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
# ./skills.nix provisions the shared ~/.agents/skills/ set (superpowers + own);
# ./instructions.nix links the global AGENTS.md into each harness's context path.
{
  lib,
  pkgs,
  ...
}: let
  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

  # Single source of truth for entering a nono jail: enter-sandbox <profile>
  # <workdir> <cmd...>.
  #
  # Always `nono wrap` (stacks Landlock and execs, no supervisor): it nests
  # cleanly when launched inside the per-project jail (shell.nix auto-enter),
  # where `nono run` cannot -- run writes its session/audit under the protected
  # ~/.nono, which the outer jail does not grant. Dropping run also drops its
  # rollback/audit; git is the undo path here.
  #
  # bwrap gives a private, empty /tmp (--dev-bind / / passes the host root
  # through unchanged, --tmpfs /tmp shadows only /tmp), closing the escape via
  # host tmux sockets at /tmp/tmux-<uid>/ (connecting there would run commands
  # in the un-sandboxed host tmux server). bwrap MUST wrap OUTSIDE nono (nono's
  # Landlock denies bwrap's procfs setup once jailed) and cannot run nested, so
  # it is added only when no private /tmp is around yet; PRIVATE_TMP marks that
  # one is, so an agent launched inside the project jail does not re-bwrap.
  # SANDBOX holds the active nono profile (non-empty = in a jail; prompt shows it).
  enterSandbox = pkgs.writeShellScriptBin "enter-sandbox" ''
    profile="$1"; workdir="$2"; shift 2
    export SANDBOX="$profile"
    if [ -n "''${PRIVATE_TMP:-}" ]; then
      exec ${pkgs.llm-agents.nono}/bin/nono wrap --profile "$profile" --workdir "$workdir" -- "$@"
    fi
    export PRIVATE_TMP=1
    exec ${pkgs.bubblewrap}/bin/bwrap --dev-bind / / --tmpfs /tmp -- \
      ${pkgs.llm-agents.nono}/bin/nono wrap --profile "$profile" --workdir "$workdir" -- "$@"
  '';

  # Wrap an agent: nono-sandboxed `<name>` (via enter-sandbox, profile `agent`,
  # rooted at $PWD) + un-sandboxed `vanilla-<name>`.
  mkAgent = {
    name,
    bin,
    env ? "",
    yolo ? "",
  }: [
    (pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} ${enterSandbox}/bin/enter-sandbox agent "$PWD" \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
in {
  imports = [./skills.nix ./pi-extensions.nix ./instructions.nix ./paseo.nix];

  home.packages = [enterSandbox] ++ lib.concatMap mkAgent (import ./agents.nix {inherit pkgs;});
}
