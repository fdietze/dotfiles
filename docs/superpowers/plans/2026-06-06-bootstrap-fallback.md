# Bootstrap & Shell-Fallback für neue Hosts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drei Installations-Einstiegspunkte schaffen — standalone Home-Manager-Shell auf beliebiger Box, definierter NixOS-Host, und ein generischer Template-Host für noch nicht konfigurierte Maschinen — ohne `gurke` zu verändern.

**Architecture:** Zuerst einen portablen `profiles/shell-core.nix` aus `shared.nix` herausziehen (gurke bleibt bitidentisch, mit `nvd` verifiziert). Dann das Flake auf Auto-Discovery aus `hosts/*` plus `mkHost`/`mkHome`-Helper umstellen (multi-arch via `hosts/<h>/system`-Datei). Schließlich Template-Host, Setup-Script und README ergänzen.

**Tech Stack:** Nix Flakes, Home Manager (als NixOS-Modul und standalone), nvf, Bash, `nixos-generate-config`, `nvd`.

**Spec:** `docs/superpowers/specs/2026-06-06-bootstrap-fallback-design.md`

---

## Verifikations-Konvention (für alle Refactor-Tasks)

In Nix gibt es keine Unit-Tests; der "Test" ist ein reproduzierbarer Build plus `nvd diff`. Für jeden Refactor-Schritt, der gurke **nicht** verändern darf, gilt:

- **Referenz bauen (vor der ersten Änderung, einmalig):**
  ```bash
  cd ~/projects/dotfiles
  nix build .#nixosConfigurations.gurke.config.system.build.toplevel \
    --out-link /tmp/gurke-before
  ```
- **Nach der Änderung vergleichen:**
  ```bash
  nix build .#nixosConfigurations.gurke.config.system.build.toplevel \
    --out-link /tmp/gurke-after
  nix run nixpkgs#nvd -- diff /tmp/gurke-before /tmp/gurke-after
  ```
  **Erwartet:** `nvd` meldet keine Paket- oder Versionsänderungen (leere Differenz). Jede Abweichung = Partitionsfehler, der vor dem Commit behoben werden muss.

`nix build` aktiviert nichts (kein `nixos-rebuild switch`). Das ist erlaubt; aktivierende Rebuilds macht der Nutzer manuell.

---

## File Structure

- `modules/home-manager/profiles/shell-core.nix` — **neu.** Portabler, headless-tauglicher Home-Manager-Core: importiert die desktop-unabhängigen Sub-Module und enthält die Shell-Essentials aus dem bisherigen `shared.nix`-Body. Default `theme = "dark"`. Kein stylix, keine GUI-Terminals.
- `modules/home-manager/profiles/packages-cli.nix` — **neu.** CLI-/TUI-/Editor-Paketsubset, herausgelöst aus `packages.nix`.
- `modules/home-manager/packages.nix` — **modifiziert.** Behält alle nicht-Core-Pakete (GUI, schwere Medien, arch-spezifische).
- `modules/home-manager/shared.nix` — **modifiziert.** Importiert `profiles/shell-core.nix`, behält den GUI-/Desktop-Teil.
- `flake.nix` — **modifiziert.** Auto-Discovery + `mkHost`/`mkHome`, `homeConfigurations."felix@<arch>"`.
- `hosts/gurke/system` — **neu.** Enthält `x86_64-linux`.
- `hosts/template/{default.nix,home.nix,.gitkeep-hw}` — **neu.** Minimaler desktop-freier Host ohne `hardware-configuration.nix`.
- `scripts/setup-new-host.sh` — **neu.** Bootstrap-Script.
- `README.md` — **modifiziert.** Drei Installationspfade.

---

## Task 1: CLI-Paketsubset aus packages.nix herauslösen

**Files:**
- Create: `modules/home-manager/profiles/packages-cli.nix`
- Modify: `modules/home-manager/packages.nix`
- Modify: `modules/home-manager/shared.nix`

**Prinzip:** `packages-cli.nix` und `packages.nix` müssen zusammen exakt dieselbe Paketmenge ergeben wie das heutige `packages.nix` (Partition, nichts hinzufügen/entfernen). `nvd` ist das Sicherheitsnetz.

