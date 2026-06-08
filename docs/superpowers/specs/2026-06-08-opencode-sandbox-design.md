# Design Spec: Sandboxed Opencode Wrapper

## Context & Background
We have a local sandboxing utility called `nono` that is used to isolate AI agents from the rest of the host system. Currently, `claude` (Claude Code) is wrapped in the `nono` sandbox under a dedicated `claude` profile, with `nice` and `ionice` priorities.

We want to apply the same sandboxing security controls and resource limits to `opencode`, using the same `claude` profile under the hood.

## Requirements
1. **Sandbox Integration:** Wrap the `opencode` command in the `nono` sandbox using the `claude` profile.
2. **Permission Prompts:** Pass `--dangerously-skip-permissions` to the inner `opencode` command to skip interactive permission confirmations, since the `nono` sandbox provides the ultimate layer of system-level isolation and permission enforcement.
3. **Resource Priority:** Prepend `ionice -c 3` and `nice -n 19` to prevent the agent's subprocesses from starving interactive system/desktop processes.
4. **Escape Hatch:** Provide a `vanilla-opencode` executable that bypasses the sandbox to run directly on the host (with `nice`/`ionice` intact).
5. **No Shell Alias Regression:** Ensure the aliases (`opencode`, `oc`, `c`) defined in `shell-core.nix` continue to resolve and work correctly (as they execute `opencode` on the path).

## Architecture & Design
We will implement this by updating the package definition in `/home/felix/projects/dotfiles/modules/home-manager/profiles/packages-cli.nix`.

1. Remove the raw `opencode` package from the list of packages.
2. Define `opencode` and `vanilla-opencode` wrapper scripts via `pkgs.writeShellScriptBin`:

### `opencode` Wrapper:
```bash
exec /run/current-system/sw/bin/ionice -c 3 /run/current-system/sw/bin/nice -n 19 \
  /run/current-system/sw/bin/nono run --profile claude -- \
  /run/current-system/sw/bin/opencode --dangerously-skip-permissions "$@"
```
Wait, we should use `${pkgs.util-linux}/bin/ionice`, `${pkgs.coreutils}/bin/nice`, `${pkgs.nono}/bin/nono`, and `${pkgs.opencode}/bin/opencode` to reference store paths cleanly.

```nix
      # Wrap `opencode` in the nono sandbox using the same profile as claude.
      # `nice -n 19` + `ionice -c 3` keep it from starving interactive work.
      (pkgs.writeShellScriptBin "opencode" ''
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.nono}/bin/nono run --profile claude -- \
          ${pkgs.opencode}/bin/opencode --dangerously-skip-permissions "$@"
      '')

      # Escape hatch: stock opencode on the host, without the sandbox.
      (pkgs.writeShellScriptBin "vanilla-opencode" ''
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.opencode}/bin/opencode "$@"
      '')
```

## Verification Plan
1. **Nix Config Compilation:** Run `nixos-rebuild build --flake .` (or equivalent check) to verify syntax correctness and lack of compile errors.
2. **Behavioral Test:** Switch current system specialization using `./nrs` (manual run by user) or check wrapped execution.
