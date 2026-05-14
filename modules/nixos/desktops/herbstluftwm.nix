{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf (config.my.desktop == "herbstluftwm") {
  stylix.targets.lightdm.enable = true;

  services.displayManager = {
    defaultSession = "none+herbstluftwm";
    gdm.enable = false;
  };

  services.xserver = {
    displayManager.lightdm = {
      enable = true;
      # background = "$HOME/.cache/frottage/current-wallpaper.jpg";
      greeters.gtk.enable = true;
    };
    windowManager.herbstluftwm.enable = true;
  };

  xdg.portal = {
    enable = true;
    configPackages = [ pkgs.xdg-desktop-portal-gtk ];
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdgOpenUsePortal = false; # make xdg-open use the portal to open programs
    config.common.default = "gtk";
  };

  programs.i3lock = {
    enable = true;
    package = pkgs.i3lock-color;
  };

  programs.xss-lock = {
    enable = true;
    # i3lock(1) recommends this xss-lock pattern so suspend waits until the screen is locked.
    extraOptions = [ "--transfer-sleep-lock" ];
    # xss-lock does not run the locker through a shell; systemd expands %h for this user service.
    lockerCommand = ''
      ${config.programs.i3lock.package}/bin/i3lock-color \
            --nofork \
            --ignore-empty-password \
            --image=%h/.cache/frottage/current-wallpaper.jpg \
            --ring-width=10 --line-uses-inside \
            --ring-color=222436FF   --ringver-color=C3E88DFF   --ringwrong-color=C53B53FF \
            --inside-color=000000AA --insidever-color=000000AA --insidewrong-color=000000AA \
            --keyhl-color=C3E88DFF --bshl-color=82AAFFFF \
            --verif-color=00000000 --wrong-color=00000000
    '';
  };

}
