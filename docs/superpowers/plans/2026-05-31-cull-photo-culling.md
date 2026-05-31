# cull Photo-Culling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `home/bin/cull` tool to review and sort vacation photos/videos in the current directory — fullscreen, aspect-correct auto-zoom, arrow navigation, and del/1/2 cull keybindings with on-screen feedback and a permanent date display.

**Architecture:** A bash launcher collects+sorts media via a single `exiftool` batch call (EXIF date with mtime fallback), then starts `mpv` in fullscreen with an embedded Lua script written to a temp file. The Lua script owns navigation, the date overlay, and the file actions (trash/copy) — because those must run inside the live mpv process.

**Tech Stack:** bash, mpv (with Lua scripting), exiftool.

**Note on testing:** This is an interactive GUI tool; there is no headless test harness. Verification = (a) running the collection/sort pipeline against a sample directory to confirm ordering, and (b) a manual mpv session the user drives. No fake unit tests.

---

## File Structure

- Create: `home/bin/cull` — the entire deliverable (bash launcher + embedded Lua heredoc). One file, self-contained.
- Modify: `modules/home-manager/packages.nix` — add `mpv`, `exiftool` to the package list (separate task/commit).

---

## Task 1: Launcher core — dependency check, collection, EXIF-date sort

**Files:**
- Create: `home/bin/cull`

- [ ] **Step 1: Write the launcher skeleton (collection + sort, no mpv yet)**

Create `home/bin/cull` with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail

# cull — fullscreen photo/video reviewer + culler for the current directory.
# Spec: docs/superpowers/specs/2026-05-31-cull-photo-culling-design.md

command -v mpv >/dev/null 2>&1 || { echo "cull: mpv not found" >&2; exit 1; }
command -v exiftool >/dev/null 2>&1 || { echo "cull: exiftool not found" >&2; exit 1; }

# Supported extensions (exiftool -ext is case-insensitive).
EXTS=(jpg jpeg png heic webp gif tiff tif bmp mp4 mov mkv avi webm m4v)
ext_args=()
for e in "${EXTS[@]}"; do ext_args+=(-ext "$e"); done

tmpd="${XDG_RUNTIME_DIR:-/tmp}"
datefile="$(mktemp "$tmpd/cull-dates.XXXXXX")"
luafile="$(mktemp "$tmpd/cull-script.XXXXXX.lua")"
trap 'rm -f "$datefile" "$luafile"' EXIT

# Collect media in pwd (non-recursive: directory arg "." without -r) and get a
# sortable date key = first non-"-" of DateTimeOriginal/CreateDate/MediaCreateDate/
# FileModifyDate (-f prints "-" for missing; FileModifyDate always exists).
# Known limitation: filenames containing "|" would break field splitting (rare).
mapfile -t lines < <(
  exiftool -m -f -q -d "%Y%m%d%H%M%S" "${ext_args[@]}" \
    -p '${DateTimeOriginal}|${CreateDate}|${MediaCreateDate}|${FileModifyDate}|${FilePath}' . 2>/dev/null \
  | awk -F'|' '{
      key="00000000000000";
      for (i=1; i<=4; i++) { if ($i != "-") { key=$i; break } }
      print key "\t" $5
    }' \
  | sort -n
)

if [ "${#lines[@]}" -eq 0 ]; then
  echo "cull: no images or videos in $(pwd)" >&2
  exit 0
fi

# Split sorted lines into the mpv playlist and the path->date map for the overlay.
playlist=()
: > "$datefile"
for line in "${lines[@]}"; do
  key="${line%%$'\t'*}"
  path="${line#*$'\t'}"
  playlist+=("$path")
  human="${key:0:4}-${key:4:2}-${key:6:2} ${key:8:2}:${key:10:2}:${key:12:2}"
  printf '%s\t%s\n' "$path" "$human" >> "$datefile"
done

