# Nix-on-Droid Arrow Key Regression Handoff

## RESOLVED (2026-06-10)

Root cause found and fixed in commit `20a745f`. **The hypotheses below (proot
fd loss, login chain, seccomp, `.inputrc` mode) are all dead ends — superseded
by this section.**

Real cause, isolated by a controlled single-device A/B test on a fresh second
device (`kartoffel`): with the identical app-bundled proot, the same app pty
gives `isatty(0)=true` under the app's bash 5.2 but `isatty(0)=false` under
nixpkgs bash 5.3.9 — only the bash binary changed. Newer bash/glibc issue the
`TCGETS2` tty ioctl, which the app-bundled proot (proot-termux 2024-05-04)
rejects with `EACCES`; stdin then looks like a non-tty, readline cannot enter
raw mode, and arrow keys print `^[[A`. korken pulled `pkgs.bashInteractive`
(5.3.9) from master; fresh/`kartoffel` use the app's bash 5.2, which works.

Fix: build the app login shell from the matching `nixos-24.05` toolchain
(already an input as `nixpkgs-nix-on-droid`, bash 5.2p32) instead of master.

Key methodology notes for anyone revisiting:
- `pty.fork`/`openpty` ptys (proot-internal) fail `TCGETS` on *every* device and
  are **not representative** of the app terminal's host-allocated pty. Test the
  actual app pty (in the app terminal), not a self-allocated one.
- This is an instance of nix-on-droid issue #515 (newer toolchains vs the old
  proot's tty ioctls). The proper upstream fix is a newer proot; pinning the
  app shell to 24.05 is a targeted workaround. Other interactive programs built
  against newer glibc (vim, fzf, ...) may hit the same wall until proot is updated.

## Problem Definition

The `korken` Nix-on-Droid configuration activates successfully and provides a usable shell, but the Android app terminal does not handle arrow keys correctly after activation.

Observed behavior in the Nix-on-Droid app after a full app restart and fresh foreground shell:

- Pressing only arrow keys prints escape sequences like `^[[D`, `^[[C`, `^[[A`, `^[[B`.
- This happens even after forcing Android-specific readline configuration to `emacs` mode.
- The same Nix-on-Droid app reportedly handled arrow keys correctly before switching to this repository's `korken` configuration.

The goal for the next engineer is to identify the exact config/runtime change that makes the app foreground shell lose normal terminal/readline behavior, then choose the smallest fix.

## Current Known-Good State

Repository and device state at handoff:

- Local branch: `master`.
- Latest pushed commit: `fc2862d fix(shell): include baseline diagnostic tools`.
- Android repo path: `/data/data/com.termux.nix/files/home/projects/dotfiles`.
- Android user: `felix`.
- Nix-on-Droid flake output: `.#korken`.
- Manual SSH helper is installed and can be started with `sshd-start`.
- SSH access, when `sshd-start` is running: `ssh -i /tmp/opencode/nix-on-droid-ssh -p 8022 felix@192.168.100.230`.
- Current known-hosts file used during debugging: `/tmp/opencode/nix-on-droid-known-hosts-final`.
- Device command environment usually needs:
  ```sh
  export HOME=/data/data/com.termux.nix/files/home
  export TMPDIR=/data/data/com.termux.nix/files/usr/tmp
  export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/system/bin:/usr/bin:/bin"
  ```

Important local worktree caveat:

- The local repo has unrelated dirty files under Noctalia/opencode and an unrelated existing edit in `modules/home-manager/profiles/packages-cli.nix` around the opencode wrapper. Do not stage unrelated hunks.

## Relevant Commits

These commits are directly relevant to the current Nix-on-Droid state:

- `3709b1d fix(korken): use stable nix on android`
  Pins only the Nix package used by Nix-on-Droid to Nix 2.18.8 from `nixpkgs/nixos-24.05`, avoiding newer Nix builder PTY failures tracked upstream.
- `c2794f7 fix(korken): support nix 2.18 profile entries`
  Makes the `installPackages` activation override support Nix 2.18 profile JSON shape.
- `35896ab fix(korken): let nix-on-droid install hm packages`
  Re-enables `home-manager.useUserPackages` and disables the legacy priority hook.
- `35d1bec feat(korken): add manual sshd helper`
  Adds `sshd-start`, declarative `openssh`, host key generation, and committed `authorized_keys` for manual LAN/Tailscale SSH access.
