# Universal host commands. Currently provides the nixos `switch` (relocated
# nrs); generic pull/upgrade and the home/droid backends arrive in a later
# task. hostType selects which backend is installed; hostLabel and
# dotfilesDir are consumed by those later backends.
{
  lib,
  pkgs,
  config,
  hostType,
  hostLabel ? null,
  ...
}: let
  dotfilesDir = config.my.dotfilesDir;
  desktopRegistry = import ../desktop-registry.nix;

  # Spec name → desktop, derived from the same registry that defines the
  # specialisations. Keeping this in Nix means nrs can never disagree with
  # what's actually in /nix/var/nix/profiles/system/specialisation/.
  specToDesktop =
    (lib.listToAttrs (
      lib.concatMap (
        d:
          map (t: {
            name = "${d}-${t}";
            value = d;
          })
          desktopRegistry.themes
      )
      desktopRegistry.themedDesktops
    ))
    // (lib.listToAttrs (
      map (d: {
        name = d;
        value = d;
      })
      desktopRegistry.unthemedDesktops
    ));

  # Emit `  spec) printf '%s' desktop ;;` lines for a bash case statement.
  specCaseArms = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      spec: d: "      ${lib.escapeShellArg spec}) printf '%s' ${lib.escapeShellArg d} ;;"
    )
    specToDesktop
  );
  # Minimal tmux config used only for nrs's tmux server. Skips the user's
  # ~/.tmux.conf (which may use outdated option names) and hides the status
  # bar so the rebuild looks like a plain terminal command.
  nrsTmuxConfig = pkgs.writeText "nrs.tmux.conf" ''
    set -g status off
    set -g default-terminal "tmux-256color"
    set -g mouse on
  '';

  # Inner script that runs inside the tmux PTY (see nrsScript). Receives the
  # rebuild command as positional args; reads the desktop strings from env
  # (kept out of argv so quoting stays simple).
  nrsInner = pkgs.writeShellScript "nrs-inner" ''
    set -uo pipefail

    target_desktop="''${NRS_TARGET_DESKTOP:-}"
    current_desktop="''${NRS_CURRENT_DESKTOP:-}"

    # Prompt for the sudo password upfront, in this PTY where the
    # activation-phase sudo will later run (tty_tickets makes the timestamp
    # tty-bound, so priming the outer terminal would not carry over). This
    # moves the prompt to the start instead of mid-rebuild. A background loop
    # refreshes the timestamp every 50s so it never hits sudo's 5-minute
    # timeout during a long build; it is killed as soon as the rebuild returns.
    sudo -v
    ( while true; do sleep 50; sudo -n -v 2>/dev/null; done ) &
    keepalive_pid=$!

    "$@"
    rc=$?

    # Record the rebuild rc so the outer script (and pull/upgrade) can read it;
    # the outer process used to `exec tmux attach` and thus returned no code.
    printf '%s' "$rc" > "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc"

    kill "$keepalive_pid" 2>/dev/null

    if (( rc != 0 )); then
      echo
      echo "[nrs] rebuild failed (exit $rc) — press any key to close"
      read -rsn1
      exit $rc
    fi

    # Only relogin when the *desktop* (not just the theme variant) actually
    # changed: the old user@.service holds the previous compositor's env
    # (WAYLAND_DISPLAY, XDG_SESSION_TYPE, …) which leaks into user services
    # like xss-lock and breaks them. "unknown" is the desktop_of fallback for
    # unrecognised specs — never relogin in that case.
    if [[ -n "$target_desktop" \
       && "$target_desktop" != "unknown" \
       && "$target_desktop" != "$current_desktop" ]]; then
      echo "[nrs] desktop changed ($current_desktop -> $target_desktop); terminating user session for clean relogin"
      exec sudo ${pkgs.systemd}/bin/loginctl terminate-user "$USER"
    fi

    echo
    echo "[nrs] done — press any key to close"
    read -rsn1
  '';

  nixosSwitch = pkgs.writeShellScriptBin "switch" ''
    set -euo pipefail

    # nrs [<specialisation>]
    #   No arg: re-apply the currently active specialisation (or parent
    #   toplevel if none).
    #   With arg: switch to <specialisation> — works across desktops/DMs.
    #
    # The rebuild runs inside a tmux session whose server lives under
    # user@.service (via `systemd-run --user --scope`). This keeps the
    # rebuild alive when the compositor and login session scope are killed
    # during activation (e.g. greetd restarting because default_session
    # changed). The tmux PTY also gives the inner sudo a real terminal: the
    # inner script primes sudo upfront (sudo -v) and keeps the timestamp warm,
    # so the password is asked at the start, not mid-rebuild — per-tty sudo
    # timestamp caching stays as-is, no askpass, no global timestamps.
    #
    # Reattach a running rebuild with `tmux attach -t nrs`.
    # Cancel with Ctrl-C inside tmux, or `tmux kill-session -t nrs`.
    #
    # Requires logind `KillUserProcesses=no` (NixOS default) so user@.service
    # — and the tmux server inside it — survives login-session termination.

    # Map a specialisation name to its desktop. Arms generated from
    # ../desktop-registry.nix so this never drifts from the actual specs.
    desktop_of() {
      case "$1" in
${specCaseArms}
        "") printf "" ;;
        *) printf 'unknown' ;;
      esac
    }

    if [[ $# -ge 1 ]]; then
      specialisation="$1"
    elif [[ -r /run/nixos/current-specialisation ]]; then
      specialisation="$(${pkgs.coreutils}/bin/head -n1 /run/nixos/current-specialisation)"
    else
      specialisation=""
    fi

    current=""
    if [[ -r /run/nixos/current-specialisation ]]; then
      current="$(${pkgs.coreutils}/bin/head -n1 /run/nixos/current-specialisation)"
    fi

    target_desktop="$(desktop_of "$specialisation")"
    current_desktop="$(desktop_of "$current")"

    rebuild=( nixos-rebuild switch --sudo )
    if [[ -n "$specialisation" ]]; then
      rebuild+=( --specialisation "$specialisation" )
    fi

    SESSION="nrs"
    # `-L nrs` uses a dedicated server socket so the user's regular tmux
    # state is untouched. `-f` skips ~/.tmux.conf (which may use outdated
    # option names) and loads the minimal nrs config that hides the
    # status bar.
    TMUX=( ${pkgs.tmux}/bin/tmux -L nrs -f ${nrsTmuxConfig} )

    # Idempotent: if a rebuild is already running, just reattach. Communicate
    # clearly when a new spec argument is dropped on the floor.
    if "''${TMUX[@]}" has-session -t "$SESSION" 2>/dev/null; then
      if [[ $# -ge 1 ]]; then
        echo "[nrs] rebuild already running (tmux session '$SESSION'); ignoring argument '$1' and attaching to the running session." >&2
        echo "[nrs] cancel the running rebuild first (Ctrl-C in tmux, then exit) if you want to switch to '$1'." >&2
        sleep 2
      fi
      exec "''${TMUX[@]}" attach -t "$SESSION"
    fi

    # `systemd-run --user --scope` places the tmux server's cgroup under
    # user@.service rather than the current login-session scope, so the
    # server survives a session-scope termination mid-rebuild.
    rm -f "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc"
    ${pkgs.systemd}/bin/systemd-run --user --scope --quiet \
      "''${TMUX[@]}" new-session -d -s "$SESSION" \
        -e "NRS_TARGET_DESKTOP=$target_desktop" \
        -e "NRS_CURRENT_DESKTOP=$current_desktop" \
        "${nrsInner} ''${rebuild[*]@Q}"

    # Reattach to watch the rebuild, then exit with the rc that nrsInner
    # recorded — so callers (and pull/upgrade) see the real rebuild result.
    "''${TMUX[@]}" attach -t "$SESSION"
    exit "$(${pkgs.coreutils}/bin/cat "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc" 2>/dev/null || echo 0)"
  '';

  # switch: apply the current checkout. Only this varies by host category.
  switchScript =
    if hostType == "nixos"
    then nixosSwitch
    else if hostType == "home"
    then
      pkgs.writeShellScriptBin "switch" ''
        set -euo pipefail
        exec home-manager switch -b backup --flake ${dotfilesDir}#${hostLabel} "$@"
      ''
    else if hostType == "droid"
    then
      pkgs.writeShellScriptBin "switch" ''
        set -euo pipefail
        exec nix-on-droid switch --flake ${dotfilesDir}#${hostLabel} "$@"
      ''
    else throw "host-commands: unknown hostType '${hostType}'";

  # pull: sync my latest committed config, then apply. Category-agnostic.
  # --rebase --autostash so a dirty working tree (mid-iteration) doesn't abort.
  pullScript = pkgs.writeShellScriptBin "pull" ''
    set -euo pipefail
    git -C ${dotfilesDir} pull --rebase --autostash
    exec ${switchScript}/bin/switch "$@"
  '';

  # upgrade: bump upstream inputs, then apply, then commit the lock — but only
  # after a successful switch (set -e gates it), proving the bump builds.
  # nice -n 18: the full rebuild is long; niceness is inherited through
  # sudo / systemd-run --scope down to the actual build. flake.lock is shared
  # by all hosts, so one host upgrades and the rest `pull` the committed lock.
  # Push stays manual.
  upgradeScript = pkgs.writeShellScriptBin "upgrade" ''
    set -euo pipefail
    cd ${dotfilesDir}
    nix flake update
    nice -n 18 ${switchScript}/bin/switch
    git -C ${dotfilesDir} diff --quiet flake.lock \
      || git -C ${dotfilesDir} commit flake.lock -m "flake.lock: update inputs"
  '';
in {
  home.packages = [
    switchScript
    pullScript
    upgradeScript
  ];
}
