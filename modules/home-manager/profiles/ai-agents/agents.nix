# The AI coding agents, as pure data: name + binary + optional env/yolo flags.
# Consumed by ./default.nix (nono-sandboxed) and ./vanilla.nix (unsandboxed), so
# the agent list lives in exactly one place and each profile only decides how to
# wrap it. `yolo` disables an agent's own permission prompts (sandboxed variant
# only — nono is the real isolation layer there).
{pkgs}: [
  {
    name = "claude";
    bin = "${pkgs.llm-agents.claude-code}/bin/claude";
    env = "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n";
    yolo = "--dangerously-skip-permissions";
  }
  {
    name = "opencode";
    bin = "${pkgs.llm-agents.opencode}/bin/opencode";
  }
  {
    # codex: bypass its own approvals + built-in sandbox; nono is the external
    # sandbox the flag is designed for.
    name = "codex";
    bin = "${pkgs.llm-agents.codex}/bin/codex";
    yolo = "--dangerously-bypass-approvals-and-sandbox";
  }
  {
    # pi: no permission-gating flag exists; its tools run directly under nono.
    name = "pi";
    bin = "${pkgs.llm-agents.pi}/bin/pi";
  }
]