- `620096f fix(korken): use bash as app login shell`
  Replaced zsh as the app entry shell with bash.
- `24c4140 fix(korken): use plain bash prompt on android`
  Disabled Starship bash integration for Android and added a plain `PS1`.
- `ec25171 fix(korken): preserve ssh shell commands`
  Uses a generated `user.shell` wrapper that preserves `ssh user@host command` but forces `bash -i` for app launches with no arguments.
- `b58a31f fix(shell): include grep in core cli packages`
  Adds `gnugrep` after startup hooks emitted `grep: command not found`.
- `efcb61c fix(korken): force emacs inputrc on android`
  Initial attempt to force Android `.inputrc` to emacs mode using `home.file.".inputrc".text`.
- `b9b61e8 fix(korken): use writeText to override inputrc source`
  Correctly overrides the Home Manager `.inputrc` source with `pkgs.writeText`, because `text` alone did not override the existing `source` from `home/files/.inputrc`.
- `fc2862d fix(shell): include baseline diagnostic tools`
  Adds `gnused`, `procps`, and `iproute2` to the core shell profile.

## Verified Findings

### Activation Works

The `korken` configuration builds and activates successfully. Recent activation after `b9b61e8` built and activated:

- `nix-on-droid-inputrc.drv`
- `home-manager-files.drv`
- `home-manager-generation.drv`
- `activation-script.drv`
- `nix-on-droid-generation.drv`

The device subsequently pulled and activated `fc2862d` successfully.

### Baseline Tools Added

The following tools are now in the core shell profile and were verified on-device:

```text
sed=/data/data/com.termux.nix/files/home/.nix-profile/bin/sed
ps=/data/data/com.termux.nix/files/home/.nix-profile/bin/ps
pgrep=/data/data/com.termux.nix/files/home/.nix-profile/bin/pgrep
pkill=/data/data/com.termux.nix/files/home/.nix-profile/bin/pkill
ip=/data/data/com.termux.nix/files/home/.nix-profile/bin/ip
```

Caveat: Nix `procps` `ps` may print `Unable to get system boot time` under this Android/proot environment. `/system/bin/ps` may be more reliable for Android process inspection.

### `.inputrc` Is Correct and Active

On-device verification after `b9b61e8`:

```text
/data/data/com.termux.nix/files/home/.inputrc -> /nix/store/...-home-manager-files/.inputrc
```

Contents:

```text
# Managed by Nix-on-Droid/korken.
# Emacs mode is used to bypass proot timing bugs that break vi-mode arrow keys.
set editing-mode emacs
```

Foreground app diagnostic confirmed:

```text
set editing-mode emacs
"\e[D": backward-char
"\e[C": forward-char
"\e[B": next-history
"\e[A": previous-history
```

Therefore the current problem is not that readline is still in vi mode, and not that arrow keys are unbound in readline.

### Foreground App Shell Is Interactive

Foreground app diagnostic after sourcing a no-`exec` diagnostic script:

```text
flags=himBHs
TERM=xterm-256color
INPUTRC=UNSET
```

The shell is interactive and uses default `$HOME/.inputrc`, which is correct.

### Foreground App Shell Has Broken TTY Access

Same foreground app diagnostic:

```text
tty=not a tty
stty: 'standard input': Permission denied
```

This is the central unresolved fact. Readline has correct config and bindings, but the process cannot treat stdin as a usable TTY. That can explain why escape sequences are echoed literally.

### `exec -l bash` Does Not Fix It

Typed into the app via ADB:

```sh
exec -l bash
```

After this, the foreground app shell measured:

```text
flags=hBs
tty=not a tty
stty: 'standard input': Permission denied
```

This means the generated app login wrapper is not the only cause.

### Minimal Shell Bypass Test Was Inconclusive

Attempted to type via ADB:

```sh
env -i HOME=/data/data/com.termux.nix/files/home TERM=xterm-256color PATH=... INPUTRC=/data/data/com.termux.nix/files/home/.inputrc exec bash --noprofile --norc -i
```

and later:

```sh
exec bash --noprofile --norc -i
```

The first test did not clearly replace the foreground process. The second appears to have affected the session but did not leave a clearly measurable replacement bash. Do not treat this as a falsified or confirmed hypothesis.

### Active Runtime Uses Declarative Nix-on-Droid `proot-static`

On-device runtime comparison:

