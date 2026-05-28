- my dotfiles are managed with a normal git repository at `~/projects/dotfiles`. Use regular `git` and `tig` from that repository.
- commit every logical meaningful change after it was verified. stage individual hunks if necessary.
- I value simplicity, minimalism and elegance. YAGNI, KISS, SoC.
- automatically read relevant man pages and documentation websites before deciding or implementing anything
- before suggesting any config syntax, look up the official documentation to verify the syntax is correct
- configurations and programs should be resource friendly. Prefer rust(-script) over scripting languages. Allow the cpu to go into deep sleep states.
- the nixos and home manager configurations should be the source of truth
- when switching the current system, make sure to stay on the same specialization. You can simply use the already existing nrs script.
- automatically read analyze relevant log files and/or run commands like journalctl to get them
- you can assume all binaries in the nix store exist when referencing like this: "${pkgs.mypackage}/bin/mycommand"
- never search or grep the full nix store
- you can read specific files and dirs, like ~/bin or ~/.config IN $HOME, but not list files in home
- use `nixos-option` to find nixos options, e.g. services.xserver.xkb.layout
- to figure out what exactly some software is doing, trace the nix build down to the source code. 
- use DeepWiki MCP to answer questions about some repository
- for package investigations on flake-based systems, treat `flake.lock` as the source of truth for the pinned nixpkgs revision
- when tracing a package, prefer querying the pinned flake input directly with `nix flake metadata --json .` and `nix eval --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs...'` instead of assuming this repo exports `packages` or `legacyPackages`
- when `nix eval` on a local path flake uses `builtins.getFlake (toString ./.)`, add `--impure`
- if `nix eval` or related commands fail on `/nix/var/nix/daemon-socket/socket`, immediately rerun with escalation instead of working around it
- prefer this package tracing order: config reference -> pinned flake input -> package metadata via `nix eval` -> nixpkgs package definition or generated index -> installed runtime files -> upstream source/issues/PRs
- for `pkgs.gnomeExtensions.*`, check `pkgs/desktops/gnome/extensions/extensions.json` and `buildGnomeExtension.nix` before assuming there is a dedicated `*.nix` package file
- for GNOME extensions, note that nixpkgs `version` may be the extensions.gnome.org build number, while the human-facing extension version may live in embedded metadata like `version-name`
- if a `src.outPath` store path is not realized or readable, inspect the pinned nixpkgs source tree and the installed runtime files under `/run/current-system/sw` or `/etc/profiles/per-user/...` instead
- for live desktop investigations, prefer checking the actually installed runtime files and session state, not just the derivation metadata
- if desktop debugging touches live GNOME session state, expect `gnome-extensions`, `dconf`, and `/run/user/*` access to require escalation
- If a nix let binding is reused across the whole module, keep it in the top-level let.
- If it is only used by one option block, move it into a local let right above that
block.
- Prefer the narrowest scope that still keeps the code readable.
- for refactorings, use nvd to verify that the generated nix code is exactly the same before and after and only shows the desired changes. When comparing specializations, anchor on `/nix/var/nix/profiles/system/specialisation/<name>` — not `/run/current-system/specialisation/<name>`, which only resolves when the parent toplevel is booted (check `cat /run/nixos/current-specialisation` to see which spec is active).
- to know how other people configure something, search their dotfiles on github. Use corresponding file path and language where appropriate.
- if you found a good reference or documentation for the task at hand, add a comment in the code referring to that documentation for future quick retreival
- If code should be moved to another file, always do it with shell commands to preserve the content verbatim and avoid copy paste errors
- If any command is missing to to the job or investigate, you can access any command via an ad-hoc nix-shell
- always add comments to document why things are the way they are. The comments should only refer to the current code, not to past code.
- don't hardcode paths. whenever possible, use xdg dirs.
- build incrementally during refactors, to catch errors early
- if a task is not straightforward, think about which refactor would make the task easy. Then do this refactoring first and commit it before attempting the task.
- once the user confirms a specific change is working, commit *that* change immediately (stage only the relevant hunks). Don't bundle it with later work or wait for more confirmations.
- never run `nrs`, `nixos-rebuild switch`, or any other system-activating rebuild yourself — the user always runs those manually. `nixos-rebuild build` (no activation) is fine for verification.
- files written at runtime (not by nix) must carry a header comment naming the writer and the source template, e.g. `AUTOGENERATED at runtime by noctalia from home/noctalia/templates/<file>. Edits are overwritten on the next theme change.` JSON files and other formats without comment support are exempt.

configuration entrypoints:
- flake.nix # top-level NixOS flake
- hosts/<hostname>/default.nix # host NixOS configuration
- hosts/<hostname>/home.nix # host Home Manager configuration

# Process-improvement intake
whenever the user makes a remark about *how to work* — a new rule, a refinement, an anti-pattern to avoid, a clarification of an existing convention — update AGENTS.md in the same turn. Don't acknowledge the rule only in chat; the chat is ephemeral, AGENTS.md is durable. Commit immediately, no batching. If the remark contradicts an existing rule, replace the old text rather than appending; AGENTS.md must speak with one voice. If you're unsure whether a remark is a process tweak or a one-off ask, default to writing it down — over-recording is cheap, under-recording is silent regression.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ccf33ec3 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files
- don't push/pull dolt

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Update issue status** - Close finished work, update in-progress items

<!-- END BEADS INTEGRATION -->
