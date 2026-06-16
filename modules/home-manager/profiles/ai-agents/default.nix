# Sandboxed AI coding agents (the default; import this where nono works). Each
# agent from ./agents.nix gets a nono-wrapped `<name>` plus an un-sandboxed
# `vanilla-<name>` escape hatch, both at low CPU/IO priority. The shared nono
# profile `agent` lives at home/config/nono/profiles/agent.json and is linked
# out-of-store into ~/.config/nono/profiles/ by dotfiles.nix, so it stays
# versioned yet live-editable without a Home-Manager switch.
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

  # Wrap an agent: nono-sandboxed `<name>` + un-sandboxed `vanilla-<name>`.
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
  imports = [./skills.nix ./pi-extensions.nix];

  home.packages = lib.concatMap mkAgent (import ./agents.nix {inherit pkgs;});
}