- [ ] **Step 1: Referenz-Build erstellen**

```bash
cd ~/projects/dotfiles
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --out-link /tmp/gurke-before
```
Erwartet: Build erfolgreich, `/tmp/gurke-before` existiert.

- [ ] **Step 2: `profiles/packages-cli.nix` anlegen**

Headless-/CLI-/Editor-Pakete. Diese Liste ist die Core-Menge (bei Unsicherheit bleibt ein Paket in `packages.nix`). **Nicht** enthalten: `sprite` (nur x86_64 → bricht den aarch64-Core), GUI-Apps, schwere Medien (ffmpeg-full, imagemagick, mediainfo, whisper-cpp, espeak, texliveSmall, pandoc), xcwd-home (desktop), polybar/lxappearance/qt-styles (theming).

```nix
{pkgs, ...}: {
  home.packages =
    (with pkgs; [
      # shell / TUI essentials
      tmux
      zellij
      wget
      curl
      htop
      atop
      btop
      ncdu
      gdu
      duf
      pv
      bat
      lazygit
      tig
      git-fire
      dasel
      jq
      fd
      tldr
      gh
      tmate
      upterm
      entr
      socat
      ripgrep-all
      ouch
      atool
      p7zip
      zip
      unzip
      unrar
      tree
      moreutils
      netcat
      nmap
      calc
      inotify-tools
      lsof
      psmisc
      file
      smem
      dnsutils
      kondo
      yt-dlp
      flyctl
      miniserve
      gnumake
      gnupg
      openssl
      man
      exiftool
      qrencode
      trashy
      neovim-remote # used by nvim theme switcher
      bubblewrap
      nono
      pgcli
      sqlite-interactive
      timewarrior
      speedtest-cli
      nethogs
      # neovim editing stack
      clang # cc for nvim treesitter
      tree-sitter
      sccache
      rust-script
      python3
      nodejs
      opencode
      # language servers / formatters / linters
      nixd
      lua-language-server
      luarocks
      stylua
      lua
      nil
      nixfmt
      statix
      gopls
      gofumpt
      gomodifytags
      impl
      delve
      tailwindcss-language-server
      taplo
      docker-ls
      kotlin
      kotlin-language-server
      ktlint
      ruff
      pyright
      hadolint
      vtsls
      vscode-langservers-extracted
      bash-language-server
      shellcheck
      shfmt
      marksman
      markdownlint-cli2
      rtk
    ])
    ++ [
      # context-mode MCP plugin (not in nixpkgs). Bump version+hash:
      #   nix-prefetch-url https://registry.npmjs.org/context-mode/-/context-mode-<ver>.tgz --type sha512
      (pkgs.callPackage ../bin/context-mode.nix {})

      # Wrap `claude` in the nono sandbox so it can't touch the rest of the system.
      # `nice -n 19` + `ionice -c 3` keep claude from starving interactive work of
      # CPU/IO when it spawns heavy subprocesses (builds, ripgrep over the tree).
      (pkgs.writeShellScriptBin "claude" ''
        export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.nono}/bin/nono run --profile claude -- \
          ${pkgs.claude-code}/bin/claude --dangerously-skip-permissions "$@"
      '')

      # Escape hatch: stock Claude on the host, with its own sandbox + permission prompts intact.
      (pkgs.writeShellScriptBin "vanilla-claude" ''
        export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.claude-code}/bin/claude "$@"
      '')
    ];
}
```
Hinweis: Pfad zu `context-mode.nix` ist `../bin/context-mode.nix` (eine Ebene höher als `profiles/`).

- [ ] **Step 3: Die nach `packages-cli.nix` verschobenen Einträge aus `packages.nix` entfernen**

