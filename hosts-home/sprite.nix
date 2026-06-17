# Fly Sprite (https://docs.sprites.dev/): Ubuntu microVM, single-user nix,
# fester User "sprite", Hostname "remote-ai". Standalone Home Manager,
# aktiviert mit `home-manager switch`. Agenten unsandboxed (vanilla.nix):
# "kein Sandboxing for now" — nono/Landlock-Eignung auf der VM später prüfen.
{...}: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
  ];
  home.username = "sprite";
  home.homeDirectory = "/home/sprite";
}
