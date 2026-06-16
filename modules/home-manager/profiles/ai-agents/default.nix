# Sandboxed AI coding agents (the default; import this where nono works). Each
# agent from ./agents.nix gets a nono-wrapped `<name>` plus an un-sandboxed
# `vanilla-<name>` escape hatch, both at low CPU/IO priority. The shared nono
# profile `agent` is generated into ~/.config/nono/profiles/ by dotfiles.nix
# from the maintained base at home/config/nono/profiles/agent.json (merged with
# read perms for my.devLinks), so edits to that file need a switch to take effect.
#
# Where nono's Landlock sandbox is unavailable (e.g. korken: proot intercepts
# the landlock syscalls), import ./vanilla.nix instead.
#
# ./skills.nix provisions the shared ~/.agents/skills/ set (superpowers + own).
{
  lib,
  pkgs,
  ...
}: let
  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

  # Give each sandboxed agent a private, empty /tmp via a bwrap mount namespace
  # (--dev-bind / / passes the host root through unchanged, --tmpfs /tmp shadows
  # only /tmp). Host /tmp is then absent inside the agent, which closes the
  # sandbox escape via host tmux sockets at /tmp/tmux-<uid>/ (connecting there
  # would run commands in the un-sandboxed host tmux server). /tmp stays usable
  # for tools. bwrap MUST wrap OUTSIDE nono: nono's seccomp blocks the
  # unshare/uid-map bwrap needs; nono keeps enforcing Landlock inside.
  privateTmp = "${pkgs.bubblewrap}/bin/bwrap --dev-bind / / --tmpfs /tmp --";

  # Wrap an agent: nono-sandboxed `<name>` + un-sandboxed `vanilla-<name>`.
  mkAgent = {
    name,
    bin,
    env ? "",
    yolo ? "",
  }: [
    (pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} ${privateTmp} \
        ${pkgs.llm-agents.nono}/bin/nono run --profile agent -- \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
in {
  imports = [./skills.nix ./pi-extensions.nix];

  home.packages = lib.concatMap mkAgent (import ./agents.nix {inherit pkgs;});
}
