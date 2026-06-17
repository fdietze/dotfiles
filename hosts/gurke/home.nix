{...}: {
  imports = [
    ../../modules/home-manager/shared.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/desktops/gnome.nix
    ../../modules/home-manager/desktops/herbstluftwm.nix
    ../../modules/home-manager/desktops/noctalia-niri.nix
    # NVF Neovim configuration explicitly enabled for this host.
    ../../modules/home-manager/nvf.nix
  ];

  # TEMPORÄR: subagents live ans Working Tree linken für schnelles Feedback.
  # Nach Stabilisierung wieder entfernen — nicht committen.
  my.devLinks = [
    "modules/home-manager/profiles/ai-agents/pi-extensions/subagents"
    "modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts"
    "modules/home-manager/profiles/ai-agents/pi-extensions/question.ts"
  ];
}
