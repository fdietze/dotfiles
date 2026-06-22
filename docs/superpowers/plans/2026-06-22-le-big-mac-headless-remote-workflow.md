# Le-Big-Mac Headless Remote Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give felix a single `work` command on Le-Big-Mac that brings up his own isolated userspace Tailscale (with Tailscale SSH), keeps the mac awake while a tmux session lives, and attaches — all with zero root.

**Architecture:** One new home-manager module ships `pkgs.tailscale` plus two shell entrypoints (`work`, `tsf`). `work` runs `tailscaled` in userspace-networking mode as a plain felix process, binds `caffeinate` to the tmux server pid, and attaches tmux. No boot daemon, no utun, no system sshd dependency.

**Tech Stack:** Nix home-manager (aarch64-darwin), `pkgs.writeShellApplication`, Tailscale userspace networking + Tailscale SSH, macOS `caffeinate`, tmux.

## Global Constraints

- Target host: `homeConfigurations."Le-Big-Mac"` (aarch64-darwin), file `hosts-home/Le-Big-Mac.nix`.
- felix has **no sudo**: nothing may require root, `pmset`, utun, Remote Login changes, or LaunchDaemons.
- Tailscale must run **userspace-networking** mode under felix's own tailnet account — never touch the main user's macsys system extension.
- State path: `${XDG_STATE_HOME:-$HOME/.local/state}/tailscale` (no hardcoded `/Users/felix`).
- The dev box (gurke) is x86_64-linux: aarch64-darwin configs can be **evaluated** locally but only **built/switched on the mac** (`felix@192.168.100.233`, ssh with `-F none`).
- Commit every verified logical change; stage only relevant hunks.
- Spec: `docs/superpowers/specs/2026-06-22-le-big-mac-headless-remote-workflow-design.md`.

---

### Task 1: Verify `pkgs.tailscale` is available on aarch64-darwin

**Files:** none (investigation only).

**Interfaces:**
- Produces: confirmation that `pkgs.tailscale` evaluates for aarch64-darwin and the derivation provides `tailscale` + `tailscaled`. If it does NOT, stop and report — the fallback (fetching a static tailscale build) changes Task 2 and needs a new design decision.

- [ ] **Step 1: Evaluate the pinned nixpkgs tailscale drvPath for aarch64-darwin**

Run (from repo root):
```bash
nix eval --impure --raw --expr \
  '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.aarch64-darwin.tailscale.drvPath'
```
Expected: prints a `/nix/store/...-tailscale-*.drv` path with no error.

- [ ] **Step 2: Confirm meta lists aarch64-darwin**

Run:
```bash
nix eval --impure --json --expr \
  '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.aarch64-darwin.tailscale.meta.platforms' \
  | tr ',' '\n' | grep -i darwin
```
Expected: output contains `aarch64-darwin` (or a broad `darwin`/`unix` pattern). If empty, treat as failure → report.

- [ ] **Step 3: Record result**

No commit. State in the task hand-off whether tailscale is available (proceed to Task 2) or not (halt, escalate design).

---

### Task 2: Create the `headless-mac.nix` module and wire it into Le-Big-Mac

**Files:**
- Create: `modules/home-manager/profiles/headless-mac.nix`
- Modify: `hosts-home/Le-Big-Mac.nix` (add to `imports`)

**Interfaces:**
- Produces: `work` and `tsf` executables on felix's PATH; `pkgs.tailscale` in `home.packages`. `work` is the user-facing entrypoint; `tsf ARGS` == `tailscale --socket=<felix sock> ARGS`.

- [ ] **Step 1: Write the module**

Create `modules/home-manager/profiles/headless-mac.nix` with exactly:

```nix
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
```

- [ ] **Step 2: Import it in the host config**

In `hosts-home/Le-Big-Mac.nix`, add the module to the `imports` list (alongside the existing `shell-core.nix` / `vanilla.nix` / `standalone-extras.nix` entries):

```nix
    ../modules/home-manager/profiles/headless-mac.nix
```

- [ ] **Step 3: Verify the config evaluates (local, no build)**

Run (from repo root, on the linux dev box):
```bash
nix eval --impure --json --expr \
  '(builtins.getFlake (toString ./.)).homeConfigurations."Le-Big-Mac".config.home.packages' \
  >/dev/null && echo EVAL_OK
```
Expected: `EVAL_OK` (this forces evaluation of the new module + `work`/`tsf`/`tailscale` derivations for aarch64-darwin). Any eval error here is a wiring/syntax bug — fix before committing.

- [ ] **Step 4: Commit**

```bash
git add modules/home-manager/profiles/headless-mac.nix hosts-home/Le-Big-Mac.nix
git commit -m "feat(le-big-mac): work/tsf headless workflow (userspace tailscale + caffeinate + tmux)"
```

---

### Task 3: Build and activate on the mac, verify binaries

**Files:** none (deploy + verify on `felix@192.168.100.233`).

**Interfaces:**
- Consumes: the committed module from Task 2 (push it, or pull on the mac).
- Produces: `work`, `tsf`, `tailscale`, `tailscaled` on felix's PATH on the mac.