Lösche in `modules/home-manager/packages.nix` exakt jene Pakete aus dem `with pkgs; [ … ]`-Block und dem `++ [ … ]`-Block, die jetzt in `packages-cli.nix` stehen (Step 2). In `packages.nix` verbleiben u. a.: `pistol`, `playerctl`, `pamixer`, `imagemagick`, `ffmpeg-full`, `mediainfo`, `xcolor`, `chafa`, `dragon-drop`, `pandoc`, `texliveSmall`, `diff-so-fancy`, `espeak`, `whisper-cpp`, `alsa-utils`, `nrfconnect`, `overskride`, `typst`, `pulsemixer`, `bluetuith`, `arandr`, `wdisplays`, alle `# system tools` (pciutils/usbutils/hdparm/gparted/exfatprogs/ntfs3g/ntfsprogs/testdisk/lm_sensors/linuxPackages.cpupower/xkill/wirelesstools/xbacklight/acpi/samba/cifs-utils/jmtpfs/smartmontools), `pavucontrol`, `mimeo`, `xdotool`, `macchanger`, `ghostscript`, `mermaid-cli`, `devbox`, `visualvm`, `coursier`, `devenv`, `meld`, der gesamte `# themeing`-Block, alle `# guis`, sowie `xcwd-home` und `sprite` im `++ [ … ]`-Block.

Stelle sicher, dass `packages.nix` weiterhin gültiges Nix ist (z. B. der `xdg.desktopEntries.signal`-Block am Ende bleibt unangetastet).

- [ ] **Step 4: `packages-cli.nix` in `shared.nix` einhängen**

In `modules/home-manager/shared.nix` im `imports`-Block ergänzen (temporär; wird in Task 2 in den Core verschoben):

```nix
  imports = [
    ./shell.nix
    ./dotfiles.nix
    ./git.nix
    ./yazi.nix
    ./xdg.nix
    ./packages.nix
    ./profiles/packages-cli.nix
    ./stylix.nix
    ./theme-switching.nix
    ./icon-themes.nix
    ./launchers.nix
    ./wallpaper.nix
    ./nvf.nix
  ];
```

- [ ] **Step 5: Bitidentität verifizieren**

```bash
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --out-link /tmp/gurke-after
nix run nixpkgs#nvd -- diff /tmp/gurke-before /tmp/gurke-after
```
Erwartet: keine Differenz. Bei Abweichung: fehlendes/zusätzliches Paket in der Partition korrigieren, Step 5 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/profiles/packages-cli.nix modules/home-manager/packages.nix modules/home-manager/shared.nix
git commit -m "refactor(hm): split CLI package subset into profiles/packages-cli.nix

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: shell-core.nix anlegen und portable Imports relocieren

**Files:**
- Create: `modules/home-manager/profiles/shell-core.nix`
- Modify: `modules/home-manager/shared.nix`

**Prinzip:** Reine Verschiebung von Import-Zeilen → bitidentisch.

- [ ] **Step 1: `profiles/shell-core.nix` mit den portablen Imports anlegen**

```nix
# Portabler, headless-tauglicher Home-Manager-Core. Wird sowohl von shared.nix
# (volle Desktop-Konfiguration) als auch standalone (homeConfigurations,
# Template-Host) importiert. Enthält nur desktop-unabhängige Module und
# Shell-Essentials. Default-Theme "dark"; kein stylix, keine GUI-Terminals.
{...}: {
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
    ../nvf.nix
  ];
}
```
Hinweis: Aus `profiles/` sind die Geschwister-Module mit `../` zu referenzieren; `packages-cli.nix` liegt im selben `profiles/`-Ordner (`./`).

- [ ] **Step 2: Diese Imports aus `shared.nix` entfernen und durch den Core ersetzen**

`modules/home-manager/shared.nix` `imports`-Block wird zu:

```nix
  imports = [
    ./profiles/shell-core.nix
    ./xdg.nix
    ./packages.nix
    ./stylix.nix
    ./theme-switching.nix
    ./icon-themes.nix
    ./launchers.nix
    ./wallpaper.nix
  ];
```
(`shell.nix`, `dotfiles.nix`, `git.nix`, `yazi.nix`, `packages-cli.nix`, `nvf.nix` sind jetzt im Core.)

- [ ] **Step 3: Bitidentität verifizieren**

```bash
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --out-link /tmp/gurke-after
nix run nixpkgs#nvd -- diff /tmp/gurke-before /tmp/gurke-after
```
Erwartet: keine Differenz.

- [ ] **Step 4: Commit**

