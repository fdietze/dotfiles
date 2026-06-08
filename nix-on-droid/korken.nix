{
  config,
  lib,
  nix-index-database,
  nixOnDroidNix,
  pkgs,
  ...
}: {
  # Nix-on-Droid keeps Android's runtime hostname as "localhost"; the stable
  # repository identifier for this device is the flake output name "korken".
  user = {
    userName = "felix";
    shell = "${pkgs.zsh}/bin/zsh";
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