```text
configured proot path:
/nix/store/7qd99m1w65x2vgqg453nd70y60sm3kay-proot-termux-static-aarch64-unknown-linux-android-unstable-2024-05-04

configured proot hash:
149a6785215dcf9996286b5de2346fb6a6a36e908fc752b512085ff3af592248

installed /bin/proot-static hash:
149a6785215dcf9996286b5de2346fb6a6a36e908fc752b512085ff3af592248
```

So the app is using the proot runtime installed by the Nix-on-Droid activation.

`/usr/lib/login-inner` is also generated by activation and currently contains:

```sh
usershell="/nix/store/...-nix-on-droid-app-login-shell/bin/nix-on-droid-app-login-shell"
...
exec -a "-${usershell##*/}" "$usershell"
```

## Falsified or Weakened Hypotheses

### Zsh Startup Is Not the Cause

The app login shell was changed from zsh to bash. The no-prompt and arrow-key symptoms persisted.

### Starship Prompt Is Not the Cause

Starship bash integration was disabled for Android and a plain `PS1` was set. The app prompt improved, but arrow keys still print escape sequences.

### `.inputrc` Source Override Was Initially Wrong, but Is Now Fixed

The original `home.file.".inputrc".text = lib.mkForce ...` did not work because `home.file.".inputrc".source` still came from `home/files/.inputrc` through `dotfiles.nix`.

Correct fix is active now:

```nix
home.file.".inputrc".source = lib.mkForce (pkgs.writeText "nix-on-droid-inputrc" ''
  # Managed by Nix-on-Droid/korken.
  # Emacs mode is used to bypass proot timing bugs that break vi-mode arrow keys.
  set editing-mode emacs
'');
```

Diagnostics confirm it is active.

### User Shell Wrapper Alone Is Not the Cause

Running `exec -l bash` in the app did not restore TTY behavior.

## Strongest Current Hypothesis

Fresh Nix-on-Droid arrow keys worked before activation. After `nix-on-droid switch`, activation replaces the app's runtime pieces, including `/bin/proot-static` and `/usr/lib/login-inner`. After activation, foreground app shells report `tty=not a tty` and `stty` permission errors.

Therefore, the likely regression boundary is one of:

1. The declarative `proot-static` installed by Nix-on-Droid activation.
2. The generated `login-inner` script and how it launches the shell.
3. Session-init/profile behavior before shell launch.
4. A combination of Nix-on-Droid's proot runtime and this configuration's shell/session setup.

This should be investigated before adding more readline or shell keybinding tweaks.

## Upstream Context

Relevant upstream issues/PRs found earlier:

- Nix-on-Droid issue `#495`: activation failure with newer nix/nixos-unstable; error involved `getting pseudoterminal attributes: Permission denied`.
- Nix-on-Droid issue `#515`: terminal programs report stdin/stdout are not terminals; process/session layout under `proot-static` differs from regular Termux.
- Nix-on-Droid PR `#529`: updates `proot-termux` and mentions terminal ioctl fixes around `TCGETS`/`TCSETS`.
- Nix-on-Droid PR `#516`: larger update for Nix 2.34/nixos-25.11/proot changes; not obviously safe as a direct fix.

The current repo already pins only the Nix binary to Nix 2.18.8 to avoid builder PTY failure, but still uses Nix-on-Droid's current configured proot runtime.

## Recommended Next Tests

Do these in order. Avoid permanent config changes until one test clearly narrows the boundary.

### 1. Establish a Clean Fresh-Baseline Capture

On a truly fresh Nix-on-Droid install before running this repo's activation, record:

```sh
tty || true
stty -a || true
printf 'flags=%s\n' "$-"
printf 'TERM=%s\n' "$TERM"
ps -A | grep -E 'proot-static|bash|login-inner' || true
sha256sum /data/data/com.termux.nix/files/usr/bin/proot-static 2>/dev/null || true
sed -n '1,80p' /data/data/com.termux.nix/files/usr/usr/lib/login-inner 2>/dev/null || true
```

Expected value: this is the state where arrow keys reportedly work. Capture the exact proot hash and login-inner behavior.

### 2. Compare Pre-Activation vs Post-Activation Runtime Files

After `nix-on-droid switch --flake ~/projects/dotfiles#korken`, compare:

```sh
sha256sum /data/data/com.termux.nix/files/usr/bin/proot-static
sed -n '1,80p' /data/data/com.termux.nix/files/usr/usr/lib/login-inner
```

