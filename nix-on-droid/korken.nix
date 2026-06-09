{
  config,
  lib,
  nix-index-database,
  nixOnDroidNix,
  pkgs,
  ...
}: let
  # https://github.com/nix-community/nix-on-droid/wiki/SSH-access
  sshdDirectory = "${config.user.home}/.ssh/nix-on-droid-sshd";
  sshdPort = 8022;
  sshdAuthorizedKeys = ./ssh/authorized_keys;
  sshdConfig = pkgs.writeText "nix-on-droid-sshd_config" ''
    Port ${toString sshdPort}
    ListenAddress 0.0.0.0
    HostKey ${sshdDirectory}/ssh_host_ed25519_key
    AuthorizedKeysFile ${config.user.home}/.ssh/authorized_keys
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    PermitRootLogin no
    PidFile ${sshdDirectory}/sshd.pid
    UsePAM no
    Subsystem sftp internal-sftp
  '';
  appLoginShell = pkgs.writeShellScriptBin "nix-on-droid-app-login-shell" ''
    # Nix-on-Droid currently starts the app shell through proot without bash
    # detecting an interactive stdin, so force interactivity for a visible prompt.
    if [ "$#" -gt 0 ]; then
      exec ${pkgs.bashInteractive}/bin/bash "$@"
    fi

    exec ${pkgs.bashInteractive}/bin/bash -i
  '';
in {
  # Nix-on-Droid keeps Android's runtime hostname as "localhost"; the stable
  # repository identifier for this device is the flake output name "korken".
  user = {
    userName = "felix";
    shell = "${appLoginShell}/bin/nix-on-droid-app-login-shell";
  };

  nix = {
    # Nix-on-Droid issue #495 tracks newer Nix builders failing to open PTYs on
    # Android; keep the app's proven Nix 2.18 line while using current modules.
    package = nixOnDroidNix;

    # Nix-on-Droid's option reference uses nix.extraOptions for nix.conf text.
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Upstream installPackages currently calls `xargs nix profile remove` even
  # when no old nix-on-droid-path profile entry exists on fresh app installs.
  build.activation = lib.mkAfter {
    sshd = ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 700 -d "${config.user.home}/.ssh"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 700 -d "${sshdDirectory}"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 600 "${sshdAuthorizedKeys}" "${config.user.home}/.ssh/authorized_keys"

      if [[ ! -e "${sshdDirectory}/ssh_host_ed25519_key" ]]; then
        $VERBOSE_ECHO "Generating Nix-on-Droid SSH host key..."
        $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f "${sshdDirectory}/ssh_host_ed25519_key" -N ""
      fi

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 600 "${sshdConfig}" "${sshdDirectory}/sshd_config"
    '';

    installPackages = ''
      if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
        # Keep the modern-profile path, but make the removal a no-op when the
        # profile has no matching nix-on-droid-path element.
        nix_previous="$(command -v nix)"

        profile_entry="$(${pkgs.jq}/bin/jq -r '
          def nix_on_droid_path:
            (.storePaths // [])[]? | select(endswith("-nix-on-droid-path"));

          if (.elements | type) == "object" then
            if (.elements | has("nix-on-droid-path")) then "nix-on-droid-path" else empty end
          else
            ([.elements[]? | nix_on_droid_path][0] // empty)
          end
        ' < <(nix profile list --json))"

        if [[ -n "$profile_entry" ]]; then
          $DRY_RUN_CMD nix profile remove $VERBOSE_ARG "$profile_entry"
        fi

        $DRY_RUN_CMD $nix_previous profile install ${config.environment.path}

        unset profile_entry
        unset nix_previous
      else
        $DRY_RUN_CMD nix-env --install ${config.environment.path}
      fi
    '';
  };

  environment.packages = [
    pkgs.openssh
    (pkgs.writeShellScriptBin "sshd-start" ''
      set -eu
      echo "Starting sshd on 0.0.0.0:${toString sshdPort}. Stop it with Ctrl-C."
      exec ${pkgs.openssh}/bin/sshd -D -e -f ${lib.escapeShellArg "${sshdDirectory}/sshd_config"}
    '')
  ];

  build.activationBefore = lib.mkAfter {
    # `useUserPackages` is the Nix-on-Droid/Home Manager integration path for
    # packages, but its legacy priority hook still assumes a nix-env profile.
    setPriorityHomeManagerPath = ''
      :
    '';
  };

  build.activationAfter = lib.mkAfter {
    # Nix-on-Droid writes USER into the next login session, but Home Manager's
    # sanity checks run during the current activation process.
    homeManager = ''
      USER=${lib.escapeShellArg config.user.userName} \
        HOME=${lib.escapeShellArg config.user.home} \
        HOME_MANAGER_BACKUP_EXT=${lib.escapeShellArg config.home-manager.backupFileExtension} \
        ${config.home-manager.config.home.activationPackage}/activate
    '';
  };

  home-manager = {
    backupFileExtension = "hm-bak";
    # shell-core enables comma through nix-index-database, so load the matching
    # Home Manager module explicitly in this Nix-on-Droid integration path.
    sharedModules = [nix-index-database.homeModules.nix-index];
    useGlobalPkgs = true;
    # Let Nix-on-Droid install Home Manager packages through environment.packages
    # so Home Manager does not fight nix-on-droid-path in the same user profile.
    useUserPackages = true;
    config = {lib, ...}: {
      imports = [
        ../modules/home-manager/profiles/shell-core.nix
        ../modules/home-manager/profiles/standalone-extras.nix
      ];

      # The Android app terminal needs a prompt that is visible even when the
      # richer workstation prompt stack misdetects terminal capabilities.
      programs.starship.enableBashIntegration = lib.mkForce false;
      programs.bash.bashrcExtra = lib.mkAfter ''
        PS1='\u@localhost:\w\$ '
      '';

      # Android-specific .inputrc to override workstation vi-mode.
      # Emacs mode is required here because the proot terminal timing bugs break
      # readline vi-mode arrow key escape sequence detection.
      home.file.".inputrc".source = lib.mkForce (pkgs.writeText "nix-on-droid-inputrc" ''
        # Managed by Nix-on-Droid/korken.
        # Emacs mode is used to bypass proot timing bugs that break vi-mode arrow keys.
        set editing-mode emacs
      '');
    };
  };

  # Latest stateVersion listed in the current Nix-on-Droid option reference.
  system.stateVersion = "24.05";
}
