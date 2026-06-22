# Le-Big-Mac headless remote workflow — design

## Context

Le-Big-Mac = MacBook Pro 14" M2 Pro (Mac14,5), macOS 26.5.1. felix is a
standalone home-manager user with **no sudo** (system owned by main GUI user
`tiphaniedousset`). felix uses it headlessly over ssh "from time to time" for
**long training runs + interactive AI-agent sessions**.

Goal: simple, effective workflow to (1) reach the box remotely, (2) keep jobs
alive across disconnects, (3) keep the mac awake while working — all with **zero
root** and felix's tailscale identity **isolated** from the main user.

## Constraints discovered

- felix has no sudo → cannot create a utun interface, cannot enable/disable
  Remote Login, cannot install boot daemons, cannot `pmset`.
- Existing Tailscale = standalone **macsys** variant (system extension
  `io.tailscale.ipn.macsys`), owned by `tiphaniedousset`, currently *stopped*.
  One system extension = one tailnet identity → cannot host felix's separate
  account.
- macOS LaunchAgents autostart only on **GUI login**, which a headless ssh-only
  felix never performs → no unattended autostart for felix without root.

## Architecture — three independent layers

1. **Connectivity** — felix's *own* userspace `tailscaled` (nix `pkgs.tailscale`,
   own tailnet account). Runs `--tun=userspace-networking` (mandatory: no root =
   no utun). State under `$XDG_STATE_HOME/tailscale/`, dedicated socket + random
   port → never collides with the macsys system extension. Built-in **Tailscale
   SSH** (`--ssh`): felix's tailscaled terminates ssh in its own netstack and
   spawns the shell — no dependency on the admin-controlled system sshd, no
   authorized_keys, auth via felix's tailnet ACL. Transparent to standard
   clients (`ssh felix@<tailnet-ip>`, scp, rsync, IDE-remote all work).

2. **Wakefulness** — `/usr/bin/caffeinate -i -s` (macOS builtin) bound to the
   **tmux server pid** (`-w <pid>`). Awake only while tmux lives; kill the
   session → mac sleeps again (matches the deep-sleep rule).

3. **Persistence** — tmux (already installed via `packages-cli`), reusing the
   existing `~/.tmux.conf` (prefix `C-a`, mouse, 10k scrollback, OSC52 clipboard
   over ssh, vi copy-mode). No new tmux config.

## The glue: `work` script

`pkgs.writeShellApplication` named `work`, on felix's PATH. Idempotent. Run
after sshing in (over LAN the first time and after any reboot). Pseudocode:

```sh
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/tailscale"; SOCK="$STATE/tailscaled.sock"
mkdir -p "$STATE"

# 1. ensure felix's tailscaled is up
if ! tailscale --socket="$SOCK" status >/dev/null 2>&1; then
  nohup tailscaled --tun=userspace-networking \
    --state="$STATE/tailscaled.state" --socket="$SOCK" --port=0 \
    >"$STATE/tailscaled.log" 2>&1 &
  for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
  tailscale --socket="$SOCK" up --ssh --hostname=le-big-mac-felix
fi

# 2. ensure tmux server, 3. bind caffeinate to its lifetime
tmux has-session 2>/dev/null || tmux new-session -d -s main
TPID="$(tmux display-message -p '#{pid}')"
pgrep -f "caffeinate .*-w $TPID" >/dev/null 2>&1 || /usr/bin/caffeinate -i -s -w "$TPID" &

# 4. attach
exec tmux attach
```

First `tailscale up --ssh` prints a login URL → authenticate in a browser to
felix's tailscale account; state persists on disk, so later cold starts come up
authed with no URL. `runtimeInputs = [ tailscale tmux ]`; `caffeinate` called by
absolute path (macOS builtin, not a nix pkg).

Convenience wrapper `tsf` (`writeShellScriptBin`): `exec tailscale
--socket=$STATE/tailscaled.sock "$@"` — for `tsf status`, `tsf down`, etc.

## File / module layout

- New module `modules/home-manager/profiles/headless-mac.nix`: `home.packages`
  gets `tailscale`; defines `work` + `tsf`. Header comment documents no-root /
  userspace / reboot rationale.
- `hosts-home/Le-Big-Mac.nix` imports it. **Not** added to shared `packages-cli`
  (would bloat the NixOS host `gurke`). Separate module = "modules over options".

## Reconnect flow

From any device on felix's tailnet: `ssh felix@le-big-mac-felix` (or
`tailscale ssh`). Detach `C-a d`; jobs keep running, mac stays awake (tmux
alive); reconnect later and `work` (or `tmux attach`).

## Caveats (no zero-root fix; documented, not solved)

- **Reboot** kills felix's tailscaled (no boot daemon). Re-run `work` while on
  LAN to revive it — **no re-auth** (state on disk). Accepted cost of the
  zero-root option.
- **Clamshell sleep**: lid-closed *on battery* sleeps regardless of caffeinate
  (needs root `pmset`); `caffeinate -s` is also ignored on battery. For reliable
  long jobs: **plugged in + lid open**.
- Tailscale SSH needs an `ssh` rule in felix's tailnet ACL (solo admin console,
  trivial for own devices).

## Non-goals

- No boot-persistent daemon, no wake-on-LAN, no `pmset` (all need root).
- No sharing of / interaction with the main user's macsys Tailscale.
- No tmux config changes; no sandboxing (Le-Big-Mac agents already unsandboxed).

## Prerequisite to verify in the plan

- `pkgs.tailscale` builds on `aarch64-darwin` and ships both `tailscaled` and
  `tailscale` binaries (else fall back to a fetched static build).
