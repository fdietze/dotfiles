# Noctalia v4 → v5 migration (this repo)

Last investigated: 2026-06-17. Locked v5 rev `faebcd38…` (C++ rewrite).

## What changed upstream

v5 is a ground-up rewrite, not a point upgrade.

| Area        | v4                                | v5                                      |
| ----------- | --------------------------------- | --------------------------------------- |
| Engine      | Quickshell / Qt / QML             | native C++ Wayland/OpenGL ES            |
| Binary      | `noctalia-shell`                  | `noctalia`                              |
| Config      | `settings.json` (+ `plugins.json`)| `config.toml` (all config-dir `*.toml`) |
| GUI state   | written into config dir           | `$XDG_STATE_HOME/noctalia/settings.toml`|
| Config model| app-written JSON                  | defaults → config-dir `*.toml` (deep-merged, alphabetical) → state `settings.toml` (deep-merged on top) |
| IPC         | `noctalia-shell ipc call X Y`     | `noctalia msg <cmd>`                    |
| HM module   | enable-only                       | `settings` (TOML), `customPalettes` (JSON), `systemd.enable`, `validateConfig` |

Key source facts verified in the locked tree:

- Custom palettes load from `<config-dir>/palettes/<name>.json` with the exact
  `dark`/`light` + `mPrimary…` + `terminal` shape that `modules/themes/noctalia-scheme.nix`
  already emits (`src/theme/custom_palettes.cpp`). Port is ~1:1.
- Template engine uses the **same** `{{colors.terminal_*.default.hex}}` / `{{mode}}`
  syntax as v4 (`src/theme/template_engine.cpp`); our stock-shaped template sources
  are unchanged. User templates move to `[theme.templates.user.<name>]`, `input_path`
  resolves relative to the config dir (supports `~`, `$XDG_*`).
- Config files deep-merge recursively (`ConfigService::deepMerge`), so a nix-owned
  `config.toml` carrying only `[theme.templates.user.*]` coexists with the GUI's
  `settings.toml` without clobbering.
- `settings.toml` is written with `writeTextFileAtomic` which **resolves symlinks**
  (`src/config/atomic_file.cpp`: `resolveAtomicWriteTarget` → `canonical`, then
  `<target>.tmp` + rename in the target's dir). So an out-of-store symlink at
  `~/.local/state/noctalia/settings.toml` is written *through* to the repo file and
  is never clobbered.

## Decisions for this repo

- **Ride v5** (v4 is the abandoned QML branch).
- **GUI is source of truth.** No declarative `settings` for user-facing options.
- **Track only `settings.toml` in git**, via an out-of-store symlink
  `~/.local/state/noctalia/settings.toml → home/noctalia/settings.toml`. Caches
  (clipboard history, plugin/notification caches, exports) stay in `~/.local/state`,
  out of the repo (and out of reach of sandboxed agents).
- **nix owns** only the theming plumbing in the config dir: `config.toml`
  (templates), `palettes/Base16.json` (from `noctalia-scheme.nix`, shared with the
  herbstluftwm/stylix X11 desktop), and the template source files.
- **Drop** the old whole-dir `mkOutOfStoreSymlink ~/.config/noctalia → repo`.

## Filesystem layout after migration

```
~/.config/noctalia/              normal dir; nix owns sub-paths, noctalia writes the rest
├── config.toml                  nix (programs.noctalia.settings): only [theme.templates.user.*]
├── palettes/Base16.json         nix (programs.noctalia.customPalettes), from noctalia-scheme.nix
├── templates/                   nix (out-of-store symlink → repo templates/), source files
└── generated/*                  noctalia runtime output (not tracked)

~/.local/state/noctalia/
├── settings.toml                out-of-store symlink → repo home/noctalia/settings.toml (TRACKED)
└── (clipboard, plugins, exports, …)   runtime only, never in repo

~/projects/dotfiles/home/noctalia/
├── templates/                   template sources (kept)
└── settings.toml                GUI config (tracked; noctalia writes through the symlink)
```

Deleted v4 artifacts: `settings.json`, `plugins.json`, `colors.json`,
`user-templates.toml`, `plugins/`, `colorschemes/`.

## IPC mapping (niri binds)

| v4 `ipc call`                       | v5 `msg`                          |
| ----------------------------------- | --------------------------------- |
| `launcher toggle`                   | `panel-toggle launcher`           |
| `lockScreen lock`                   | `session lock`                    |
| `darkMode setLight` / `setDark`     | `theme-mode-set light` / `dark`   |
| `volume increase`/`decrease`/`muteOutput` | `volume-up`/`volume-down`/`volume-mute` |
| `brightness increase`/`decrease`    | `brightness-up`/`brightness-down` |
| `bluetooth toggle`                  | `bluetooth-toggle`                |
| `media previous`/`play`/`playPause`/`stop`/`next` | `media-prev`/`media-play`/`media-pause`/`media-pause`/`media-next` |

Startup: `spawn-at-startup "noctalia-shell"` → `"noctalia"`.
v5 has no `media-stop`/`media-playpause`; both map to `media-pause`.
