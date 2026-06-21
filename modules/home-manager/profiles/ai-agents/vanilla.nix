# Unsandboxed AI coding agents, for hosts where nono cannot run: nono relies on
# Landlock, which proot intercepts (korken's switch tested: "No supported
# Landlock ABI detected"), so the sandbox never initialises and the wrapped
# command refuses to run. Here `<name>` is the agent itself at low priority —
# NO sandbox. A proot-based sandbox profile (inner proot with restricted binds)
# is the planned follow-up; until then mobile agents run unconfined.
#
# Same agent list (./agents.nix) and shared extras (skills, pi-extensions,
# instructions) as the sandboxed ./default.nix — only the wrapping differs.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  # ionice (util-linux) is Linux-only; on Darwin drop it and keep just nice.
  prio = "${lib.optionalString pkgs.stdenv.isLinux "${pkgs.util-linux}/bin/ionice -c 3 "}${pkgs.coreutils}/bin/nice -n 19";

  mkAgent = {
    name,
    bin,
    env ? "",
    ...
  }:
    pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '';
  allAgents = import ./agents.nix {inherit pkgs;};
in {
  imports = [./skills.nix ./pi-extensions.nix ./instructions.nix];

  # Which agents (by name from agents.nix) to install. Default: all. A host can
  # narrow this to avoid pulling heavy builds it doesn't need (e.g. the cubie
  # SBC sets ["pi"] to skip codex's slow aarch64 Rust source build).
  options.aiAgents.names = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = map (a: a.name) allAgents;
    description = "Agent names from agents.nix to install (unsandboxed).";
  };

  config.home.packages =
    map mkAgent (lib.filter (a: lib.elem a.name config.aiAgents.names) allAgents);
}
