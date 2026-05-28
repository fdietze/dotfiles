{
  config,
  lib,
  flake-inputs,
  pkgs,
  ...
}: let
  breezyOverlay = final: prev: let
    system = prev.stdenv.hostPlatform.system;
  in {
    # breezy-desktop's upstream overlay still uses the deprecated prev.system
    # alias. Keep the package wiring local until upstream switches too.
    inherit
      (flake-inputs.breezy-desktop.packages.${system})
      breezy-desktop-ui
      breezy-gnome
      breezy-kwin
      breezy-vulkan
      xr-linux-driver
      ;
  };
in
  lib.mkIf (config.my.desktop == "gnome") {
    nixpkgs.overlays = [breezyOverlay];

    environment.sessionVariables.XDG_BIN_HOME = "/run/current-system/sw/bin";
    environment.systemPackages = [
      pkgs.xr-linux-driver
      pkgs.breezy-desktop-ui
      pkgs.breezy-gnome
    ];

    # Breezy's upstream NixOS module still uses deprecated pkgs.system, so keep
    # this small local wiring until upstream switches to stdenv.hostPlatform.
    boot.kernelModules = ["uinput"];
    services.udev.packages = [pkgs.xr-linux-driver];
    systemd.tmpfiles.rules = [
      "r! /dev/shm/xr_driver_state"
    ];
    systemd.user.services.xr-driver = {
      description = "XR user-space driver";
      after = ["network.target"];
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.xr-linux-driver}/bin/xrDriver";
        Environment = "LD_LIBRARY_PATH=${pkgs.xr-linux-driver}/lib";
        Restart = "always";
      };
    };

    programs.ssh.startAgent = false; # conflicts with gnome
    stylix.targets.gnome.enable = true;

    # Install the driver
    services.desktopManager.gnome.enable = true;
    services.gnome.gnome-keyring.enable = lib.mkForce false; # we use keepassxc instead

    services.displayManager = {
      defaultSession = "gnome";
      gdm = {
        enable = true;
      };
    };

    services.xserver.displayManager.lightdm.enable = false;
  }