```bash
git add modules/home-manager/profiles/shell-core.nix modules/home-manager/shared.nix
git commit -m "refactor(hm): introduce profiles/shell-core.nix with portable imports

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Shell-Essential-Settings aus shared.nix-Body in den Core verschieben

**Files:**
- Modify: `modules/home-manager/shared.nix`
- Modify: `modules/home-manager/profiles/shell-core.nix`

**Prinzip:** Verbatim-Verschiebung definierter Attribut-Blöcke. Bitidentisch.

**In den Core (`shell-core.nix`) verschieben** (verbatim aus `shared.nix` ausschneiden):
- `home.username`, `home.homeDirectory`
- der `repoDir`-`let`-Binding (wird von sessionPath/aliases gebraucht)
- `home.sessionPath`
- `home.sessionVariables`
- `programs.bat.enable`
- `programs.direnv` (ganzer Block)
- `home.shell.enableIonIntegration`
- `home.shellAliases` (ganzer Block)
- `programs.ion` (ganzer Block)
- `programs.nix-index` + `programs.nix-index-database.comma.enable`
- `programs.fzf`, `programs.ripgrep`, `programs.eza`
- `services.ssh-agent.enable`
- `home.stateVersion`
- `programs.home-manager.enable`

**In `shared.nix` bleiben** (GUI/Desktop): GUI-Terminals (ghostty/alacritty/kitty/wezterm + kitty-config-check), `services.podman`, `programs.fish`, `services.copyq`, `services.udiskie`, `services.espanso`, `services.playerctld`, `services.blueman-applet` + autostart-Maskierung, `services.mpris-proxy`, `programs.keepassxc`, `gtk`, `home.pointerCursor`, `programs.librewolf`, `programs.qutebrowser`, `programs.chromium`, `services.keynav`.

- [ ] **Step 1: Blöcke verschieben**

Schneide die oben gelisteten Attribute aus dem Body von `modules/home-manager/shared.nix` aus und füge sie in den Body von `modules/home-manager/profiles/shell-core.nix` ein. Passe die Funktions-Header an:

`shell-core.nix` Header (braucht `config`, `pkgs`, `lib`):
```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
in {
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
    ../nvf.nix
  ];

  # … hier die verschobenen Attribut-Blöcke …
}
```

`shared.nix` Header bleibt wie gehabt (`config, lib, pkgs, theme, uiFonts, flake-inputs`), aber der `repoDir`-let-Binding wird entfernt, falls er nach dem Verschieben in `shared.nix` nicht mehr referenziert wird. (Prüfen: greppe `repoDir` in `shared.nix` nach dem Schnitt; wird er noch gebraucht, behalte ihn auch dort.)

- [ ] **Step 2: Bitidentität verifizieren**

```bash
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --out-link /tmp/gurke-after
nix run nixpkgs#nvd -- diff /tmp/gurke-before /tmp/gurke-after
```
Erwartet: keine Differenz. (Falls `nix build` mit „attribute defined in both …" o. ä. fehlschlägt: ein Block wurde dupliziert statt verschoben — aus `shared.nix` vollständig entfernen.)

- [ ] **Step 3: Commit**

```bash
git add modules/home-manager/shared.nix modules/home-manager/profiles/shell-core.nix
git commit -m "refactor(hm): move shell-essential settings into shell-core

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Flake auf Auto-Discovery + mkHost umstellen

**Files:**
- Modify: `flake.nix`
- Create: `hosts/gurke/system`

- [ ] **Step 1: Arch-Marker für gurke anlegen**

```bash
printf 'x86_64-linux\n' > hosts/gurke/system
```

- [ ] **Step 2: `flake.nix` `outputs` umbauen**

Ersetze den `let … in { nixosConfigurations = { "gurke" = …; }; … }`-Teil durch Auto-Discovery. Vollständiger neuer `outputs`-Body:

