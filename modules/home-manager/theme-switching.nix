{
  lib,
  pkgs,
  desktop,
  theme,
  ...
}: let
  desktopRegistry = import ../desktop-registry.nix;
  hasThemeVariants = builtins.elem desktop desktopRegistry.themedDesktops;
  switchToConfigurationPath = mode: "/nix/var/nix/profiles/system/specialisation/${desktop}-${mode}/bin/switch-to-configuration";

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

    "$@"
    rc=$?

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

  nrsScript = pkgs.writeShellScriptBin "nrs" ''
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
    # changed). The tmux PTY also gives the activation-phase inner sudo a
    # real terminal so it prompts for the password normally — per-tty
    # sudo timestamp caching stays as-is, no askpass, no global timestamps.
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
    ${pkgs.systemd}/bin/systemd-run --user --scope --quiet \
      "''${TMUX[@]}" new-session -d -s "$SESSION" \
        -e "NRS_TARGET_DESKTOP=$target_desktop" \
        -e "NRS_CURRENT_DESKTOP=$current_desktop" \
        "${nrsInner} ''${rebuild[*]@Q}"

    exec "''${TMUX[@]}" attach -t "$SESSION"
  '';
  mkThemeSwitchScript = mode:
    pkgs.writeShellScriptBin "theme-${mode}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      sudo ${switchToConfigurationPath mode} switch
      ${pkgs.systemd}/bin/systemctl --user daemon-reload
      ${pkgs.systemd}/bin/systemctl --user stop theme-light.target theme-dark.target || true
      exec ${pkgs.systemd}/bin/systemctl --user start theme-${mode}.target
    '';
in {
  home.file.".theme" = lib.mkIf hasThemeVariants {
    text = theme;
  };

  home.packages =
    [
      nrsScript
    ]
    ++ lib.optionals hasThemeVariants [
      (mkThemeSwitchScript "light")
      (mkThemeSwitchScript "dark")
    ];

  systemd.user.targets = lib.mkIf hasThemeVariants {
    "theme-light".Unit.Description = "Apply light theme hooks";
    "theme-dark".Unit.Description = "Apply dark theme hooks";
  };
}
