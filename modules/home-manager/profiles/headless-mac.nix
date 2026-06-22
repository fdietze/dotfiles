# Headless remote workflow for the standalone macOS host (Le-Big-Mac).
# felix has no sudo, so Tailscale runs in USERSPACE-NETWORKING mode as a plain
# felix process (no utun, no boot daemon): felix's own tailnet identity, fully
# isolated from the main user's macsys Tailscale system extension. State lives
# under $XDG_STATE_HOME/tailscale with a dedicated socket + random port so it
# never collides with that system extension. Built-in Tailscale SSH (`up --ssh`)
# lets felix reach the box without depending on the admin-controlled system sshd.
#
# `work` is the single entrypoint: ensure tailscaled is up -> ensure a tmux
# server -> bind `caffeinate` to the tmux server pid (mac sleeps again when the
# session is killed) -> attach. Re-run after a reboot while on LAN; tailscale
# state persists on disk so there is no re-auth.
# Design: docs/superpowers/specs/2026-06-22-le-big-mac-headless-remote-workflow-design.md
{pkgs, ...}: let
  # felix-owned tailscale state/socket; XDG so no hardcoded /Users/felix.
  sock = ''"''${XDG_STATE_HOME:-$HOME/.local/state}/tailscale/tailscaled.sock"'';

  work = pkgs.writeShellApplication {
    name = "work";
    runtimeInputs = [pkgs.tailscale pkgs.tmux];
    text = ''
      STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/tailscale"
      SOCK="$STATE/tailscaled.sock"
      mkdir -p "$STATE"

      # 1. ensure felix's userspace tailscaled is running (no root, no utun).
      if ! tailscale --socket="$SOCK" status >/dev/null 2>&1; then
        nohup tailscaled \
          --tun=userspace-networking \
          --state="$STATE/tailscaled.state" \
          --socket="$SOCK" \
          --port=0 \
          >"$STATE/tailscaled.log" 2>&1 &
        for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
        # First run prints a login URL (auth to felix's tailnet account in a
        # browser); later cold starts read persisted state and come up authed.
        tailscale --socket="$SOCK" up --ssh --hostname=le-big-mac-felix
      fi

      # 2. ensure a tmux server exists (reuses ~/.tmux.conf).
      tmux has-session 2>/dev/null || tmux new-session -d -s main

      # 3. bind caffeinate to the tmux server pid: awake only while tmux lives.
      #    caffeinate is a macOS builtin, not a nix pkg -> absolute path.
      TPID="$(tmux display-message -p '#{pid}')"
      if ! pgrep -f "caffeinate .*-w $TPID" >/dev/null 2>&1; then
        /usr/bin/caffeinate -i -s -w "$TPID" &
      fi

      # 4. attach (replaces this shell; backgrounded caffeinate reparents and
      #    keeps running until the tmux server exits).
      exec tmux attach
    '';
  };

  # Convenience wrapper for felix's tailscale CLI against his own socket:
  #   tsf status | tsf down | tsf up --ssh ...
  tsf = pkgs.writeShellScriptBin "tsf" ''
    exec ${pkgs.tailscale}/bin/tailscale --socket=${sock} "$@"
  '';
in {
  home.packages = [pkgs.tailscale work tsf];
}
