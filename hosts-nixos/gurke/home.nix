{...}: {
  imports = [
    ../../modules/home-manager/shared.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/desktops/gnome.nix
    ../../modules/home-manager/desktops/herbstluftwm.nix
    ../../modules/home-manager/desktops/noctalia-niri.nix
    ../../modules/home-manager/desktops/noctalia-frottage.nix
    # Base Neovim arrives via shell-core (modules/home-manager/nvf.nix); this
    # host opts into the full LSP/language toolchain on top.
    ../../modules/home-manager/nvf-lsp.nix
  ];

  # TEMPORÄR: subagents live ans Working Tree linken für schnelles Feedback.
  # Nach Stabilisierung wieder entfernen — nicht committen.
  my.devLinks = [
    "modules/home-manager/profiles/ai-agents/pi-extensions/subagents"
    "modules/home-manager/profiles/ai-agents/pi-extensions/context-prune"
    "modules/home-manager/profiles/ai-agents/pi-extensions/question.ts"
  ];
}
