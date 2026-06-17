# Fly Sprite (https://docs.sprites.dev/): Ubuntu microVM, single-user nix,
# fester User "sprite", Hostname "remote-ai". Standalone Home Manager; repo
# unter ~/projects/dotfiles geklont, aktiviert mit
#   home-manager switch -b backup --flake ~/projects/dotfiles#sprite
# Agenten unsandboxed (vanilla.nix): "kein Sandboxing for now" —
# nono/Landlock-Eignung auf der VM später prüfen.
{...}: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
  ];
  home.username = "sprite";
  home.homeDirectory = "/home/sprite";

  # `sprite x` spawnt Shells ohne Login/PAM, daher ist $USER ungesetzt. Der
  # home-manager-Aktivierungs-Wrapper läuft unter `set -u` und referenziert
  # $USER -> "unbound variable". Deklarieren, damit der switch-Befehl ohne
  # manuelles `USER=sprite`-Präfix klappt (greift ab dem zweiten switch, weil
  # hm-session-vars erst nach der ersten Aktivierung gesourced wird).
  home.sessionVariables.USER = "sprite";
}
