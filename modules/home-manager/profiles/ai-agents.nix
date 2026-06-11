# Sandboxed AI coding agents. Each agent gets a nono-wrapped `<name>` plus an
# un-sandboxed `vanilla-<name>` escape hatch, both at low CPU/IO priority. The
# shared nono profile `agent` is sourced from the repo via out-of-store symlink
# so it stays versioned yet live-editable without a Home-Manager switch.
{
  config,
  lib,
  pkgs,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";

  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

  # Wrap an AI coding agent.
  #   env  -> shell prelude (export lines, must end in "\n"); applied to BOTH variants
  #   yolo -> flag(s) that disable the agent's own permission prompts; sandboxed
  #           variant ONLY — without nono (vanilla) we keep the agent's prompts.
  mkAgent = {
    name,
    bin,
    env ? "",
    yolo ? "",
  }: [
    (pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} \
        ${pkgs.nono}/bin/nono run --profile agent -- \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
in {
  home.packages = lib.concatLists [
    # `claude`: experimental agent-teams env + skip its own permission prompts
    # (nono is the real isolation layer). `vanilla-claude` keeps the prompts.
    (mkAgent {
      name = "claude";
      bin = "${pkgs.claude-code}/bin/claude";
      env = "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n";
      yolo = "--dangerously-skip-permissions";
    })
    (mkAgent {
      name = "opencode";
      bin = "${pkgs.opencode}/bin/opencode";
    })
    # `codex`: bypass codex's own approvals + built-in sandbox; nono is the
    # external sandbox the flag is designed for. `vanilla-codex` keeps approvals.
    (mkAgent {
      name = "codex";
      bin = "${pkgs.codex}/bin/codex";
      yolo = "--dangerously-bypass-approvals-and-sandbox";
    })
    # `pi`: no permission-gating flag exists; its tools run directly under nono.
    (mkAgent {
      name = "pi";
      bin = "${pkgs.pi-coding-agent}/bin/pi";
    })
  ];

  # Source the shared nono profile from the repo (versioned) while keeping it
  # live-editable without a HM switch. nono resolves `--profile agent` by name
  # from ~/.config/nono/profiles/.
  home.file.".config/nono/profiles/agent.json".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/config/nono/profiles/agent.json";
}
