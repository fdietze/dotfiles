# Paseo (github:getpaseo/paseo): self-hosted daemon + CLI, das die AI-Coding-
# Agents hinter einer Oberfläche (CLI/Web/Mobile/Desktop) orchestriert. Hier nur
# das Paket — kein services.paseo. Der Daemon wird bei Bedarf manuell gestartet
# (`paseo`), nicht als systemd-Unit.
#
# Bewusst NICHT nono-gewrappt: Paseo spawnt die Agent-CLIs selbst. Auf PATH
# liegen die in ./default.nix erzeugten, nono-gesandboxten Wrapper (claude,
# codex, opencode, pi) — Paseo ruft also die bereits gesandboxten Varianten auf.
# Paseo koordiniert, die Isolation bleibt in den Agent-Wrappern.
{
  pkgs,
  flake-inputs,
  ...
}: {
  home.packages = [
    flake-inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.paseo
  ];
}
