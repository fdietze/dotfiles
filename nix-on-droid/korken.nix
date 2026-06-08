{
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
