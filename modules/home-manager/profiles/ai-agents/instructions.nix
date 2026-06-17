# Globale, harness-übergreifende Agent-Instruktionen aus EINER nix-verwalteten
# Quelle (./AGENTS.md) in den globalen Kontextpfad JEDES Harness verlinken —
# read-only In-Store-Symlinks (Bearbeitung im Repo + Switch, wie alle dotfiles).
#
# Wichtig: ~/.config/agents/ ist KEIN Standardpfad; nur Claude las es früher über
# einen handgemachten Symlink. Jeder Agent liest seine *globale* AGENTS.md aus
# einem eigenen Verzeichnis, daher pro Harness ein eigener Symlink auf dieselbe
# Datei:
#   * claude   -> ~/.claude/CLAUDE.md         (claude kennt global nur CLAUDE.md)
#   * pi       -> ~/.pi/agent/AGENTS.md       (agentDir; dist/core/resource-loader.js
#                                              loadContextFileFromDir(agentDir))
#   * codex    -> ~/.codex/AGENTS.md          (CODEX_HOME, globale Guidance)
#   * opencode -> ~/.config/opencode/AGENTS.md (globale Rules)
#
# Die *projektweite* AGENTS.md (vom cwd hochgelaufen) ist der eigentliche Standard
# und bleibt davon unberührt — die lesen ohnehin alle Agents von selbst.
{...}: {
  home.file.".claude/CLAUDE.md".source = ./AGENTS.md;
  home.file.".pi/agent/AGENTS.md".source = ./AGENTS.md;
  home.file.".codex/AGENTS.md".source = ./AGENTS.md;
  xdg.configFile."opencode/AGENTS.md".source = ./AGENTS.md;
}
