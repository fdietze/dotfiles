{
  config,
  lib,
  nix-index-database,
  nixOnDroidNix,
  nixOnDroidAppBash,
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
  # Run the interactive app shell with bash from nixos-24.05 (nixOnDroidAppBash).
  # Newer bash/glibc issue the TCGETS2 tty ioctl, which the app-bundled proot
  # (proot-termux 2024-05-04) rejects with EACCES; stdin then looks like a
  # non-tty and readline arrow keys print ^[[A. The 24.05 toolchain uses the
  # legacy TCGETS that proot handles, so readline can enter raw mode.
  # See https://github.com/nix-community/nix-on-droid/issues/515
  appLoginShell = pkgs.writeShellScriptBin "nix-on-droid-app-login-shell" ''
    # `ssh user@host cmd` passes args through; an argument-less app launch gets
    # an interactive bash. It auto-detects the tty (see TCGETS note above), so
    # no forced -i is needed.
    if [ "$#" -gt 0 ]; then
      exec ${nixOnDroidAppBash}/bin/bash "$@"
    fi

    exec ${nixOnDroidAppBash}/bin/bash
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

      # Starship's prompt binary comes from current nixpkgs (newer glibc) and is
      # tty-blind under the app-bundled proot (TCGETS2 -> EACCES, same root cause
      # as the arrow keys / nix-on-droid#515), so it renders no usable prompt -
      # running plain `zsh` shows the same blank-prompt symptom. Use a static
      # bash PS1, which needs no terminal ioctls. Only the bash login shell is
      # pinned to the 24.05 toolchain (above); a general fix needs a newer proot.
      programs.starship.enableBashIntegration = lib.mkForce false;
      programs.bash.bashrcExtra = lib.mkAfter ''
        PS1='\u@localhost:\w\$ '
      '';
    };
  };

  # Latest stateVersion listed in the current Nix-on-Droid option reference.
  system.stateVersion = "24.05";
}
