# Paseo (github:getpaseo/paseo): self-hosted daemon + CLI, das die AI-Coding-
# Agents hinter einer Oberfläche (CLI/Web/Mobile/Desktop) orchestriert. Hier nur
# das Paket — kein services.paseo. Der Daemon wird bei Bedarf manuell gestartet
# (`paseo`), nicht als systemd-Unit.
#
# Bewusst NICHT nono-gewrappt: Paseo spawnt die Agent-CLIs selbst. Auf PATH
# liegen die Agent-Wrapper aus ./default.nix (nono-gesandboxt) bzw. ./vanilla.nix
# (unsandboxed, z.B. cubie) — Paseo ruft also die jeweils dort definierte
# Variante auf und koordiniert nur; die Isolation (falls vorhanden) bleibt im
# Agent-Wrapper.
#
# Importiert von ./default.nix (sandboxed Hosts) und direkt von hosts-home/
# cubie.nix (vanilla Host mit Boot-Daemon). NICHT in ./vanilla.nix, weil das
# auch korken (Phone) und Le-Big-Mac den schweren npm-Build aufzwingen würde.
{
  pkgs,
  flake-inputs,
  ...
}: {
  home.packages = [
    flake-inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.paseo
  ];
}
