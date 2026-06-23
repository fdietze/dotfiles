# Cubie A7Z (Radxa A733): aarch64 SBC, Debian 11, Determinate Nix (multi-user).
# Permanent remote AI-agent host (replaces the destroyed Fly Sprite). Runs under
# a dedicated "felix" user (isolated from the board's primary "radxa" desktop
# user). Standalone Home Manager; repo cloned under ~/projects/dotfiles,
# activated with
#   home-manager switch -b backup --flake ~/projects/dotfiles#cubie
# User/home come from shell-core's defaults (felix, /home/felix).
# Agents unsandboxed (vanilla.nix) for now — nono/Landlock fit on this kernel
# still to be verified.
{...}: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
    # Base Neovim arrives via shell-core (modules/home-manager/nvf.nix); this
    # host opts into the full LSP/language toolchain for remote editing. LSP
    # servers/formatters + grammars are cached for aarch64-linux (unlike codex's
    # Rust source build), so it stays a mostly-substituted closure on the 1 GB SBC.
    ../modules/home-manager/nvf-lsp.nix
  ];

  # pi + claude on this 1 GB SBC. Skip codex (slow aarch64 Rust source build,
  # no binary cache) and opencode. claude-code is a light npm fetch.
  aiAgents.names = ["pi" "claude"];

  # Per-repo GitHub deploy keys, now nix-managed (was hand-written ~/.ssh/config).
  # Each alias forces exactly one repo's write-scoped key via IdentitiesOnly, so
  # remotes git@github-dotfiles:… / git@github-ct:… push only to their repo.
  # Private keys live on the SBC (~/.ssh/deploy_*), outside nix.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # only these aliases, no global Host-* defaults
    settings = {
      "github-dotfiles" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/deploy_dotfiles";
        identitiesOnly = true;
      };
      "github-ct" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/deploy_causal_transformer";
        identitiesOnly = true;
      };
    };
  };
}
