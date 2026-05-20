{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf (config.my.desktop == "noctalia-niri") {
  # https://docs.noctalia.dev/v4/getting-started/compositor-settings/niri/
  programs.niri.enable = true;
  # programs.niri sets services.gnome.gnome-keyring.enable = mkDefault true; we use
  # keepassxc as the Secret Service provider instead, so suppress the keyring daemon.
  services.gnome.gnome-keyring.enable = false;

  # Noctalia v4 authenticates the lockscreen against /etc/pam.d/login;
  # NixOS provides it by default, so no extra PAM wiring is required here.

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
    ];
    config.common.default = [
      "wlr"
      "gtk"
    ];
  };

  # greetd autologin: default_session with a `user` field bypasses PAM and runs
  # niri-session as that user on every boot. initial_session would only cover
  # the first login, and greetd refuses to start without default_session.command
  # set (https://man.sr.ht/~kennylevinsen/greetd/).
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.niri}/bin/niri-session";
      user = "felix";
    };
  };

  # Host-wide services.displayManager.autoLogin, lightdm and GDM are gated by
  # the other desktop modules' mkIf blocks and do not fire under noctalia-niri.
}
