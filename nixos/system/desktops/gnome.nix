{
  config,
  lib,
  flake-inputs,
  ...
}:
lib.mkIf (config.my.desktop == "gnome") {
  nixpkgs.overlays = [flake-inputs.breezy-desktop.overlays.default];

  # Install the driver
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-keyring.enable = lib.mkForce false; # we use keepassxc instead

  services.displayManager = {
    defaultSession = "gnome";
    gdm = {
      enable = true;
      wayland = true;
    };
  };

  services.xserver.displayManager.lightdm.enable = false;

  services.breezy-desktop = {
    enable = true;

    # Pick your desktop environment:
    gnome.enable = true; # GNOME Shell extension + UI
    # kwin.enable = true;  # KDE Plasma 6 KWin plugin + UI

    # Optional:
    # vulkan.enable = true; # Vulkan layer for XR gaming
  };
}
