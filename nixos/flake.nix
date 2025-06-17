{
  description = "NixOS configuration with flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stylix.url = "github:danth/stylix";
    # nixpkgs.url =
    #   "github:NixOS/nixpkgs/0e905f6bc12528d7e3ead3d4263530d7f13597cb";
    # nixpkgs.url = "path:/home/felix/projects/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database.url = "github:nix-community/nix-index-database";
    # nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, stylix, nixos-hardware, home-manager
    , nix-index-database,
    # stylix,
    ... }@inputs: {
      nixosConfigurations = {
        "gurke" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { flake-inputs = inputs; };
          modules = [
            stylix.nixosModules.stylix
            ./configuration.nix
            ./hardware-configuration.nix
            nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen
            nix-index-database.nixosModules.nix-index

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.felix = ./home.nix;
            }
          ];
        };
      };
      # homeConfigurations.felix = home-manager.lib.homeManagerConfiguration {
      #   # inherit pkgs;
      #
      #   modules = [
      #     nix-index-database.hmModules.nix-index
      #     # optional to also wrap and install comma
      #     # { programs.nix-index-database.comma.enable = true; }
      #   ];
      # };
    };
}
