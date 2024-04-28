{
  description = "NixOS configuration with flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:NixOS/nixpkgs/838c2235558e0ffb2c36fdc9bce745c36cd3160d";
    # nixpkgs.url = "path:/home/felix/projects/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    #
    # nix-index-database.url = "github:Mic92/nix-index-database";
    # nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    # stylix.url = "github:danth/stylix";
  };

  outputs = {
    self,
    nixpkgs,
    nixos-hardware,
    home-manager,
    # nix-index-database,
    # stylix,
    ...
  } @ inputs: {
    nixosConfigurations = {
      "gurke" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          flake-inputs = inputs;
        };
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.felix = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
          # stylix.nixosModules.stylix
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
