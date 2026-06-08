{
  config,
  lib,
  nix-index-database,
  pkgs,
  ...
}: {
  # Nix-on-Droid keeps Android's runtime hostname as "localhost"; the stable
  # repository identifier for this device is the flake output name "korken".
  user = {
    userName = "felix";
    shell = "${pkgs.zsh}/bin/zsh";
  };

  # Nix-on-Droid's option reference uses nix.extraOptions for nix.conf text.
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Upstream installPackages currently calls `xargs nix profile remove` even
  # when no old nix-on-droid-path profile entry exists on fresh app installs.
  build.activation = lib.mkAfter {
    installPackages = ''
      if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
        # Keep the modern-profile path, but make the removal a no-op when the
        # profile has no matching nix-on-droid-path element.
        nix_previous="$(command -v nix)"

        if nix profile list --json | ${pkgs.jq}/bin/jq -e '.elements | has("nix-on-droid-path")' >/dev/null; then
          $DRY_RUN_CMD nix profile remove $VERBOSE_ARG nix-on-droid-path
        fi

        $DRY_RUN_CMD $nix_previous profile install ${config.environment.path}

        unset nix_previous
      else
        $DRY_RUN_CMD nix-env --install ${config.environment.path}
      fi
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
    # Keep Home Manager packages out of Nix-on-Droid's system package activation
    # path; that path still mixes nix-env with modern nix profiles on fresh apps.
    useUserPackages = false;
    config = {...}: {
      imports = [
        ../modules/home-manager/profiles/shell-core.nix
        ../modules/home-manager/profiles/standalone-extras.nix
      ];
    };
  };

  # Latest stateVersion listed in the current Nix-on-Droid option reference.
  system.stateVersion = "24.05";
}
