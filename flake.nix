{
  description = "NixOS configuration with flakes";

  inputs = {
    # get hash of currently running system: nixos-version --revision
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Only the Nix binary for Nix-on-Droid comes from 24.05; newer unstable Nix
    # builds currently hit Android PTY activation failures.
    nixpkgs-nix-on-droid.url = "github:NixOS/nixpkgs/nixos-24.05";
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
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nix-index-database.url = "github:nix-community/nix-index-database";
    # nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    breezy-desktop.url = "github:johnrizzo1/breezy-desktop-nixos";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Täglich aktualisierte Pakete für AI-Coding-Agents (claude-code, codex,
    # opencode, pi), neuer als der nixpkgs-Stand. Das `default`-Overlay baut
    # gegen die im Flake gepinnte nixpkgs → Treffer im Binary-Cache
    # cache.numtide.com (siehe Substituter in hosts-nixos/gurke/default.nix), kein
    # lokales Kompilieren des Rust-Codex etc.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Superpowers: harness-agnostische Agent-Skills (Agent Skills Standard) von
    # obra/superpowers. Kein Flake, nur Quell-Repo; die Skills werden in
    # modules/home-manager/profiles/superpowers.nix nach ~/.agents/skills/
    # verlinkt, sodass alle Agents (pi, claude, codex, opencode) sie sehen.
    # Update: `nix flake update superpowers`.
    superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };

  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-nix-on-droid,
    stylix,
    nixos-hardware,
    nvf,
    home-manager,
    nix-on-droid,
    nix-index-database,
    breezy-desktop,
    noctalia,
    llm-agents,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;

    # Default-Theme für headless/standalone Kontexte ohne Desktop-Spezialisierung.
    # nvf themt sich selbst über dieses Arg (kein stylix); "dark" entspricht dem
    # Build-Zeit-Verhalten der themed Desktops.
    defaultTheme = "dark";

    # Arch pro Host aus hosts-nixos/<h>/system lesen (fileContents strippt das
    # abschließende Newline); Default x86_64-linux, falls die Datei fehlt.
    # Liegt in einer Datei statt im Modul, weil nixosSystem `system` braucht,
    # bevor die Module ausgewertet werden (und uiFonts pro System hier baut).
    hostSystem = hostName: let
      f = ./hosts-nixos/${hostName}/system;
    in
      if builtins.pathExists f
      then lib.fileContents f
      else "x86_64-linux";

    uiFontsFor = system: import ./fonts.nix {pkgs = nixpkgs.legacyPackages.${system};};

    # Alle Verzeichnisse unter hosts-nixos/ außer dem kopierbaren Template werden zu
    # NixOS-Hosts. So genügt es, ein hosts-nixos/<name>/ anzulegen — scripts/
    # setup-new-host.sh muss flake.nix nie editieren.
    hostNames =
      builtins.filter (n: n != "template")
      (builtins.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts-nixos)
      ));

    mkHost = hostName: let
      system = hostSystem hostName;
      localFile = ./hosts-nixos/${hostName}/local.nix;
      # Maschinen-lokale Identifier (Disk-UUIDs etc.) nur, wenn der Host eine
      # local.nix mitbringt; der generische Template-Host hat keine.
      hostLocal =
        if builtins.pathExists localFile
        then import localFile
        else {};
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          flake-inputs = inputs;
          inherit hostLocal;
          uiFonts = uiFontsFor system;
        };
        modules = [
          stylix.nixosModules.stylix
          ./hosts-nixos/${hostName}/default.nix
          ./hosts-nixos/${hostName}/hardware-configuration.nix
          nix-index-database.nixosModules.nix-index
          home-manager.nixosModules.home-manager
          {
            # AI-Agents (claude-code, codex, opencode, pi) aus llm-agents.nix
            # statt nixpkgs; greift über useGlobalPkgs auch in Home Manager.
            nixpkgs.overlays = [llm-agents.overlays.default];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              nix-index-database.homeModules.nix-index
              noctalia.homeModules.default
            ];
            home-manager.users.felix = ./hosts-nixos/${hostName}/home.nix;
          }
        ];
      };

    # Standalone Home Manager: schnelle Shell-Variante auf beliebiger Box,
    # importiert nur den portablen shell-core (kein Desktop, kein stylix).
    mkHome = system: username:
      home-manager.lib.homeManagerConfiguration {
        # Eigene pkgs-Instanz mit allowUnfree, weil standalone Home Manager —
        # anders als der NixOS-Host — keine nixpkgs.config erbt; shell-core zieht
        # über packages-cli/Aliases u.a. unfreie Pakete (unrar, claude-code).
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          # Eigene pkgs-Instanz erbt keine Host-Overlays; AI-Agents hier separat.
          overlays = [llm-agents.overlays.default];
        };
        extraSpecialArgs = {
          flake-inputs = inputs;
          nvf = nvf;
          theme = defaultTheme;
          uiFonts = uiFontsFor system;
        };
        modules = [
          nix-index-database.homeModules.nix-index
          ./modules/home-manager/profiles/shell-core.nix
          ./modules/home-manager/profiles/ai-agents # sandboxed; mkHome pkgs has the overlay
          ./modules/home-manager/profiles/standalone-extras.nix
          # shell-core setzt felix nur per mkDefault; auf fremden Boxen mit
          # anderem User (z.B. Fly Sprites, User "sprite") hier überschreiben.
          {
            home.username = username;
            home.homeDirectory = "/home/${username}";
          }
        ];
      };

    mkNixOnDroid = deviceName:
      nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [./hosts-nix-on-droid/${deviceName}.nix];
        extraSpecialArgs = {
          inherit nix-index-database;
          # Bumped proot (PR nix-on-droid#529) that fixes the TCGETS2 tty
          # blindness (#515). Built by CI on x86 and substituted from cachix;
          # korken pins it via environment.files.prootStatic. See proot-bumped/.
          prootBumped = import ./hosts-nix-on-droid/proot-bumped {inherit nixpkgs;};
          # Forwarded to korken's home-manager modules (see korken.nix
          # home-manager.extraSpecialArgs): shell-core needs nvf, packages-cli/
          # yazi need theme, ai-agents/skills needs flake-inputs.
          flake-inputs = inputs;
          nvf = nvf;
          theme = defaultTheme;
          # Stable prompt label: proot reports the OS hostname as "localhost".
          hostLabel = deviceName;
        };

        # The upstream flake template recommends the Nix-on-Droid overlay; this
        # pkgs instance also permits the same unfree CLI tools as standalone HM.
        pkgs = import nixpkgs {
          system = "aarch64-linux";
          # llm-agents overlay so korken can install (vanilla) AI agents, the
          # same pkgs.llm-agents.* the NixOS/standalone configs use.
          overlays = [nix-on-droid.overlays.default llm-agents.overlays.default];
          config.allowUnfree = true;
        };

        home-manager-path = home-manager.outPath;
      };
  in {
    # gurke (und jeder weitere hosts-nixos/<name>/) wird auto-entdeckt.
    nixosConfigurations = lib.genAttrs hostNames mkHost;

    # "nix run home-manager -- switch --flake .#felix@<arch>"
    homeConfigurations = {
      "felix@x86_64-linux" = mkHome "x86_64-linux" "felix";
      "felix@aarch64-linux" = mkHome "aarch64-linux" "felix";
      # Fly Sprite (https://docs.sprites.dev/): Ubuntu-VM, fester User "sprite".
      "sprite@x86_64-linux" = mkHome "x86_64-linux" "sprite";
    };

    # "nix-on-droid switch --flake .#korken"
    nixOnDroidConfigurations = {
      korken = mkNixOnDroid "korken";
    };
  };
}
