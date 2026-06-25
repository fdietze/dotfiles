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

  # Point the pi web-search extension at gurke's local SearXNG
  # (services.searx, 127.0.0.1:8888 in default.nix). Host-scoped on purpose:
  # backends.ts picks the backend from PI_SEARX_URL *unconditionally* and does
  # NOT fall back, so setting it where no searx runs would break web_search.
  # Local-first: each host should use its own local search service; only gurke
  # has one today (cubie is the next candidate, see that host's notes).
  # Launch-context caveat: home.sessionVariables is only sourced by a session
  # that loaded the HM env (a terminal in gurke's graphical session — true
  # here). If pi is ever launched over ssh (non-login shell) on a future host,
  # that host may need the wrapper-env approach instead.
  home.sessionVariables.PI_SEARX_URL = "http://127.0.0.1:8888";

  # TEMPORÄR: subagents live ans Working Tree linken für schnelles Feedback.
  # Nach Stabilisierung wieder entfernen — nicht committen.
  my.devLinks = [
    "modules/home-manager/profiles/ai-agents/pi-extensions/subagents"
    "modules/home-manager/profiles/ai-agents/pi-extensions/context-prune"
    "modules/home-manager/profiles/ai-agents/pi-extensions/question"
  ];
}
