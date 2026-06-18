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
  ];

  # Only pi on this 1 GB SBC: skip codex's slow aarch64 Rust source build
  # (no binary cache) and the other agents we don't use here.
  aiAgents.names = ["pi"];
}