```nix
  outputs = {
    self,
    nixpkgs,
    stylix,
    nixos-hardware,
    nvf,
    home-manager,
    nix-index-database,
    breezy-desktop,
    noctalia,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;

    # Default-Theme für headless/standalone Kontexte ohne Spezialisierung.
    defaultTheme = "dark";

    # Arch pro Host aus hosts/<h>/system lesen; Default x86_64-linux.
    hostSystem = hostName: let
      f = ./hosts/${hostName}/system;
    in
      if builtins.pathExists f
      then lib.strings.trim (builtins.readFile f)
      else "x86_64-linux";

    uiFontsFor = system:
      import ./fonts.nix {pkgs = nixpkgs.legacyPackages.${system};};

    # Alle Verzeichnisse unter hosts/ außer dem Template werden zu Hosts.
    hostNames =
      builtins.filter (n: n != "template")
      (builtins.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      ));

    mkHost = hostName: let
      system = hostSystem hostName;
      localFile = ./hosts/${hostName}/local.nix;
      hostLocal =
        if builtins.pathExists localFile
        then import localFile
        else {};
      uiFonts = uiFontsFor system;
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          flake-inputs = inputs;
          inherit hostLocal uiFonts;
        };
        modules = [
          stylix.nixosModules.stylix
          ./hosts/${hostName}/default.nix
          ./hosts/${hostName}/hardware-configuration.nix
          nix-index-database.nixosModules.nix-index
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              nix-index-database.homeModules.nix-index
              noctalia.homeModules.default
            ];
            home-manager.users.felix = ./hosts/${hostName}/home.nix;
          }
        ];
      };

    mkHome = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          flake-inputs = inputs;
          nvf = nvf;
          theme = defaultTheme;
          uiFonts = uiFontsFor system;
        };
        modules = [
          nix-index-database.homeModules.nix-index
          ./modules/home-manager/profiles/shell-core.nix
        ];
      };
  in {
    nixosConfigurations =
      lib.genAttrs hostNames mkHost;

    homeConfigurations = {
      "felix@x86_64-linux" = mkHome "x86_64-linux";
      "felix@aarch64-linux" = mkHome "aarch64-linux";
    };
  };
```

Hinweis: `gurke` braucht weiterhin `nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen`. Da `mkHost` generisch ist, wandert dieser hardware-spezifische Import in gurkes eigene Modulliste: ergänze ihn in `hosts/gurke/default.nix` über einen `imports`-Eintrag bzw. (sauberer) belasse die Generik und füge in `mkHost` **keinen** nixos-hardware-Import ein — stattdessen importiert `hosts/gurke/default.nix` ihn selbst. Siehe Step 3.

- [ ] **Step 3: nixos-hardware-Import in gurke verlagern**

`mkHost` (Step 2) importiert bewusst kein `nixos-hardware`. Damit gurke identisch bleibt, muss gurke das Lenovo-Modul selbst ziehen. In `hosts/gurke/default.nix` im `imports`-Block ergänzen (flake-inputs ist als specialArg verfügbar):

```nix
  imports = [
    flake-inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen
    ../../modules/options.nix
    ./power.nix
    # … bestehende Imports …
  ];
```
`flake-inputs` ist bereits in der Argumentliste von `hosts/gurke/default.nix` (Zeile mit `flake-inputs,`). Prüfen und ggf. ergänzen.

- [ ] **Step 4: Bitidentität von gurke verifizieren**

```bash
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --out-link /tmp/gurke-after
nix run nixpkgs#nvd -- diff /tmp/gurke-before /tmp/gurke-after
```
Erwartet: keine Differenz. (Der `nixos-hardware`-Import landet jetzt über gurkes eigene Modulliste in derselben Konfiguration.)

- [ ] **Step 5: Flake-Auswertung prüfen**

```bash
nix flake show 2>&1 | grep -E "nixosConfigurations|gurke|homeConfigurations|felix@"
```
Erwartet: `nixosConfigurations.gurke` und `homeConfigurations."felix@x86_64-linux"` / `"felix@aarch64-linux"` erscheinen.

- [ ] **Step 6: Commit**

