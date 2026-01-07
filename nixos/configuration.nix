{
  lib,
  pkgs,
  flake-inputs,
  ...
}:
{
  nixpkgs.config.permittedInsecurePackages = [
    # add some here whenever needed
  ];

  system.autoUpgrade.enable = true;
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings.auto-optimise-store = true;
    daemonIOSchedPriority = 7;
    daemonCPUSchedPolicy = "idle";

    # nixdirenv requires this to stop nix from garbage collecting its stuff
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';

    settings.experimental-features = "nix-command flakes"; # enable flakes
    settings.trusted-users = [
      "root"
      "felix"
    ];

    # useful for using traditional nix-shell, but with nixpkgs pointing to the system flake
    # registry entries
    registry = {
      nixpkgs.flake = flake-inputs.nixpkgs;
    };
    # nix path to correspond to my flakes
    nixPath = [ "nixpkgs=${flake-inputs.nixpkgs}" ];
  };

  home-manager.backupFileExtension = "hm-bak";

  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    kernelParams = [
      "kvm.enable_virt_at_load=0" # fix virtualbox
      "usbcore.autosuspend=-1" # Disable USB autosuspend globally to prevent issues with powertop
      "zswap.enabled=1" # enables zswap
      # "zswap.compressor=zstd" # compression algorithm
      "zswap.max_pool_percent=5" # maximum percentage of RAM that zswap is allowed to use
    ]; # https://github.com/NixOS/nixpkgs/issues/363887
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [
      "ntfs"
      "exfat"
    ];

    initrd.kernelModules = [
      "zstd"
      "zsmalloc"
    ];

    # Howto: Installation of NixOS with encrypted root
    # https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134
    initrd.luks.devices = {
      root = {
        device = "/dev/disk/by-uuid/81409765-5560-4b29-8f5c-235f27b58f85";
        preLVM = true;
        allowDiscards = true;
      };
    };

    kernel.sysctl = {
      "kernel.sysrq" = 1; # enable REISUB: https://blog.kember.net/posts/2008-04-reisub-the-gentle-linux-restart/
      "vm.swappiness" = 1;
    };

    tmp = {
      useTmpfs = false;
      cleanOnBoot = true;
    };

    # extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];
  };

  # 3. Enable EarlyOOM (The Safety Net)
  # Prevents complete system lockups by killing the heaviest process
  # (usually a browser tab) when you have < 5% RAM left.
  services.earlyoom = {
    enable = true;
    enableNotifications = true; # You get a popup if something is killed
    freeMemThreshold = 5; # Kill if less than 5% RAM free
    freeSwapThreshold = 5; # Kill if less than 5% Swap free
  };

  console.keyMap = "neo"; # https://neo-layout.org/

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "de_DE.UTF-8";
    };
  };

  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  networking = {
    hostName = "gurke";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager = {
      enable = true;
      plugins = with pkgs; [
        networkmanager-openvpn
      ];
    };
    networkmanager.dns = "systemd-resolved";

    # cloudflare dns servers: https://developers.cloudflare.com/1.1.1.1/ip-addresses/
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];

    # firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh
    firewall.allowedTCPPorts = [
      12345
      5173
      8080 # miniserve
      8081 # expo
      3000 # common rust backend port
      9099 # firebase auth
      9000 # firebase auth
    ]; # devserver
    # firewall.allowedUDPPorts = [ 8123 ]; # Stream Audio from VirtualBox
    firewall.allowedUDPPorts = [
      5353 # mDNS (Multicast DNS) for printer discovery
      427 # SLP (Service Location Protocol)
    ];

    extraHosts = ''
      10.101.8.14 onboard.eurostar.com
    '';
  };
  services.resolved = {
    # cache dns requests locally
    enable = true;
    # dnssec = "true";
    # domains = [ "~." ];
    # fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    # dnsovertls = "opportunistic";
  };

  services.tailscale.enable = true;

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  # time.timeZone = "Europe/Berlin";
  # time.timeZone = "Europe/Sofia";
  # time.timeZone = "Europe/Lisbon";
  # time.timeZone = "Indian/Mauritius";
  services.automatic-timezoned.enable = true; # relies on geoclue to work: https://github.com/NixOS/nixpkgs/issues/321121

  location.provider = "geoclue2";
  services.geoclue2 = {
    enable = true;
    # geoProviderUrl =
    #   "https://api.beacondb.net/v1/geolocate"; # https://github.com/NixOS/nixpkgs/pull/391845
    # enableStatic = true;
    # staticLatitude = 41.8333;
    # staticLongitude = 23.5;
    # staticAltitude = 900.0;
    # staticAccuracy = 1000.0;
  };

  users.users.geoclue.extraGroups = [ "networkmanager" ]; # ?

  powerManagement = {
    enable = true;
    powertop.enable = true;
  };
  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 10;
    criticalPowerAction = "Hibernate";
  };

  services.thermald.enable = true;

  services.auto-cpufreq = {
    enable = true; # conflict with gnome
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

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # for 32bit steam games
    extraPackages = with pkgs; [
      # https://nixos.wiki/wiki/Accelerated_Video_Playback
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      libva-vdpau-driver
      libvdpau-va-gl
      vpl-gpu-rt
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [ libva ];
  };
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  }; # Force intel-media-driver
  hardware.sane = {
    enable = true; # scanners
    extraBackends = [ pkgs.hplipWithPlugin ]; # HP scanner support
  };

  hardware.bluetooth = {
    # https://nixos.wiki/wiki/Bluetooth
    enable = true;
    # powerOnBoot = false;
    settings.General.Experimental = true; # bluetooth battery percentage
  };
  services.blueman.enable = true;

  security.rtkit.enable = true; # allows certain user-level processes to run with real-time priorities, good for media editing and playing
  services.pipewire = {
    # alternative to pulseaudio with better bluetooth support
    # https://nixos.wiki/wiki/PipeWire
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/51-bluez-config.lua" ''
        bluez_monitor.properties = {
        	["bluez5.enable-sbc-xq"] = true,
        	["bluez5.enable-msbc"] = true,
        	["bluez5.enable-hw-volume"] = true,
        	["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
        }
      '')
    ];
  };

  virtualisation.virtualbox.host.enable = true;
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };
  programs.virt-manager.enable = true;
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = false;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
    oraclejdk.accept_license = true;
    segger-jlink.acceptLicense = true;
    # chromium = {
    #   enablePepperFlash = true;
    #   enablePepperPDF = true;
    #   enableWideVine = true;
    # };
  };

  environment = {
    systemPackages = with pkgs; [
      # only the bare minimum here
      git
      neovim
      hplipWithPlugin # HP printer utilities (hp-setup, hp-toolbox, etc.)

      # xdg-utils # Provides xdg-screensaver and other desktop integration tools
      # Remove lockers managed by home-manager or unused
      # i3lock       # Dependency for betterlockscreen
      # betterlockscreen # The new locker

      # workaround for rust-analyzer with openblas not finding CC
      # gcc
      # gfortran

    ];
  };

  services.ollama.enable = false; # local ai models
  services.qdrant.enable = false; # vector search engine, used for kilo code indexing

  # Remove PAM configuration for i3lock
  # security.pam.services.i3lock = { ... };

  # Remove PAM configuration for betterlockscreen
  # security.pam.services.betterlockscreen = { ... };

  programs.nix-ld.enable = true; # run non-nixos binaries on nixos
  programs.nix-ld.libraries = [ ];
  programs.appimage.enable = true;
  programs.zsh.enable = true;
  programs.fish.enable = false;
  programs.java = {
    enable = true; # provide JAVA_HOME
    package = pkgs.jdk17; # needed for flutter builds in android studio
  };
  programs.dconf.enable = true; # useful for: blueman-applet, ...
  programs.light.enable = true; # adjust screen brightness
  programs.iotop.enable = true;
  programs.nix-index-database.comma.enable = true;

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

  services.libinput = {
    enable = true;
    touchpad = {
      disableWhileTyping = true;
      tapping = false;
      scrollMethod = "twofinger";
      accelSpeed = "0.7";
      naturalScrolling = true; # seriously, try it for a day
    };
  };

  xdg.portal = {
    enable = true;
    configPackages = [ pkgs.xdg-desktop-portal-gtk ];
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdgOpenUsePortal = false; # make xdg-open use the portal to open programs
    config.common.default = "gtk";
  };

  stylix = {
    # https://stylix.danth.me/index.html
    enable = true;
    autoEnable = true;
    polarity = "dark";
    base16Scheme = {
      # tokyo-night-moon
      base00 = "222436"; # bg
      base01 = "2f334d"; # bg_highlight
      base02 = "2d3f76"; # bg_visual
      base03 = "636da6"; # comment
      base04 = "828bb8"; # fg_dark
      base05 = "c8d3f5"; # fg
      base06 = "c8d3f5"; # fg (reused)
      base07 = "c8d3f5"; # terminal.white_bright
      base08 = "ff757f"; # red
      base09 = "ff966c"; # orange
      base0A = "ffc777"; # yellow
      base0B = "c3e88d"; # green
      base0C = "86e1fc"; # cyan
      base0D = "82aaff"; # blue
      base0E = "c099ff"; # magenta
      base0F = "4fd6be"; # teal
    };
    # targets = {
    #   console.enable = true;
    #   gtk.enable = true;
    # };
  };
  home-manager.extraSpecialArgs = {
    theme = "dark";
  };
  specialisation.light.configuration = {
    stylix = {
      polarity = lib.mkForce "light";
      # base16Scheme = lib.mkForce "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
      base16Scheme = {
        # sabuni
        base00 = "ffffff"; # bg (from primary.background)
        base01 = "eeeeee"; # bg_highlight (Generated light gray)
        base02 = "999999"; # bg_visual (from bright.black)
        base03 = "666666"; # comment (from primary.dim_foreground)
        base04 = "333333"; # fg_dark (Generated dark gray)
        base05 = "000000"; # fg (from primary.foreground)
        base06 = "000000"; # fg (reused primary.foreground)
        base07 = "000000"; # terminal.white_bright (reused primary.foreground)
        base08 = "ff0088"; # red (from normal.red)
        base09 = "ff7e00"; # orange (from normal.yellow)
        base0A = "ffa34a"; # yellow (from bright.yellow)
        base0B = "19af00"; # green (from normal.green)
        base0C = "00cab2"; # cyan (from normal.cyan)
        base0D = "0a94ff"; # blue (from normal.blue)
        base0E = "3b00cb"; # magenta (from normal.magenta)
        base0F = "65cabe"; # teal (from bright.cyan)
      };
    };
    home-manager.extraSpecialArgs = {
      theme = "light";
    };
  };

  # Start the driver at boot
  systemd.services.fprintd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "simple";
  };

  # Install the driver
  services.fprintd.enable = true;

  services.xserver = {
    enable = true;
    dpi = 210;
    videoDrivers = [ "modesetting" ];

    xkb.layout = "de,de";
    xkb.variant = "neo,basic";
    xkb.options = "altwin:swap_lalt_lwin";

    displayManager = {
      lightdm = {
        enable = true;
        # background = "/home/felix/frottage/wallpaper.jpg";
        greeters.gtk = {
          enable = true;
        };
      };
      # gdm.enable = true;
    };
    desktopManager.xterm.enable = false;
    windowManager.herbstluftwm.enable = true;
    # desktopManager.gnome.enable = true;
  };

  services.displayManager = {
    defaultSession = "none+herbstluftwm";
    autoLogin = {
      enable = true;
      user = "felix";
    };
  };

  fonts = {
    enableDefaultPackages = true;
    enableGhostscriptFonts = true;
    packages = with pkgs; [
      corefonts # Arial, Verdana, ...
      vista-fonts # Consolas, ...
      noto-fonts-color-emoji
      # google-fonts # Droid Sans, Roboto, ...
      roboto
      # ubuntu_font_family
      nerd-fonts._0xproto
      # (nerdfonts.override {
      #   # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/data/fonts/nerdfonts/shas.nix
      #   fonts = [
      #     "0xProto"
      #     "DejaVuSansMono"
      #     "FiraCode"
      #     "DroidSansMono"
      #     "CascadiaCode"
      #   ];
      # }) # common fonts with icons and glyphs: https://www.nerdfonts.com/
      # commit-mono # https://commitmono.com/
    ];
    fontconfig = {
      includeUserConf = false; # no user fonts.conf
      defaultFonts.monospace = [
        # https://www.nerdfonts.com/font-downloads
        "0xProto Nerd Font Mono"
        "Noto Color Emoji"
      ];
    };
    fontDir.enable = true;
  };

  programs.ssh.startAgent = true;

  services = {
    cron.enable = true;
    openssh = {
      enable = false;
      settings.PasswordAuthentication = false;
      settings.X11Forwarding = true;
    };

    fstrim.enable = true; # periodic SSD TRIM of mounted partitions in background

    avahi = {
      # network discovery
      enable = true;
      nssmdns4 = true;
      publish.enable = true;
      publish.addresses = true;
      openFirewall = true; # needed for printer discovery
    };

    gvfs.enable = true; # gnome virtual file system
    udisks2.enable = true; # allows to mount removable devices in graphical file managers

    journald = {
      extraConfig = ''
        Storage=persistent
        Compress=yes
        SystemMaxUse=128M
        RuntimeMaxUse=8M
      '';
    };

    # syncthing = {
    #   enable = true;
    #   user = "felix";
    #   dataDir = "/home/felix/.config/syncthing";
    #   openDefaultPorts = true;
    # };

    printing = {
      enable = true;
      drivers = [ pkgs.hplip ];
    };

    acpid.enable = true;

  };

  # systemd.services.frottage = {
  #   description = "Download wallpaper using frottage script";
  #   wantedBy = ["multi-user.target"];
  #   # after = [ "network-online.target" ];
  #   requires = ["network-online.target"];
  #   wants = ["network-online.target"];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.writeScriptBin "frottage" ''
  #       #!${pkgs.bash}/bin/bash
  #       set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail

  #       # light or dark
  #       THEME=$(cat "$HOME/.theme" || echo dark)

  #       case $THEME in
  #       light)
  #       	TARGET=desktop-light
  #       	;;
  #       dark)
  #       	TARGET=desktop
  #       	;;
  #       esac

  #       cd ~/downloads
  #       ${pkgs.curl}/bin/curl -s "https://fdietze.github.io/frottage/wallpapers/$TARGET.json" | ${pkgs.jq}/bin/jq -r '.prompt' >"frottage-prompt"
  #       ${pkgs.wget}/bin/wget --timestamping --retry-on-host-error --tries=60 --waitretry=60 "https://fdietze.github.io/frottage/wallpapers/wallpaper-$TARGET-latest.jpg"
  #       DISPLAY=:0 ${pkgs.feh}/bin/feh --bg-fill "wallpaper-$TARGET-latest.jpg"
  #     ''}/bin/frottage";
  #     # Ensure that the script is executable
  #     PermissionsStartOnly = true;
  #     User = "felix";
  #     Group = "users";
  #   };
  # };

  # Define the systemd timer
  # systemd.timers.frottage = {
  #   description = "Timer for frottage service";
  #   wantedBy = ["timers.target"];
  #   # after = [ "network-online.target" ];
  #   timerConfig = {
  #     OnCalendar = "*-*-* 01,04,07,10,13,16,19:00:00";
  #     Persistent = true; # If the timer is missed, run it as soon as possible
  #   };
  # };
  #
  # ensure the group exists
  users.groups.plugdev = { };
  users.groups.usb = { };

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="cafe", ATTR{idProduct}=="4000", MODE="0660", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8771", MODE="0660", GROUP="plugdev"
  '';

  users = {
    defaultUserShell = pkgs.bash;
    extraUsers.felix = {
      isNormalUser = true;
      extraGroups = [
        "plugdev"
        "usb"
        "wheel"
        "networkmanager"
        "video"
        "disk"
        "docker"
        "vboxusers"
        "adbusers"
        "kvm"
        "scanner" # for HP scanner support
        "lp" # for printer access
      ];
      shell = pkgs.zsh;
    };
  };

  system.stateVersion = "18.03";
}
