{config, ...}: {
  xdg.userDirs = {
    download = "${config.home.homeDirectory}/downloads";
    extraConfig = {
      XDG_SCREENSHOTS_DIR = "${config.home.homeDirectory}/screenshots";
    };
  };

  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = ["firefox.desktop"];
      "x-scheme-handler/https" = ["firefox.desktop"];
      "x-scheme-handler/about" = ["firefox.desktop"];
      "image/jpeg" = ["feh.desktop"];
      "image/png" = ["feh.desktop"];
      "application/pdf" = ["org.pwmt.zathura-pdf-mupdf.desktop"];
    };
  };

  xdg.autostart.enable = true; # Enable creation of XDG autostart entries.
}
