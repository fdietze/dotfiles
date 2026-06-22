# frottage wallpaper for noctalia-niri — design

Date: 2026-06-22. Status: approved, pre-implementation.

Port the herbstluftwm/gnome frottage wallpaper service (`modules/home-manager/wallpaper.nix`)
to the `noctalia-niri` specialisation (noctalia v5, C++ rewrite).

## Goal

On the `noctalia-niri` desktop, frottage's daily AI wallpaper rotates automatically
(4×/day UTC slots, dark/light variant tracking noctalia's runtime mode), set through
noctalia's own wallpaper system — without dirtying the git-tracked
`home/noctalia/settings.toml`.

## Locked facts (verified — do not re-litigate)

From noctalia source `src/shell/wallpaper/wallpaper.cpp` (pinned flake input
`/nix/store/hh34zf86m0059wlv3k1mr64cx2040m6z-source`) and live tests:

1. **Frottage must pass a unique dated path each slot.** A stable symlink path will
   NOT refresh the image: `applyWallpaperChange` skips when `newPath == currentPath`
   (line 534); `reload()` early-returns on unchanged wallpaper config and performs no
   texture reload (line 430); the texture cache keys by path; `resolvePath` only
   `lexically_normal()`s (no symlink canonicalization). So the wallpaper path noctalia
   stores must differ each slot → the dated frottage filename
   (`wallpaper-<TARGET>-<DATE>_<HH>-00-00.jpg`) is the unique key.
2. **`wallpaper-set` persists the path** into `settings.toml` via `setWallpaperPath`
   (writes `[wallpaper.default]`, `[wallpaper.last]`, `[wallpaper.monitors.<out>]`).
3. **Noctalia live-watches/reloads `settings.toml`** (confirmed: an external restore of
   the file flipped the live `color-scheme-get` result within ~2s).

Consequence: setting wallpaper 4×/day churns the git-tracked `settings.toml`. Handled by
part 3 (clean filter).

## IPC used

- `noctalia msg wallpaper-set <path>` — set + persist wallpaper (all outputs + default).
- `noctalia msg theme-mode-get` — resolved mode (`dark`/`light`) for variant selection.

## Components

### 1. Shared download helper — `modules/home-manager/frottage-download.nix`

`{pkgs}: pkgs.writeShellScript "frottage-download" ''…''`. Extracted verbatim from the
inline logic currently in `wallpaper.nix` (DRY — slot calc, download, fallback, symlink
are one piece of knowledge).

Contract:
- Arg `$1 = TARGET` ∈ `{desktop, desktop-light}`.
- Computes the current UTC slot (01/07/13/19 UTC boundaries, same 6-branch logic as
  today), builds `wallpaper-<TARGET>-<slot>.jpg`.
- Ensures it is in `${XDG_CACHE_HOME:-$HOME/.cache}/frottage/` — curl with
  `--retry 5 --retry-delay 10 --retry-all-errors`; on failure falls back to the newest
  cached `wallpaper-*.jpg`.
- Maintains `~/.cache/frottage/current-wallpaper.jpg` symlink → the resolved file
  (needed by both desktops and as the clean-filter placeholder / startup fallback).
- **stdout:** the single absolute path to use. **stderr:** all logging.
- **Exit:** 0 if a usable path was printed, 1 otherwise.

`wallpaper.nix` is refactored to call the helper and keep its own `set_wallpaper`
(feh / GNOME gsettings) backend:
`path="$(${frottageDownload} "$TARGET")" && set_wallpaper "$path"`. The
`current-wallpaper.jpg` symlink maintenance moves out of `set_wallpaper` into the helper.
Herbstluftwm/gnome behavior must be unchanged — verify by building the home-manager
generation and inspecting the rendered scripts.

### 2. noctalia module — `modules/home-manager/desktops/noctalia-frottage.nix`

Whole body gated `lib.mkIf (desktop == "noctalia-niri")`. Imports the shared helper.

- **Script `frottage-noctalia [mode]`** (`home.file."bin/frottage-noctalia"`,
  `pkgs.writeShellScript`, like `noctalia-gtk-theme`):
  ```
  mode="${1:-$(noctalia msg theme-mode-get)}"
  case "$mode" in light) target=desktop-light;; *) target=desktop;; esac
  path="$(frottage-download "$target")" && noctalia msg wallpaper-set "$path"
  ```
  Uses absolute `${frottageDownload}` store path, not PATH lookup.
- **`systemd.user.services.frottage`**: `Type=oneshot`,
  `ExecStart = frottage-noctalia` (no arg → derives mode). `After`/`Wants`
  network-online + nss-lookup + graphical-session-pre; `PartOf graphical-session.target`.
- **`systemd.user.timers.frottage`**: `OnCalendar=*-*-* 01,07,13,19:00:00 UTC`,
  `OnActiveSec=15s`, `Persistent=true`, `WantedBy=timers.target`. (Same schedule as
  herbstluftwm.) Service/timer name `frottage` is reused; safe because `wallpaper.nix`'s
  same-named units are gated to themed desktops, mutually exclusive with this one.
- **noctalia template `frottage-trigger`** contributed to
  `programs.noctalia.settings.theme.templates.user` (nix merges across modules):
  - source `home/noctalia/templates/frottage-trigger.txt` = `{{mode}}` (re-renders on
    every mode change; picked up by the existing `noctalia/templates` symlink).
  - `output_path = generated/frottage-trigger.txt`.
  - `post_hook = "<home>/bin/frottage-noctalia {{mode}}"`.
  Fires `frottage-noctalia` with the authoritative mode on every dark/light toggle and at
  startup. Mirrors the existing `gtk-theme-trigger`.

No HM-activation download (would block activation on network). Startup is covered by the
post_hook + timer `Persistent`; noctalia's persisted placeholder shows pre-render.

### 3. Clean filter — keep tracked `settings.toml` clean

- **`home/bin/noctalia-wallpaper-clean`** (committed, executable, `#!/usr/bin/env bash`,
  uses `sed`): reads stdin, writes stdout. Normalizes every
  `^(\s*path = ").*frottage[^"]*(")$` → `\1~/.cache/frottage/current-wallpaper.jpg\2`.
  Idempotent. Only rewrites paths containing `frottage`, so hand-picked wallpapers stay
  tracked. bash+sed (not rust-script) is the deliberate KISS choice for a one-line text
  stream filter, consistent with the other `home/bin/` scripts. Installed unconditionally
  (on PATH all specs via `home/bin`), so `git add` of `settings.toml` works on every spec.
- **`home/files/.gitconfig`**: add
  ```
  [filter "noctalia-wallpaper"]
      clean = noctalia-wallpaper-clean
  ```
  (definition is global; only activated where `.gitattributes` says so.)
- **`.gitattributes`** (new, repo root):
  ```
  home/noctalia/settings.toml filter=noctalia-wallpaper
  ```

Net: noctalia stores a unique dated path in the working-copy `settings.toml` (so the
image refreshes), but on `git add` the clean filter collapses every frottage path to the
one stable `current-wallpaper.jpg` placeholder → index matches the committed baseline →
no diff, tree stays clean. The rest of `settings.toml` is tracked normally.

### 4. Baseline commit

Update committed `home/noctalia/settings.toml` so `[wallpaper.*]` paths are the
`~/.cache/frottage/current-wallpaper.jpg` placeholder (frottage now owns the wallpaper).

## Out of scope (YAGNI)

- HM-activation wallpaper download.
- noctalia's native folder automation (does not download new frottage art).
- Stable-symlink IPC refresh (proven not to refresh).
- Touching the legacy manual `home/bin/frottage` / `frottage-save` scripts.

## Implementation / verification order (incremental, commit each)

1. Extract `frottage-download.nix`; refactor `wallpaper.nix` to use it. Build the HM
   generation; confirm the herbstluftwm frottage scripts are behavior-equivalent. Commit.
2. Add clean filter (script + `.gitconfig` + `.gitattributes`). Test:
   `printf '...frottage...' | noctalia-wallpaper-clean` is idempotent; a frottage-path
   `settings.toml` stages with no diff. Commit.
3. Add `noctalia-frottage.nix`; import it next to `noctalia-niri.nix` in the host
   `home.nix`. Build. On the live noctalia spec: run `frottage-noctalia`, confirm
   `wallpaper-get` updates and the image changes; toggle mode, confirm variant swap;
   confirm `git status` stays clean. Commit.
4. Update committed `settings.toml` baseline to the placeholder. Commit.

## Risks / gotchas

- **Live-managed file:** never `git checkout` / overwrite `home/noctalia/settings.toml`
  while noctalia runs — it watches and reloads, and a bad write reverts live theme state.
- **Filter availability:** the clean command must resolve on every spec (hence
  unconditional `home/bin` install); a missing filter command makes `git add` fail.
- **Offline first boot:** no cache + no network → `frottage-noctalia` skips `wallpaper-set`
  (the `&&` short-circuits); noctalia keeps the placeholder. Acceptable.
- **Mode source:** `theme-mode-get` returns the resolved mode (auto → dark/light), which
  is what we want for variant selection.