The current post-activation proot hash is:

```text
149a6785215dcf9996286b5de2346fb6a6a36e908fc752b512085ff3af592248
```

If fresh baseline differs and arrows work only with the baseline proot, the next fix candidate is to preserve or pin the working proot package.

### 3. Test Disabling Only `installProotStatic`

If the fresh proot binary differs from declarative proot, test a local branch that prevents Nix-on-Droid activation from replacing `/bin/proot-static`.

Candidate shape in `nix-on-droid/korken.nix`:

```nix
build.activation = lib.mkAfter {
  installProotStatic = ''
    :
  '';
};
```

This should only be tested if a known-good fresh proot binary is still installed or restored. The point is to isolate proot replacement from other activation changes.

### 4. Test Default Login Fallback Without Wrapper

Temporarily configure `user.shell` to a non-executable path or directory to force Nix-on-Droid's fallback branch:

```sh
exec -l bash
```

But note: manual `exec -l bash` inside the current broken session did not restore TTY behavior, so this is lower priority than proot comparison.

### 5. Test a Newer Proot From Upstream PR

If fresh proot differs or upstream issue `#515` matches, test a newer `proot-termux` from the upstream PR that fixes terminal ioctls. This is likely more complex because the current Nix-on-Droid module hardcodes store paths for `proot-termux-static` in `modules/environment/login/default.nix`.

Do not switch the entire stack to a newer Nix/NixOS blindly: prior testing showed newer Nix versions on Android can trigger builder PTY failures.

### 6. Keep SSH as the Reliable Control Plane

Because app terminal PTY behavior is unstable, use `sshd-start` for all investigation. The app terminal can still be used for foreground reproduction and ADB input, but avoid relying on it for long commands.

## Commands Useful for the Next Engineer

SSH:

```sh
ssh -i /tmp/opencode/nix-on-droid-ssh \
  -o UserKnownHostsFile=/tmp/opencode/nix-on-droid-known-hosts-final \
  -o StrictHostKeyChecking=yes \
  -p 8022 felix@192.168.100.230
```

ADB text injection example:

```sh
nix shell nixpkgs#android-tools -c adb shell "input text 'sshd-start' && input keyevent 66"
```

Pull and activate:

```sh
export HOME=/data/data/com.termux.nix/files/home
export TMPDIR=/data/data/com.termux.nix/files/usr/tmp
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/system/bin:/usr/bin:/bin"
cd "$HOME/projects/dotfiles"
git pull --ff-only
nix-on-droid switch --flake "$HOME/projects/dotfiles#korken"
```

Foreground app shell diagnostic script:

```sh
cat > "$HOME/arrow-diag-safe.sh" <<'EOF'
#!/usr/bin/env bash
{
  printf "=== shell ===\n"
  printf "pid=%s ppid=%s flags=%s\n" "$$" "$PPID" "$-"
  printf "tty=%s\n" "$(tty 2>&1)"
  printf "TERM=%s INPUTRC=%s\n" "${TERM-UNSET}" "${INPUTRC-UNSET}"
  printf "=== stty ===\n"
  stty -a || true
  printf "=== readline mode ===\n"
  bind -v | grep editing-mode || true
  printf "=== arrow bindings ===\n"
  bind -p | grep -E "\\e\[[ABCD]|\\eO[ABCD]|previous-history|next-history|forward-char|backward-char" | grep -v "^#" || true
  printf "=== inputrc ===\n"
  ls -la "$HOME/.inputrc" || true
  cat "$HOME/.inputrc" || true
  printf "=== proc stat current ===\n"
  cat "/proc/$$/stat" || true
} >"$HOME/arrow-diag-safe.txt" 2>&1
EOF
chmod +x "$HOME/arrow-diag-safe.sh"
```

Run it in the foreground app session via ADB:

```sh
nix shell nixpkgs#android-tools -c adb shell "input text '.%s~/arrow-diag-safe.sh' && input keyevent 66"
```

Then read it over SSH:

```sh
cat "$HOME/arrow-diag-safe.txt"
```

## Do Not Assume

- Do not assume another `.inputrc` setting will fix this. Readline config is currently correct.
- Do not assume zsh/starship is responsible. Those were already bypassed or disabled for the app shell.
- Do not assume `procps ps` works reliably under Android/proot. Prefer `/system/bin/ps` when process listing looks broken.
- Do not reset the device unless you need a fresh baseline capture and accept losing app data.
