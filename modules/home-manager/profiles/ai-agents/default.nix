# Sandboxed AI coding agents. Each agent gets a nono-wrapped `<name>` plus an
# un-sandboxed `vanilla-<name>` escape hatch, both at low CPU/IO priority. The
# shared nono profile `agent` lives at home/config/nono/profiles/agent.json and
# is linked out-of-store into ~/.config/nono/profiles/ by dotfiles.nix, so it
# stays versioned yet live-editable without a Home-Manager switch.
#
# ./skills.nix provisions the shared ~/.agents/skills/ set (superpowers + own).
{
  lib,
  pkgs,
  ...
}: let
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
        ${pkgs.llm-agents.nono}/bin/nono run --profile agent -- \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
in {
  imports = [./skills.nix];

  home.packages = lib.concatLists [
    # `claude`: experimental agent-teams env + skip its own permission prompts
    # (nono is the real isolation layer). `vanilla-claude` keeps the prompts.
    (mkAgent {
      name = "claude";
      bin = "${pkgs.llm-agents.claude-code}/bin/claude";
      env = "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n";
      yolo = "--dangerously-skip-permissions";
    })
    (mkAgent {
      name = "opencode";
      bin = "${pkgs.llm-agents.opencode}/bin/opencode";
    })
    # `codex`: bypass codex's own approvals + built-in sandbox; nono is the
    # external sandbox the flag is designed for. `vanilla-codex` keeps approvals.
    (mkAgent {
      name = "codex";
      bin = "${pkgs.llm-agents.codex}/bin/codex";
      yolo = "--dangerously-bypass-approvals-and-sandbox";
    })
    # `pi`: no permission-gating flag exists; its tools run directly under nono.
    (mkAgent {
      name = "pi";
      bin = "${pkgs.llm-agents.pi}/bin/pi";
    })
  ];
}

