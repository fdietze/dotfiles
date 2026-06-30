# Cubie A7Z (Radxa A733): aarch64 SBC, Debian 11, Determinate Nix (multi-user).
# Permanent remote AI-agent host (replaces the destroyed Fly Sprite). Runs under
# a dedicated "felix" user (isolated from the board's primary "radxa" desktop
# user). Standalone Home Manager; repo cloned under ~/projects/dotfiles,
# activated with
#   switch        # (or: home-manager switch -b backup --flake <dotfilesDir>#cubie)
# User/home come from shell-core's defaults (felix, /home/felix).
# Agents unsandboxed (vanilla.nix) for now — nono/Landlock fit on this kernel
# still to be verified.
{
  config,
  pkgs,
  ...
}: let
  # paseo detects provider availability by running `<cmd> --version` with a
  # hardcoded 2 s timeout. pi is a node CLI whose cold start is ~2.2 s on this
  # 1 GB SBC, so the probe always times out and pi shows "unavailable" (claude
  # starts fast enough). This shim answers --version instantly from the build-time
  # version string; every real call execs pi at low priority (matching
  # ai-agents/vanilla.nix). PI_COMMAND below points paseo's pi provider at it.
  piPkg = pkgs.llm-agents.pi;
  piForPaseo = pkgs.writeShellScriptBin "pi" ''
    if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
      echo "${piPkg.version}"
      exit 0
    fi
    exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 ${piPkg}/bin/pi "$@"
  '';
in {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    # paseo CLI + daemon package (paseo, paseo-server). Imported here, not in
    # vanilla.nix, so the heavy aarch64 npm build lands only on this host and not
    # on the other vanilla hosts (korken phone, Le-Big-Mac).
    ../modules/home-manager/profiles/ai-agents/paseo.nix
    # Shared Paseo systemd user service module (defines services.paseo-daemon)
    ../modules/home-manager/profiles/ai-agents/paseo-service.nix
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

  # Enable the shared Paseo user daemon, set to start automatically on boot.
  services.paseo-daemon = {
    enable = true;
    autoStart = true;
  };

  # Local override of the shared Paseo service:
  # Inject the local fast-`--version` pi shim to prevent 2s timeouts on this SBC.
  systemd.user.services.paseo.Service.Environment = [
    "PI_COMMAND=${piForPaseo}/bin/pi"
  ];

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
