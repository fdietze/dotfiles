# nrs rewrite: tmux session in user@.service

Date: 2026-06-05
Status: approved
Scope: `modules/home-manager/theme-switching.nix` (nrs script), `hosts/gurke/default.nix` (sudoers revert)

## Problem

The current `nrs` script wraps `nixos-rebuild` in `sudo systemd-run --collect
--pipe --wait --service-type=oneshot` so the rebuild survives the user's
compositor and terminal being killed mid-activation (necessary when switching
specialisations whose greetd `default_session` differs). The transient unit
runs detached from any TTY.

`nixos-rebuild`'s activation phase internally calls
`sudo nix-env -p /nix/var/nix/profiles/system --set …`. With
`wheelNeedsPassword = true` (set on host `gurke`), that inner sudo prompts for
a password. Inside the systemd-run unit there is no TTY and no askpass helper
configured, so the prompt fails:

    sudo: a terminal is required to read the password; either use the -S option
    to read from standard input or configure an askpass helper

A previously considered workaround — `sudo -v` on the outer TTY to prime the
credential cache, plus `Defaults timestamp_type=global` in sudoers — fixes the
prompt but weakens sudo's security model: any TTY belonging to the user can
reuse cached credentials primed in any other TTY. Rejected.

## Goal

Run the rebuild in a context that:

1. Survives the user session scope being killed when greetd restarts.
2. Has a real PTY so the inner sudo prompts interactively, with per-TTY
   credential caching unchanged.
3. Can be cancelled and inspected interactively.
4. Does not require an askpass helper, GUI prompt, or relaxed sudoers config.

## Approach

Run `nixos-rebuild` inside a tmux session whose **server** lives in
`user@.service` (the user systemd manager), not in the dying session scope.
The user's interactive shell attaches a tmux **client** to that server; the
server (and the rebuild process underneath) survives independent of the
client.

### Why `systemd-run --user --scope`

A bare `tmux new-session -d` started from the user's shell inherits the shell's
cgroup — typically `session-N.scope` under `user@.service/user.slice`. When
greetd restarts and logind terminates `session-N.scope`, every process in that
cgroup (including the new tmux server) is killed.

`systemd-run --user --scope -- tmux new-session -d …` creates a transient
**user-level** scope unit directly under `user@.service`, not under the login
session scope. tmux's double-fork daemonisation then reparents the server to
the user manager; the server stays under `user@.service` regardless of which
session scope spawned it.

### Why tmux at all (vs. a service unit)

A `systemd-run --user --unit=nrs --service-type=oneshot` would also survive
session-scope death, but it has no PTY. Solving the inner-sudo prompt would
require an askpass helper or sudoers timestamp relaxation — exactly what we
are avoiding.

tmux gives the rebuild a real PTY for free, makes "cancel" a normal `Ctrl-C`,
and lets the user reattach after a session crash.

## Architecture

```
user shell (session-N.scope)
└─ nrs script
   ├─ systemd-run --user --scope -- tmux new-session -d -s nrs "<inner>"
   │  └─ tmux server (user@.service)        ◄── survives session-scope death
   │     └─ tmux window running inner bash:
   │        • nixos-rebuild switch --sudo --specialisation X
   │          └─ inner sudo prompts on tmux PTY (per-TTY timestamp, normal)
   │        • on desktop change: exec sudo loginctl terminate-user $USER
   └─ exec tmux attach -t nrs                ◄── client; may die with session
```

## Lifecycle

1. **Resolve spec.** Same logic as today: positional arg, else
   `/run/nixos/current-specialisation`, else empty (parent toplevel).
2. **Map spec → desktop** via the case statement generated from
   `desktop-registry.nix`. `desktop_of` returns `unknown` for unrecognised
   specs.
3. **Idempotency check.** If `tmux has-session -t nrs` already exists:
   - If the user passed a positional arg, print a clear two-line warning to
     stderr (rebuild already running; argument ignored; cancel the running
     rebuild first to retarget) and `sleep 2` so the warning is readable.
   - `exec tmux attach -t nrs`.
4. **Spawn.** `systemd-run --user --scope --quiet tmux new-session -d -s nrs
   "bash -c <inner>"`. The inner script:
   - Runs `nixos-rebuild switch --sudo [--specialisation $spec]`.
   - On non-zero exit: prints a failure line, waits for a keypress so the
     PTY scrollback stays visible, exits.
   - If `target_desktop` is non-empty, not `unknown`, and differs from
     `current_desktop`: prints "desktop changed" then
     `exec sudo loginctl terminate-user "$USER"` (synchronous from the
     caller's point of view; logind kills `user@.service`, taking tmux with
     it).
   - Otherwise: prints "done", waits for keypress, exits cleanly.