```bash
git add flake.nix hosts/gurke/system hosts/gurke/default.nix
git commit -m "flake: auto-discover hosts from hosts/*, add mkHost/mkHome helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Standalone homeConfigurations zum Bauen bringen

**Files:**
- Modify: `flake.nix` (nur falls fehlende Modul-Argumente auftauchen)
- Modify: `modules/home-manager/profiles/shell-core.nix` (nur falls ein Modul einen Default braucht)

**Prinzip:** `mkHome` aus Task 4 existiert; hier wird der Build grün gemacht.

- [ ] **Step 1: x86_64-Home-Config bauen**

```bash
nix build .#homeConfigurations."felix@x86_64-linux".activationPackage --out-link /tmp/home-x86
```
Erwartet: Build erfolgreich. Mögliche Fehler und Fixes:
- *„called without required argument 'theme'/'nvf'/'uiFonts'"* → fehlt in `mkHome`-`extraSpecialArgs`; ergänzen (in Task 4 bereits gesetzt — prüfen).
- *„The option `…' does not exist"* → ein Core-Modul referenziert eine NixOS-/Desktop-Option, die standalone fehlt. Betroffenes Modul identifizieren; entweder den Verursacher aus dem Core nehmen oder den Wert konditional machen. Kandidaten: `nvf.nix` (systemd-Targets), `dotfiles.nix`.

- [ ] **Step 2: aarch64-Home-Config evaluieren**

```bash
nix build .#homeConfigurations."felix@aarch64-linux".activationPackage \
  --out-link /tmp/home-arm --dry-run
```
Erwartet: Evaluation ohne Fehler (Dry-Run vermeidet teure Cross-Builds). Falls ein Paket `meta.platforms` auf x86_64 beschränkt (z. B. versehentlich mitgenommenes `sprite`), Eval-Fehler → das Paket aus `packages-cli.nix` entfernen (gehört nach `packages.nix`).

- [ ] **Step 3: Inhalt sanity-checken**

```bash
ls -l /tmp/home-x86/home-path/bin/ | grep -E "nvim|zsh|git|fzf|rg|eza|tmux" | head
```
Erwartet: `nvim`, `git`, `fzf`, `tmux` etc. vorhanden; **keine** GUI-Terminals (`kitty`/`alacritty`) und kein `keepassxc`.

- [ ] **Step 4: Commit**

```bash
git add flake.nix modules/home-manager/profiles/shell-core.nix
git commit -m "flake: make standalone homeConfigurations build for both arches

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
(Falls in Step 1/2 keine Änderungen nötig waren, entfällt dieser Commit.)

---

## Task 6: Template-Host anlegen

**Files:**
- Create: `hosts/template/default.nix`
- Create: `hosts/template/home.nix`
- Create: `hosts/template/.gitkeep-hardware` (Doku-Platzhalter)

**Prinzip:** Auto-Discovery überspringt `template` (Task 4, Step 2). Der Host wird also nicht als `nixosConfiguration` ausgewertet, ist aber kopierbereit.

- [ ] **Step 1: `hosts/template/default.nix` schreiben**

```nix
# Generischer, desktop-freier Fallback-Host für noch nicht konfigurierte
# Maschinen. Wird von scripts/setup-new-host.sh nach hosts/<hostname>/ kopiert;
# hardware-configuration.nix wird dort per `nixos-generate-config
# --show-hardware-config` erzeugt. Wer den Host behalten will, ergänzt Desktops
# und local.nix analog zu hosts/gurke/.
{
  pkgs,
  lib,
  ...
}: {
  # Flakes/nix-command dauerhaft aktiv.
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Bootloader-Default für die meisten UEFI-Maschinen. Auf BIOS-only-Systemen
  # nach dem Kopieren anpassen.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  services.openssh.enable = true;

  users.users.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # Kein my.desktop / my.theme: der Template-Host hat keinen Desktop.
  system.stateVersion = lib.mkDefault "26.05";
}
```

- [ ] **Step 2: `hosts/template/home.nix` schreiben**

```nix
# Home Manager für den Fallback-Host: nur der portable Shell-Core, kein Desktop.
{...}: {
  imports = [
    ../../modules/home-manager/profiles/shell-core.nix
  ];
}
```

- [ ] **Step 3: Hardware-Platzhalter dokumentieren**

```bash
cat > hosts/template/.gitkeep-hardware <<'EOF'
hardware-configuration.nix wird NICHT eingecheckt. scripts/setup-new-host.sh
erzeugt sie beim Kopieren dieses Templates via:
  nixos-generate-config --show-hardware-config > hosts/<hostname>/hardware-configuration.nix
