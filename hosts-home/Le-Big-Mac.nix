# Le-Big-Mac: Apple Silicon (M2 Pro, aarch64-darwin), macOS 26. Permanenter
# Standalone-Home-Manager-Host für felix (Home /Users/felix). Nur per ssh als
# felix erreichbar; felix hat kein sudo (System-Änderungen via separatem
# root-Account). Multi-user Nix (offizieller Installer), flakes system-weit in
# /etc/nix/nix.conf aktiviert, nix-daemon-Sourcing in /etc/zshrc ergänzt.
# Aktiviert mit
#   home-manager switch -b backup --flake ~/projects/dotfiles#Le-Big-Mac
#
# Agents UNSANDBOXED (vanilla.nix): nono/Landlock existiert auf macOS nicht.
# Eine macOS-Sandbox (sandbox-exec/seatbelt) ist Folge-Arbeit; bis dahin laufen
# Agents hier unconfined (Supply-Chain-Risiko bewusst in Kauf genommen).
{...}: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
  ];

  # macOS-Home; überschreibt shell-cores /home/felix-Default (username = felix
  # ist bereits der shell-core-Default).
  home.homeDirectory = "/Users/felix";
}
