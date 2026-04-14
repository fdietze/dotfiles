{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf (config.my.desktop == "herbstluftwm") {
  services.displayManager = {
    defaultSession = "none+herbstluftwm";
    gdm.enable = false;
  };

  services.xserver = {
    displayManager.lightdm = {
      enable = true;
      # background = "/home/felix/frottage/wallpaper.jpg";
      greeters.gtk.enable = true;
    };
    windowManager.herbstluftwm.enable = true;
  };

  xdg.portal = {
    enable = true;
    configPackages = [pkgs.xdg-desktop-portal-gtk];
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdgOpenUsePortal = false; # make xdg-open use the portal to open programs
    config.common.default = "gtk";
  };

  programs.xss-lock = {
    enable = true;
    lockerCommand = ''
      ${pkgs.i3lock-color}/bin/i3lock-color \
            --ignore-empty-password \
            --image=/home/felix/frottage/wallpaper.jpg \
            --ring-width=10 --line-uses-inside \
            --ring-color=222436FF   --ringver-color=C3E88DFF   --ringwrong-color=C53B53FF \
            --inside-color=000000AA --insidever-color=000000AA --insidewrong-color=000000AA \
            --keyhl-color=C3E88DFF --bshl-color=82AAFFFF \
            --verif-color=00000000 --wrong-color=00000000
    '';
  };
  security.pam.services.i3lock.enable = true;

  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor = "powersave";
        turbo = "never";
      };
      charger = {
        governor = "powersave";
        turbo = "auto";
      };
    };
  };

  #   services.tlp = {
  #     enable = true;
  #     settings = {
  #       tlp_DEFAULT_MODE = "BAT";
  #       CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
  # # CPU_SCALING_GOVERNOR_ON_AC = "powersave";
  #       DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth";
  #
  # #Optional helps save long term battery health
  #       START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
  #         STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
  #     };
  #   };
}
