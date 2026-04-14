{
  description = "NixOS configuration with flakes";

  inputs = {
    # get hash of currently running system: nixos-version --revision
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:NixOS/nixpkgs/6308c3b21396534d8aaeac46179c14c439a89b8a";
    # nixpkgs.url = "path:/home/felix/projects/nixpkgs";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nvf = {
      url = "github:NotAShelf/nvf";
      # You can override the input nixpkgs to follow your system's
      # instance of nixpkgs. This is safe to do as nvf does not depend
      # on a binary cache.
      inputs.nixpkgs.follows = "nixpkgs";
      # Optionally, you can also override individual plugins
      # for example:
      # inputs.obsidian-nvim.follows = "obsidian-nvim"; # <- this will use the obsidian-nvim from your inputs
    };

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

    breezy-desktop.url = "github:johnrizzo1/breezy-desktop-nixos";
  };

  outputs = {
    self,
    nixpkgs,
    stylix,
    nixos-hardware,
    nvf,
    home-manager,
    nix-index-database,
    breezy-desktop,
    ...
  } @ inputs: let
    uiFonts = import ./fonts.nix {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    };
  in {
    nixosConfigurations = {
      "gurke" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          flake-inputs = inputs;
          inherit uiFonts;
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

          breezy-desktop.nixosModules.breezy-desktop
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