5. **Attach.** `exec tmux attach -t nrs`. From here the user types the sudo
   password, watches the build, and either lets it finish or hits `Ctrl-C`.

## Failure modes

| Scenario | Behaviour |
|---|---|
| Compositor / greetd restart mid-build | tmux client dies with session scope; tmux server keeps running under `user@.service`; rebuild continues. After relogin, `nrs` (or `tmux attach -t nrs`) reattaches. |
| Compositor restart during the sudo prompt | Same — prompt is still waiting in the PTY when the user reattaches. |
| Rebuild fails | Inner script `read -n1` keeps the PTY alive so the user sees the error. Exit code is not propagated to the outer shell (tmux attach always exits 0); acceptable since the error is visible. |
| `Ctrl-C` in attached tmux | SIGINT propagates to `nixos-rebuild`; build aborts; inner script falls through to the keypress wait. |
| User detaches (`C-b d`) | Client gone; server + build continue; reattach any time. |
| `tmux kill-session -t nrs` | Server killed → inner script SIGTERM → rebuild aborted. Predictable cancel knob. |
| Second `nrs <spec>` while a rebuild is running | Warning printed; new arg ignored; attached to existing session. |
| Desktop change branch | `exec sudo loginctl terminate-user` kills `user@.service` (which contains tmux); greeter reappears via autologin / greetd. |
| `KillUserProcesses=yes` in logind config | tmux server would die with the session — design assumption broken. NixOS default is `no`; treated as a documented prerequisite, not a runtime check. |

## Migration

1. `hosts/gurke/default.nix`: remove the `extraConfig = "Defaults
   timestamp_type=global\n"` block and its comment added during the
   `sudo -v` experiment. Restore the original `security.sudo` block shape.
2. `modules/home-manager/theme-switching.nix`:
   - Drop the `sudo -v` prime line.
   - Drop the `sudo systemd-run --collect --pipe --wait --service-type=oneshot
     --uid --gid --setenv` invocation.
   - Drop the post-rebuild `loginctl terminate-user` branch in the outer
     script (the same logic moves into the inner tmux script).
   - Swap `--use-remote-sudo` → `--sudo` (the former is deprecated by
     `nixos-rebuild`).
   - Insert the new tmux-based body (see Lifecycle).
   - Reference `${pkgs.tmux}/bin/tmux` and `${pkgs.systemd}/bin/systemd-run`
     by full store path.
   - Keep the existing `specCaseArms` generator and `desktop_of` function.
   - Header comment: state that the tmux server must live in `user@.service`
     and that `KillUserProcesses=no` (NixOS default) is required.

## Testing

| Test | Expected |
|---|---|
| `nrs` (no arg) | Tmux attaches, sudo prompts on PTY, rebuild runs, "done — press any key" on success. |
| `nrs <other-themed-spec>` (theme switch only) | Rebuild runs, theme applied, no relogin. |
| `nrs <other-desktop-spec>` | Rebuild runs, "desktop changed" message, `terminate-user` triggers greeter. |
| `nrs <spec>` while another rebuild is running | Warning lines on stderr, arg ignored, attached to running session. |
| `Ctrl-C` mid-rebuild in attached tmux | Build aborts, error visible, keypress closes session. |
| Compositor kill during rebuild (e.g. `pkill -9 niri`) | Terminal dies; after relogin `nrs` (or `tmux attach -t nrs`) reattaches; build is still running or already finished. |
| `tmux kill-session -t nrs` | Build killed abruptly. |
| `nrs --typo-arg` (resolves to `desktop_of` → `unknown`) | Rebuild runs; relogin branch is **not** triggered (guard explicitly excludes `unknown`). |

Build verification: `nixos-rebuild build --flake .#gurke` (no activation) must
succeed on host `gurke` with the new module.

## Non-goals

- KillUserProcesses runtime detection.
- Per-build log archival (tmux scrollback is sufficient).
- Multi-host validation beyond `gurke` in this change; other hosts use the
  same module and inherit the behaviour, but only `gurke` is exercised in
  testing.
- Replacing `--sudo` with a different elevation mechanism (e.g. polkit).
