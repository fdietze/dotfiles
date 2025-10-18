{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Download the Intel OpenVINO models
  whisper-small-models-zip = pkgs.fetchurl {
    url = "https://huggingface.co/Intel/whisper.cpp-openvino-models/resolve/main/ggml-small-models.zip";
    sha256 = "sha256-fvq9ywjsCe4kthXbn+hkJRFKRth6JdHj0U7NcZXdTp8=";
  };

  # Extract the models
  whisper-small-models = pkgs.stdenv.mkDerivation {
    name = "whisper-small-openvino-models";
    src = whisper-small-models-zip;
    nativeBuildInputs = [ pkgs.unzip pkgs.sox ];
    buildInputs = [ pkgs.openvino whisper-cpp-openvino ];

    unpackPhase = ''
      unzip $src
    '';

    installPhase = ''
      mkdir -p $out
      cp ggml-small.bin $out/
      cp ggml-small-encoder-openvino.xml $out/
      cp ggml-small-encoder-openvino.bin $out/

      # Pre-warm the OpenVINO cache by running a test transcription
      # Create a 1-second silent audio file in the current directory
      ${pkgs.sox}/bin/sox -n -r 16000 -c 1 -b 16 dummy.wav trim 0 1
      DUMMY_WAV="$PWD/dummy.wav"

      # Set up OpenVINO environment
      export LD_LIBRARY_PATH="${pkgs.openvino}/runtime/lib/intel64:$LD_LIBRARY_PATH"
      
      # Run whisper-cli to trigger cache generation
      # The cache will be created in $out/ggml-small-encoder-openvino-cache
      cd $out
      ${whisper-cpp-openvino}/bin/whisper-cli \
        -t 1 \
        -l en \
        --no-prints \
        --no-timestamps \
        --model $out/ggml-small.bin \
        -f "$DUMMY_WAV" || true
      
      # Verify the cache was created
      if [ -d "$out/ggml-small-encoder-openvino-cache" ]; then
        echo "OpenVINO cache successfully pre-generated"
      else
        echo "Warning: OpenVINO cache was not generated"
      fi
    '';
  };

  # Build whisper-cpp with OpenVINO support
  whisper-cpp-openvino = pkgs.whisper-cpp.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.openvino ];
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ pkgs.openvino ];
    cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
      "-DWHISPER_OPENVINO=ON"
      "-DOpenVINO_DIR=${pkgs.openvino}/runtime/cmake"
    ];
    doInstallCheck = false;
  });

  # Create dictate-start script
  dictate-start = pkgs.writeShellScriptBin "dictate-start" ''
    set -eu

    STATE_FILE="/tmp/dictate.state"

    # If a state file exists, check if the process is actually running.
    if [ -f "$STATE_FILE" ]; then
        PID=$(head -n 1 "$STATE_FILE")
        # If kill -0 succeeds, a process with that PID exists.
        if kill -0 "$PID" 2>/dev/null; then
            # A recording is already active, so do nothing.
            exit 0
        else
            # The state file is stale (from a crash). Clean up before proceeding.
            WAV_FILE=$(tail -n 1 "$STATE_FILE")
            rm -f "$STATE_FILE" "$WAV_FILE"
        fi
    fi

    # Create a new temporary file for the recording.
    WAV_FILE=$(mktemp /tmp/dictate-XXXXXX.wav)

    # Start recording in the background.
    ${pkgs.alsa-utils}/bin/arecord --quiet -f S16_LE -r 16000 -t wav "$WAV_FILE" &
    REC_PID=$!

    # Store the PID and the temporary file path for the stop script to find.
    echo "$REC_PID" > "$STATE_FILE"
    echo "$WAV_FILE" >> "$STATE_FILE"
  '';

  # Create dictate-stop script
  dictate-stop = pkgs.writeShellScriptBin "dictate-stop" ''
    set -eu

    # Ensure OpenVINO libraries are available
    export LD_LIBRARY_PATH="${pkgs.openvino}/runtime/lib/intel64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    STATE_FILE="/tmp/dictate.state"

    # If there is no state file, there is no recording to stop.
    if [ ! -f "$STATE_FILE" ]; then
      exit 0
    fi

    # Read the PID and WAV file path from the state file.
    PID=$(head -n 1 "$STATE_FILE")
    WAV_FILE=$(tail -n 1 "$STATE_FILE")

    # Stop the recording process. The "|| true" prevents the script from exiting
    # if the process has already died for some reason.
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true

    # Transcribe and type the result, if the audio file exists.
    if [ -f "$WAV_FILE" ]; then
      ${pkgs.xdotool}/bin/xdotool key --clearmodifiers shift
      ${pkgs.xdotool}/bin/xdotool type "$(${whisper-cpp-openvino}/bin/whisper-cli -t 8 -l auto --no-prints --no-timestamps --model ${whisper-small-models}/ggml-small.bin --output-txt - <"$WAV_FILE")"
    fi

    # Clean up the temporary files.
    rm -f "$STATE_FILE" "$WAV_FILE"
  '';

in
{
  # Install the scripts and dependencies
  home.packages = [
    dictate-start
    dictate-stop
    pkgs.alsa-utils # Provides arecord
    pkgs.xdotool # For typing the transcription
  ];

  # Configure sxhkd keybindings
  services.sxhkd = {
    enable = true;
    keybindings = {
      "Insert" = "${dictate-start}/bin/dictate-start";
      "@Insert" = "${dictate-stop}/bin/dictate-stop";
    };
  };
}
