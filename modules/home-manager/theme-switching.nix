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

  home.packages = lib.optionals hasThemeVariants [
    (mkThemeSwitchScript "light")
    (mkThemeSwitchScript "dark")
  ];

  systemd.user.targets = lib.mkIf hasThemeVariants {
    "theme-light".Unit.Description = "Apply light theme hooks";
    "theme-dark".Unit.Description = "Apply dark theme hooks";
  };
}
