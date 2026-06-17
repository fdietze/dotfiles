{
  config,
  lib,
  nix-index-database,
  prootBumped,
  flake-inputs,
  nvf,
  theme,
  hostLabel,
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
  # Interactive app shell: route `ssh user@host cmd` straight through; an
  # argument-less app launch gets an interactive (non-login) bash so it reads
  # ~/.bashrc with the Home-Manager config (login-inner would otherwise run it as
  # a login shell). bash auto-detects the tty — the bumped proot
  # (build.activationAfter.bumpedProot) handles the tty ioctls, so no 24.05-bash
  # pin and no forced -i are needed.
  #
  # Nix-on-Droid's app launcher (/bin/login) sources nix-on-droid-session-init.sh
  # to set up PATH (it pulls in nix.sh → ~/.nix-profile/bin), NIX_PATH, locale,
  # etc. before the user shell. Over SSH sshd never runs it, so the shell starts
  # with a bare PATH (no grep/git/…) and ~/.bashrc init breaks. Source it here
  # (idempotent via its own __NOD_SESS_INIT_SOURCED guard) so app and SSH sessions
  # get the same environment. It needs $USER, which both /bin/login and sshd set.
  appLoginShell = pkgs.writeShellScriptBin "nix-on-droid-app-login-shell" ''
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix-on-droid-session-init.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix-on-droid-session-init.sh"
    fi

    if [ "$#" -gt 0 ]; then
      exec ${pkgs.bashInteractive}/bin/bash "$@"
    fi

    exec ${pkgs.bashInteractive}/bin/bash
  '';
in {
  # Nix-on-Droid keeps Android's runtime hostname as "localhost"; the stable
  # repository identifier for this device is the flake output name "korken".
  user = {
    userName = "felix";
    shell = "${appLoginShell}/bin/nix-on-droid-app-login-shell";
  };

  nix = {
    # Default Nix: issue #495 ("getting pseudoterminal attributes: Permission
    # denied" with newer Nix builders) is the same proot tty-ioctl bug, fixed by
    # the bumped proot below — so the old Nix 2.18 pin is no longer needed.

    # Nix-on-Droid's option reference uses nix.extraOptions for nix.conf text.
    extraOptions = ''
      experimental-features = nix-command flakes
      # fdietze: the bumped proot (environment.files.prootStatic below); the
      # device cannot build it itself (nix-on-droid's cross machinery fails under
      # the on-device proot fs). numtide: prebuilt AI agents (llm-agents) so the
      # phone substitutes the Rust/Node agents instead of compiling them.
      extra-substituters = https://fdietze.cachix.org https://cache.numtide.com
      extra-trusted-public-keys = fdietze.cachix.org-1:9XRlZtrv6HM2ZPnx5Vn+DnqZ8GbxsfAQ2/FMbwiCfiY= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
    '';
  };

  # The bumped proot (prootBumped) that fixes the TCGETS2 tty-blindness (#515) is
  # installed by build.activationAfter.bumpedProot below — nix-on-droid marks
  # environment.files.prootStatic readOnly, so it can't be overridden via the
  # option. The truly clean fix is the upstream #529 merge.

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
    # Stage the bumped proot (#529) as /bin/.proot-static.new, the same way
    # nix-on-droid's own installProotStatic stages cfg.prootStatic — but pointing
    # at prootBumped instead of the readOnly app-bundled proot. The outer
    # /bin/login swaps it in on the next app start (when no proot is running).
    bumpedProot = ''
      $DRY_RUN_CMD cp ${prootBumped}/bin/proot-static /bin/.proot-static.tmp
      $DRY_RUN_CMD chmod u+w /bin/.proot-static.tmp
      $DRY_RUN_CMD mv /bin/.proot-static.tmp /bin/.proot-static.new
    '';

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
    # korken's HM profiles (shell-core, ai-agents, ...) expect the same args the
    # standalone HM config passes; nix-on-droid doesn't forward them by default.
    extraSpecialArgs = {inherit flake-inputs nvf theme hostLabel;};
    config = {lib, ...}: {
      imports = [
        ../modules/home-manager/profiles/shell-core.nix
        # vanilla (unsandboxed) agents: nono's Landlock sandbox can't init under
        # proot on this device. A proot-based sandbox is the planned follow-up.
        ../modules/home-manager/profiles/ai-agents/vanilla.nix
        ../modules/home-manager/profiles/standalone-extras.nix
        # Minimal X11 client (xterm) displaying on Termux:X11 over loopback TCP.
        ./x11.nix
      ];
    };
  };

  # Latest stateVersion listed in the current Nix-on-Droid option reference.
  system.stateVersion = "24.05";
}
