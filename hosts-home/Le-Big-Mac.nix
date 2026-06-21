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

  # Per-Repo Deploy-Keys statt eines fdietze-Account-Keys: jeder Key pusht NUR
  # in sein eines Repo (Blast-Radius = 1 Repo, falls ein unsandboxed Agent ihn
  # liest). Bewusste Abweichung von der "keine Keys im Filesystem"-Policy —
  # dieser Host soll eigenständig (ohne Agent-Forwarding) pushen können.
  # Die privaten Keys werden EINMALIG auf dem Mac erzeugt (passphrasenlos für
  # autonomen Push) und liegen außerhalb von nix; hier nur die Host-Aliase, die
  # github.com pro Repo auf den passenden Key mappen. Remotes nutzen dann
  #   git@github-dotfiles:fdietze/dotfiles.git
  #   git@github-causal-transformer:fdietze/causal-transformer.git
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # nur diese Aliase, kein globaler Host-*-Default
    settings = {
      "github-dotfiles" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_dotfiles_deploy";
        identitiesOnly = true; # nur diesen Key anbieten, nicht alle
      };
      "github-causal-transformer" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_causal_transformer_deploy";
        identitiesOnly = true;
      };
    };
  };
}
