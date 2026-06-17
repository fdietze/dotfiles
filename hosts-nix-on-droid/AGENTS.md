# nix-on-droid hosts

Context for Android (nix-on-droid) hosts. Each host's config entrypoint is its
`<name>.nix` (imported by `flake.nix` `mkNixOnDroid`). The runtime hostname is
always `localhost`; the stable identifier is the flake output name.

## Command channel: SSH (preferred for all nix work)
- nix-on-droid `sshd` runs on port **8022** (start on device with `sshd-start`).
- SSH lands in a real NoD shell with the full environment (the app login shell
  sources `nix-on-droid-session-init.sh`). Use it for git/switch/run — far more
  reliable than typing into the terminal via adb.
- If a broken global `ssh_config` aborts the connection, pass `-F /dev/null`.
- sshd from `sshd-start` runs in the *foreground of the app's terminal*. By
  default Android freezes the app when it loses foreground (it is not Doze-
  whitelisted), so sshd dies mid-session when you bring another app forward (e.g.
  Termux:X11 for a screenshot). **Fix (verified): disable battery optimization
  for the app** (Settings → Apps → nix-on-droid → Battery → Unrestricted). The
  ongoing session notification (a foreground service) then keeps it from being
  killed, and the exemption stops Doze freezing it — sshd survives backgrounding
  with the screen on. Only screen-off/Doze additionally needs a wakelock.
  Note: while that terminal runs sshd it is busy, so adb-typed commands there go
  to sshd's stdin, not a shell.
- `scp`/`rsync` fail over this sshd (the app login-shell wrapper breaks scp's
  protocol). To push a file without git, pipe it through the shell:
  `ssh … 'cat > path/file' < localfile` (verify with `sha256sum` both sides).
  Iterate edits locally, cat-pipe to the device clone, switch, verify, then
  commit once — a dirty git tree is fine for `switch` (no per-iteration commit).

## Screen + input channel: adb (visual verification, app launching)
- Classic wireless adb listens on device port **5555** once enabled; connect with
  `adb connect <device-ip>:5555`.
- nixpkgs `android-tools` (`nix-shell -p android-tools`) can `adb connect` but
  **cannot `adb pair`** — it is built without mDNS/openscreen, so `adb pair`
  fails with `protocol fault (couldn't read status length)`. Pair beforehand by
  other means (e.g. Google platform-tools), then `connect` works.
- Recipes (all with `-s <device-ip>:5555`):
  - screenshot: `adb … exec-out screencap -p > shot.png`
  - wake: `adb … shell input keyevent KEYCODE_WAKEUP`
  - launch app: `adb … shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`
  - type: `adb … shell input text "a%sb"` — spaces are `%s`; **double-quotes are
    silently dropped**, so avoid commands whose args need quoting.
- App package ids: regular Termux `com.termux`, nix-on-droid `com.termux.nix`,
  Termux:X11 `com.termux.x11`.
- `screencap` returns an all-black PNG (~15 KB) for a sleeping display and for
  secure screens (a lockscreen PIN pad is `FLAG_SECURE`); unlock is manual.

## X11 (Termux:X11 + nix-on-droid), see nix-community/nix-on-droid#305
- nix-on-droid **cannot host the X server** (the Termux:X11 launcher needs
  Android's `app_process`). So the X server stays in **regular Termux** and the
  desktop/clients run from nix-on-droid over **loopback TCP**.
- Termux (X server): `termux-x11 :1 -listen tcp`. The `-listen tcp` is the whole
  trick; `-ac` is not needed. The Termux:X11 app is the actual server.
- nix-on-droid (client): `DISPLAY=127.0.0.1:1` (TCP). Do **not** use `DISPLAY=:1`
  — the unix socket hits the proot shared-`/tmp` problem.
- Keep the X client config in a small HM module (e.g. `x11.nix`) imported by the
  host. Smoke-test: `xdpyinfo` should report the server; xeyes should render.
- Ad-hoc test without a switch: `DISPLAY=127.0.0.1:1 nix run nixpkgs#xorg.xeyes`
  (first nixpkgs fetch on-device is slow).
- Gotchas:
  - **Terminal: use st (or alacritty/kitty), NOT xterm/urxvt.** xterm's `spawn()`
    unconditionally calls `setuid(getuid())`, which returns `ENOSYS` under proot
    (`spawn: setuid() failed`) — no flag avoids it, so xterm can never launch a
    shell here. st/alacritty/kitty don't setuid and work.
  - **fontconfig:** a non-NixOS NoD has no `/etc/fonts/fonts.conf`, and HM's
    `fonts.fontconfig` only drops `conf.d` snippets — so Xft clients die with
    `Cannot load default config file`. Use `pkgs.makeFontsConf { fontDirectories
    = [ <font> ]; }` and point `FONTCONFIG_FILE` (sessionVariables) at it. (xeyes
    needs no fonts, which is why it renders before fontconfig is fixed.)
  - nixGL is only needed for GL/accelerated apps (compositor); a plain WM + a
    software-rendered terminal do not need it.

## Switch / verify workflow
- The device switches with `nix-on-droid switch --flake .#<name>` from a local
  clone. **Push commits to origin first** so the device can `git pull` them.
- Build-verify from the workstation (no aarch64 builder needed):
  `nix eval --impure .#nixOnDroidConfigurations.<name>.activationPackage.drvPath`
  evaluates the full module system. A non-fatal failure *realizing* a CI-built
  store path (no local substituter) is environmental, not a config error.
  Targeted checks read into
  `.#nixOnDroidConfigurations.<name>.config.home-manager.config.…`.
- Flakes only see git-tracked files; `git add` new files before evaluating.
