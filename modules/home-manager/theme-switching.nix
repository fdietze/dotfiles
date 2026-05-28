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
  nrsScript = pkgs.writeShellScriptBin "nrs" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # nrs [<specialisation>]
    #   No arg: re-apply the currently active specialisation (or parent
    #   toplevel if none).
    #   With arg: switch to <specialisation> — works across desktops/DMs.
    #
    # When the target spec uses a different greetd default_session, the
    # running compositor (and the terminal running this command) will be
    # killed mid-switch. Wrap the rebuild in a transient systemd unit so
    # activation survives session death.

    if [[ $# -ge 1 ]]; then
      specialisation="$1"
    elif [[ -r /run/nixos/current-specialisation ]]; then
      specialisation="$(${pkgs.coreutils}/bin/head -n1 /run/nixos/current-specialisation)"
    else
      specialisation=""
    fi

    cmd=( nixos-rebuild switch --use-remote-sudo )
    if [[ -n "$specialisation" ]]; then
      cmd+=( --specialisation "$specialisation" )
    fi

    # systemd-run as root puts the unit in system.slice (survives session
    # death), but --uid/--gid run the payload as the invoking user so the
    # flake's git fetch doesn't trip libgit2's ownership check. nixos-rebuild
    # then sudos internally (NOPASSWD via wheel) for the activation phase.
    exec sudo ${pkgs.systemd}/bin/systemd-run \
      --collect --pipe --wait --service-type=oneshot \
      --unit="nrs-$$" \
      --uid="$(${pkgs.coreutils}/bin/id -u)" \
      --gid="$(${pkgs.coreutils}/bin/id -g)" \
      --setenv=HOME="$HOME" \
      --setenv=PATH="$PATH" \
      -- "''${cmd[@]}"
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
