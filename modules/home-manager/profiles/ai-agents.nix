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
  ];

  # Source the shared nono profile from the repo (versioned) while keeping it
  # live-editable without a HM switch. nono resolves `--profile agent` by name
  # from ~/.config/nono/profiles/.
  home.file.".config/nono/profiles/agent.json".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/config/nono/profiles/agent.json";
}