# (mpv launch added in Task 2)
printf '%s\n' "${playlist[@]}"   # TEMPORARY: dry-run output, removed in Task 2
```

- [ ] **Step 2: Make executable**

Run: `chmod +x home/bin/cull`

- [ ] **Step 3: Build a sample directory with known dates**

Run:
```bash
d=$(mktemp -d); cd "$d"
# three 1x1 jpgs with distinct EXIF DateTimeOriginal (needs exiftool + imagemagick 'convert')
for n in a b c; do convert -size 1x1 xc:white "$n.jpg"; done
exiftool -overwrite_original -DateTimeOriginal="2024:07:03 10:00:00" a.jpg
exiftool -overwrite_original -DateTimeOriginal="2024:07:01 09:00:00" b.jpg
exiftool -overwrite_original -DateTimeOriginal="2024:07:02 11:30:00" c.jpg
echo "$d"
```
(If `convert` is unavailable, run inside `nix-shell -p imagemagick exiftool`.)

- [ ] **Step 4: Run the collection pipeline and verify ascending order**

Run (from the sample dir): `~/projects/dotfiles/home/bin/cull`
Expected stdout (ascending by EXIF date):
```
./b.jpg
./c.jpg
./a.jpg
```

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/cull
git commit -m "feat(cull): launcher core — collect + EXIF-date sort"
```

---

## Task 2: Embed Lua script + launch mpv with navigation, zoom, loop

**Files:**
- Modify: `home/bin/cull`

- [ ] **Step 1: Replace the temporary dry-run line with the Lua heredoc + mpv launch**

In `home/bin/cull`, delete the line:
```bash
printf '%s\n' "${playlist[@]}"   # TEMPORARY: dry-run output, removed in Task 2
```
and append in its place:

```bash
# Embedded mpv Lua script (runtime-generated -> required writer header).
cat > "$luafile" <<'LUA'
-- AUTOGENERATED at runtime by cull (home/bin/cull). Edits are overwritten on the next run.
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = { datefile = "" }
options.read_options(o, "cull")

-- Arrow keys: navigate the playlist (override mpv's default LEFT/RIGHT seek).
mp.add_key_binding("LEFT",  "cull-prev", function() mp.commandv("playlist-prev") end)
mp.add_key_binding("RIGHT", "cull-next", function() mp.commandv("playlist-next") end)
LUA

mpv \
  --fullscreen \
  --loop-file=inf \
  --image-display-duration=inf \
  --no-osc \
  --script="$luafile" \
  --script-opts="cull-datefile=$datefile" \
  -- "${playlist[@]}"
```

- [ ] **Step 2: Manual verification (user-driven)**

Run from the sample dir (or a real photo/video folder): `~/projects/dotfiles/home/bin/cull`
Verify:
- Opens fullscreen.
- Image fills the screen aspect-correctly (small image scaled up, large scaled down, no stretch).
- A video in the folder plays and loops.
- LEFT/RIGHT step backward/forward through items in ascending-date order.
- An image stays on screen until a key is pressed (does not auto-advance).
- `q` quits and temp files are cleaned (`ls "$XDG_RUNTIME_DIR"/cull-*` shows nothing).

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/cull
git commit -m "feat(cull): launch mpv fullscreen with playlist navigation, zoom, loop"
```

---

## Task 3: Cull keybindings — Del (trash), 1/2 (copy) with feedback

**Files:**
- Modify: `home/bin/cull` (inside the Lua heredoc)

- [ ] **Step 1: Add the action helpers and keybindings to the Lua script**

In the Lua heredoc, insert before the closing `LUA` marker (after the LEFT/RIGHT bindings):

```lua
-- On-screen feedback (ASS-styled, ~1s). color = ASS BGR hex.
local function feedback(text, color)
  mp.osd_message(string.format("{\\1c&H%s&\\fs40\\bord3}%s", color, text), 1.0)
end

-- Absolute path of the current item (mpv paths are relative to working-directory).
local function abs_current()
  local p = mp.get_property("path")
  if not p then return nil end
  return utils.join_path(mp.get_property("working-directory"), p)
end

-- Absolute path of a target subdir in working-directory.
local function subdir(name)
  return utils.join_path(mp.get_property("working-directory"), name)
end

local function run(args)
  local r = mp.command_native({ name = "subprocess", playback_only = false, args = args })
  return r.status == 0
end

-- Del: move current file into ./trash and advance to the next.
mp.add_key_binding("DEL", "cull-trash", function()
  local src = abs_current(); if not src then return end
  local dst = subdir("trash")
  run({ "mkdir", "-p", dst })
  if run({ "mv", "--", src, dst .. "/" }) then
    feedback("→ trash", "00FFFF")        -- yellow
    mp.commandv("playlist-remove", "current")  -- auto-advances to next
  else
    feedback("✗ trash", "0000FF")        -- red
  end
end)