EOF
```

- [ ] **Step 4: Flake bleibt auswertbar (template wird übersprungen)**

```bash
nix flake show 2>&1 | grep -E "template|gurke"
```
Erwartet: `gurke` erscheint, `template` erscheint **nicht** als nixosConfiguration.

- [ ] **Step 5: Commit**

```bash
git add hosts/template/
git commit -m "hosts: add desktop-free template host for new machines

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Setup-Script schreiben

**Files:**
- Create: `scripts/setup-new-host.sh`

- [ ] **Step 1: Script schreiben**

```bash
#!/usr/bin/env bash
# setup-new-host.sh — Bootstrap dieses NixOS/Home-Manager-Setups auf einer
# laufenden NixOS-Maschine. Gedacht für:
#   bash <(curl -fsSL https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh)
# Process Substitution hält stdin am Terminal, damit interaktive Abfragen
# funktionieren. Das Script editiert kein Nix und ist sudo-frei bis zum
# optionalen Rebuild.
set -euo pipefail

REPO_URL="https://github.com/fdietze/dotfiles.git"
REPO_DIR="$HOME/projects/dotfiles"

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. git sicherstellen (auf minimalem NixOS evtl. nicht installiert).
if ! command -v git >/dev/null 2>&1; then
  say "git nicht gefunden — starte unter nix-shell -p git neu."
  exec nix-shell -p git --run "bash <(curl -fsSL $REPO_URL/raw/master/scripts/setup-new-host.sh)"
fi

# 2. Repo klonen (falls noch nicht vorhanden).
if [ -d "$REPO_DIR/.git" ]; then
  say "Repo existiert bereits: $REPO_DIR"
else
  say "Klone Repo nach $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Aktuelles System (z. B. x86_64-linux / aarch64-linux).
ARCH="$(nix eval --raw --impure --expr builtins.currentSystem)"
say "Architektur: $ARCH"

# 3. Modus wählen.
printf '\nWas einrichten?\n  [1] NixOS + Home Manager (ganzes System)\n  [2] Nur Home Manager (Shell-Profil)\n'
read -r -p "Auswahl [1/2]: " MODE < /dev/tty

if [ "$MODE" = "2" ]; then
  # 4. Nur Home Manager.
  say "Home-Manager-Shell-Profil aktivieren: felix@$ARCH"
  nix run home-manager -- switch -b backup \
    --flake "$REPO_DIR#felix@$ARCH"
  say "Fertig. Neue Shell starten oder 'exec zsh'."
  exit 0
fi

# 5. NixOS + Home Manager.
HOST="$(hostname)"
say "Hostname: $HOST"

if [ -d "$REPO_DIR/hosts/$HOST" ]; then
  say "Host '$HOST' ist bereits definiert — kein Template nötig."
else
  say "Neuer Host '$HOST' — erzeuge aus Template."
  cp -r "$REPO_DIR/hosts/template" "$REPO_DIR/hosts/$HOST"
  rm -f "$REPO_DIR/hosts/$HOST/.gitkeep-hardware"
  printf '%s\n' "$ARCH" > "$REPO_DIR/hosts/$HOST/system"
  nixos-generate-config --show-hardware-config \
    > "$REPO_DIR/hosts/$HOST/hardware-configuration.nix"
  # Flakes sehen nur getrackte Dateien — neue Host-Dateien stagen.
  git -C "$REPO_DIR" add "hosts/$HOST"
fi

REBUILD_CMD="sudo nixos-rebuild switch --flake $REPO_DIR#$HOST"
say "Rebuild-Befehl:"
printf '    %s\n' "$REBUILD_CMD"

read -r -p "Jetzt direkt ausführen? [y/N]: " RUN < /dev/tty
case "$RUN" in
  [yY]*) say "Starte Rebuild …"; eval "$REBUILD_CMD" ;;
  *) say "Übersprungen. Befehl oben bei Bedarf selbst ausführen." ;;
esac
```