- [ ] **Step 1: Get the commit onto the mac**

The mac builds its own config. Either push and pull the dotfiles repo, or build directly against the working tree. On the mac (`ssh -F none felix@192.168.100.233`), from felix's dotfiles checkout:
```bash
home-manager switch -b backup --flake ~/projects/dotfiles#Le-Big-Mac
```
Expected: builds and activates with no error (this is the felix-only home activation, not a system rebuild — no sudo needed).

- [ ] **Step 2: Verify the new commands exist**

On the mac:
```bash
command -v work tsf tailscale tailscaled
```
Expected: four store paths print. If `tailscaled` is missing, Task 1's assumption was wrong — halt.

- [ ] **Step 3: No commit** (deploy/verify only).

---

### Task 4: First-run Tailscale auth + remote reachability

**Files:** none (on-mac + tailnet admin console).

**Interfaces:**
- Consumes: `work`/`tsf` from Task 3.
- Produces: Le-Big-Mac joined to felix's tailnet as `le-big-mac-felix`, reachable via Tailscale SSH from another felix-tailnet device.

- [ ] **Step 1: Start the workflow over LAN**

On the mac (LAN ssh), run:
```bash
work
```
Expected: prints a `https://login.tailscale.com/...` URL, then attaches tmux. Open the URL in a browser, authenticate to **felix's** tailscale account (the isolated one, not the main user's).

- [ ] **Step 2: Confirm tailscale is up and authed**

Detach tmux (`C-a d`), then on the mac:
```bash
tsf status
```
Expected: shows `le-big-mac-felix` with a `100.x.y.z` address and state `active`/`running` (not "Logged out"/"stopped").

- [ ] **Step 3: Add the Tailscale SSH ACL rule (admin console)**

In felix's tailnet admin console (`https://login.tailscale.com/admin/acls`), ensure an `ssh` rule permits felix's own devices to SSH to this node as `felix`. For a solo tailnet the default self rule suffices:
```json
"ssh": [
  { "action": "check", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot", "felix"] }
]
```

- [ ] **Step 4: Verify remote reach from another tailnet device**

From a different device on felix's tailnet (NOT the LAN):
```bash
ssh felix@le-big-mac-felix
```
Expected: lands in a felix shell on the mac via Tailscale SSH. Run `tmux attach` to rejoin the session. (If MagicDNS is off, use the `100.x.y.z` address from Step 2.)

- [ ] **Step 5: No commit** (runtime auth/verify only).

---

### Task 5: Verify caffeine binding and tmux persistence

**Files:** none (on-mac behavior verification).

**Interfaces:**
- Consumes: a running `work` session from Task 4.

- [ ] **Step 1: Confirm caffeinate is bound to the tmux server**

On the mac, with a `work` session running:
```bash
TPID="$(tmux display-message -p '#{pid}')"; pgrep -fl "caffeinate .*-w $TPID"
```
Expected: one `caffeinate -i -s -w <TPID>` process listed.

- [ ] **Step 2: Confirm an awake assertion exists**

On the mac:
```bash
pmset -g assertions | grep -iE 'PreventUserIdleSystemSleep|caffeinate'
```
Expected: a `PreventUserIdleSystemSleep` assertion held by `caffeinate`.

- [ ] **Step 3: Confirm it releases when the session dies**

On the mac:
```bash
tmux kill-server; sleep 1; pgrep -fl caffeinate || echo NO_CAFFEINATE
```
Expected: `NO_CAFFEINATE` — killing the tmux server releases caffeine, so the mac can sleep again.

- [ ] **Step 4: Confirm idempotent re-run**

On the mac:
```bash
work   # detach with C-a d
work   # detach again
tsf status >/dev/null && echo STILL_ONE_UP
```
Expected: second `work` re-attaches without a new auth URL and without a duplicate tailscaled; `STILL_ONE_UP` prints. (Optionally `pgrep -c tailscaled` for felix's process shows the felix one is not duplicated.)

- [ ] **Step 5: No commit** (behavior verification only).

---

## Notes on caveats (already in the spec, do NOT try to "fix")

- After a **reboot** felix's tailscaled is gone (no boot daemon). Re-run `work` on LAN; state persists so no re-auth.
- **Clamshell on battery** sleeps regardless of caffeinate (`-s` ignored on battery, no root `pmset`). For long jobs: plugged in + lid open.

## Self-Review

- **Spec coverage:** connectivity (Task 2 module + Task 4 auth), wakefulness (Task 2 + Task 5), persistence (Task 2 tmux + Task 5), module layout & import (Task 2), tailscale-availability prerequisite (Task 1), ACL rule (Task 4 Step 3), caveats (Notes). All spec sections mapped.
- **Placeholder scan:** no TBD/TODO; all shell + nix shown in full.
- **Type/name consistency:** `work`, `tsf`, socket path `${XDG_STATE_HOME:-$HOME/.local/state}/tailscale/tailscaled.sock`, hostname `le-big-mac-felix` used identically across module and verification tasks.
