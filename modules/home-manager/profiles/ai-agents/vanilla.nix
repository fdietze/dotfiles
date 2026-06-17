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
  lib,
  pkgs,
  ...
}: let
  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

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
in {
  imports = [./skills.nix ./pi-extensions.nix ./instructions.nix];

  home.packages = map mkAgent (import ./agents.nix {inherit pkgs;});
}