- [ ] **Step 2: Ausführbar machen + shellcheck**

```bash
chmod +x scripts/setup-new-host.sh
nix run nixpkgs#shellcheck -- scripts/setup-new-host.sh
```
Erwartet: keine Errors (SC2086 für `$REBUILD_CMD` in `eval` ist beabsichtigt; bei Warnung mit `# shellcheck disable=SC2086` über der `eval`-Zeile unterdrücken).

- [ ] **Step 3: Syntax-Check ohne Ausführung**

```bash
bash -n scripts/setup-new-host.sh && echo "syntax ok"
```
Erwartet: `syntax ok`.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-new-host.sh
git commit -m "scripts: add setup-new-host.sh bootstrap (NixOS+HM or HM-only)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: README-Installationsabschnitt neu fassen

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Abschnitt „My Installation" ersetzen**

Ersetze den bestehenden Block (von `## My Installation` bis vor `# Awesome Links`) durch:

````markdown
## My Installation

**WARNING**: These are the installation instructions for myself, not for you. You should have your own repository and get inspired by this one. If you have any questions, feel free to open issues.

All paths assume a running NixOS system.

### A — Quick shell on any box (standalone Home Manager)

No clone needed; points straight at the GitHub flake. Ephemeral or permanent.

```bash
nix run home-manager -- switch -b backup \
  --flake github:fdietze/dotfiles#felix@x86_64-linux
# aarch64 machines: use #felix@aarch64-linux
```

### B / C — Full NixOS host (defined host or brand-new machine)

One bootstrap script handles both. It clones the repo, then asks whether to set
up the whole system (NixOS + Home Manager) or just the Home Manager shell
profile. For a hostname that is already defined (e.g. `gurke`) it builds that
host directly; for a new machine it derives a desktop-free host from
`hosts/template/`, generates `hardware-configuration.nix`, and offers to rebuild.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh)
```

If `curl` is missing on a minimal install: `nix-shell -p curl`.

To keep a new host long-term, promote it: add desktops and a `local.nix` the way
`hosts/gurke/` does.
````

- [ ] **Step 2: Markdown-Lint**

```bash
nix run nixpkgs#markdownlint-cli2 -- README.md || true
```
Erwartet: keine neuen schwerwiegenden Fehler im geänderten Abschnitt (bestehende Repo-weite Lint-Lage ignorieren).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite installation section with three bootstrap paths

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review-Ergebnis

- **Spec-Abdeckung:** Refactor/Shell-Core (Tasks 1–3) ✓; Theme-Default „dark" ohne stylix (Core liefert `theme = "dark"` via `mkHome`/extraSpecialArgs, Task 4/5) ✓; Auto-Discovery + multi-arch + `system`-Datei (Task 4) ✓; standalone homeConfigurations (Task 5) ✓; Template-Host (Task 6) ✓; Setup-Script inkl. NixOS-vs-HM-Wahl, `--show-hardware-config`, `git add`, `/dev/tty`-Abfrage (Task 7) ✓; README 3 Pfade (Task 8) ✓.
- **Platzhalter:** keine — alle Code-Blöcke vollständig.
- **Typ-/Namenskonsistenz:** `mkHost`/`mkHome`/`hostSystem`/`uiFontsFor` einheitlich; `profiles/shell-core.nix` und `profiles/packages-cli.nix` durchgängig gleich benannt.

## Risiken

- **CLI/GUI-Partition (Task 1/3):** Urteilssache; `nvd diff` garantiert nur, dass gurke unverändert bleibt, nicht die „Schönheit" des Schnitts. Anpassbar.
- **aarch64 (Task 5):** Manche Core-Pakete könnten `meta.platforms` einschränken; Dry-Run-Eval deckt das auf, Fix = Paket aus dem Core nehmen.
- **Core-Module standalone (Task 5):** `nvf.nix`/`dotfiles.nix` könnten standalone Optionen erwarten, die nur im NixOS-Kontext existieren; Build-Fehler in Task 5 zeigt es, Fix dort dokumentiert.
- **`curl` auf minimalem NixOS** evtl. nicht vorhanden → README nennt `nix-shell -p curl`.