-- 1 / 2: copy current file into ./1 or ./2, stay on the current item.
local function copy_to(name)
  local src = abs_current(); if not src then return end
  local dst = subdir(name)
  run({ "mkdir", "-p", dst })
  if run({ "cp", "--", src, dst .. "/" }) then
    feedback("→ " .. name .. " \u{2713}", "00FF00")  -- green check
  else
    feedback("✗ " .. name, "0000FF")
  end
end
mp.add_key_binding("1", "cull-copy1", function() copy_to("1") end)
mp.add_key_binding("2", "cull-copy2", function() copy_to("2") end)
```

- [ ] **Step 2: Manual verification (user-driven)**

Run `cull` in the sample dir and verify:
- `1` → green `→ 1 ✓` flashes; a copy appears in `./1/` (item stays on screen).
- `2` → copy appears in `./2/`.
- `Del` → yellow `→ trash` flashes; file moved to `./trash/`; view advances to the next item.
- Check filesystem: `ls 1 2 trash` show the expected files.

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/cull
git commit -m "feat(cull): del/1/2 keybindings to trash/copy with OSD feedback"
```

---

## Task 4: Permanent date/time overlay

**Files:**
- Modify: `home/bin/cull` (inside the Lua heredoc)

- [ ] **Step 1: Load the date map and render a persistent bottom overlay**

In the Lua heredoc, insert after `options.read_options(o, "cull")` (before the keybindings):

```lua
-- Load the path -> human-date map written by the launcher.
local dates = {}
if o.datefile ~= "" then
  local f = io.open(o.datefile, "r")
  if f then
    for line in f:lines() do
      local p, d = line:match("^(.*)\t(.*)$")
      if p then dates[p] = d end
    end
    f:close()
  end
end

-- Persistent bottom-center date overlay, refreshed on each loaded file.
local overlay = mp.create_osd_overlay("ass-events")
local function show_date()
  local p = mp.get_property("path") or ""
  local d = dates[p] or mp.get_property("filename") or ""
  overlay.data = string.format("{\\an2\\fs28\\bord2}%s", d)
  overlay:update()
end
mp.register_event("file-loaded", show_date)
```

- [ ] **Step 2: Manual verification (user-driven)**

Run `cull` in the sample dir and verify:
- Aufnahmedatum/-zeit (e.g. `2024-07-01 09:00:00`) is shown permanently at the bottom center.
- Navigating LEFT/RIGHT updates the displayed date for each item.
- The date overlay stays visible while the action feedback (1/2/Del) flashes on top of it.

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/cull
git commit -m "feat(cull): permanent bottom date/time overlay"
```

---

## Task 5: Ensure dependencies are installed (mpv, exiftool)

**Files:**
- Modify: `modules/home-manager/packages.nix`

- [ ] **Step 1: Check whether mpv/exiftool are already present**

Run: `grep -nE 'mpv|exiftool|perlPackages\.ImageExifTool' modules/home-manager/packages.nix`
- If both already listed: skip Steps 2–4, note in the commit message that no change was needed, and move on.
- exiftool's nixpkgs attribute is `exiftool` (alias) / `perlPackages.ImageExifTool`. Prefer `exiftool` if the file uses top-level pkgs.

- [ ] **Step 2: Add any missing packages**

Add the missing entries to the package list in `modules/home-manager/packages.nix`, matching the file's existing formatting/alphabetization. Example entries:
```nix
    mpv
    exiftool
```

- [ ] **Step 3: Verify the config builds (no activation)**

Run: `nixos-rebuild build --flake ~/projects/dotfiles 2>&1 | tail -20`
Expected: builds without errors. (Do NOT run `nrs`/switch — the user activates manually.)

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/packages.nix
git commit -m "feat(packages): add mpv and exiftool for cull"
```

---

## Self-Review notes

- **Spec coverage:** fullscreen+zoom (Task 2), video+loop (Task 2), arrow nav (Task 2), date-ascending sort (Task 1), Del→trash (Task 3), 1/2→copy (Task 3), visual feedback (Task 3), permanent date display (Task 4), EXIF→mtime date source (Task 1), deps (Task 5). All covered.
- **Naming consistency:** `datefile`/`luafile`/`playlist` (bash), `abs_current`/`subdir`/`run`/`feedback`/`show_date`/`dates`/`overlay`/`o.datefile` (Lua) used consistently across tasks.
- **No placeholders:** every code step shows complete code.
