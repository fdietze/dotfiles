{
  description = "NixOS configuration with flakes";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # get hash of currently running system: nixos-version --revision
    nixpkgs.url = "github:NixOS/nixpkgs/3e2499d5539c16d0d173ba53552a4ff8547f4539";
    # nixpkgs.url = "path:/home/felix/projects/nixpkgs";
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # nvf = {
    #   url = "github:NotAShelf/nvf";
    #   # You can override the input nixpkgs to follow your system's
    #   # instance of nixpkgs. This is safe to do as nvf does not depend
    #   # on a binary cache.
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   # Optionally, you can also override individual plugins
    #   # for example:
    #   # inputs.obsidian-nvim.follows = "obsidian-nvim"; # <- this will use the obsidian-nvim from your inputs
    # };

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

  outputs =
    {
      self,
      nixpkgs,
      stylix,
      nixos-hardware,
      # nvf,
      home-manager,
      nix-index-database,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        "gurke" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            flake-inputs = inputs;
          };
          modules = [
            stylix.nixosModules.stylix
            ./configuration.nix
            ./hardware-configuration.nix
            nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen
            nix-index-database.nixosModules.nix-index
            # nvf.homeManagerModules.default
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
