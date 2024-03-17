{
  pkgs,
  flake-inputs,
  ...
}: {
  nixpkgs.config.permittedInsecurePackages = [
    "freeimage-unstable-2021-11-01" # https://github.com/NixOS/nixpkgs/issues/290949
    "nix-2.16.2" # https://github.com/nix-community/nixd/issues/357
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
    settings.trusted-users = ["root" "felix"];

    # useful for using traditional nix-shell, but with nixpkgs pointing to the system flake
    # registry entries
    registry = {
      nixpkgs.flake = flake-inputs.nixpkgs;
    };
    # nix path to correspond to my flakes
    nixPath = [
      "nixpkgs=${flake-inputs.nixpkgs}"
    ];
  };

  boot = {
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

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
      "vm.swappiness" = 2; # start swapping before the system is out of memory
    };

    # zramSwap.enable = true; # ram compression

    tmp = {
      useTmpfs = false;
      cleanOnBoot = true;
    };

    # extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];
  };

  console.keyMap = "neo"; # https://neo-layout.org/

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {LC_TIME = "de_DE.UTF-8";};
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
    networkmanager.enable = true;
    # networkmanager.dns = "none";

    # cloudflare dns servers: https://developers.cloudflare.com/1.1.1.1/ip-addresses/
    nameservers = ["1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001"];

    # firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh
    # firewall.allowedTCPPorts = [12345 18080 8080 4566]; # devserver
    # firewall.allowedUDPPorts = [ 8123 ]; # Stream Audio from VirtualBox
  };

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  # time.timeZone = "Europe/Berlin";
  services.automatic-timezoned.enable = true;

  location = {
    provider = "geoclue2";
    # Lisbon
    # latitude = 38.72;
    # longitude = -9.15;
  };
  services.geoclue2.enable = true;

  powerManagement = {
    enable = true;
    # powertop.enable = true;
  };

  hardware.opengl = {
    enable = true;
    driSupport32Bit = true; # for 32bit steam games
    extraPackages = with pkgs; [
      # https://nixos.wiki/wiki/Accelerated_Video_Playback
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      vaapiVdpau
      libvdpau-va-gl
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [libva];
  };
  environment.sessionVariables = {LIBVA_DRIVER_NAME = "iHD";}; # Force intel-media-driver
  # hardware.sane.enable = true; # scanners

  hardware.bluetooth = {
    # https://nixos.wiki/wiki/Bluetooth
    enable = true;
    powerOnBoot = false;
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
  virtualisation.docker.enable = true;

  nixpkgs.config = {
    allowUnfree = true;
    oraclejdk.accept_license = true;
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
    ];
  };

  programs.zsh.enable = true;
  # programs.java.enable = true; # otherwise, JAVA_HOME is not set
  programs.adb.enable = true; # android debugging
  programs.dconf.enable = true; # useful for: blueman-applet, ...
  programs.light.enable = true; # adjust screen brightness
  # programs.file-roller.enable = true;
  programs.iotop.enable = true;

  services.xserver = {
    enable = true;
    # dpi = 210;
    videoDrivers = ["modesetting"];
    # waiting for https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/1006, released in xserver 21.1.6
    # then, hopefully, picom can be disabled
    # deviceSection = ''
    #   Option "TearFree" "true"
    # '';
    xkb.layout = "de,de";
    xkb.variant = "neo,basic";
    xkb.options = "grp:menu_toggle";

    libinput = {
      enable = true;
      touchpad = {
        disableWhileTyping = true;
        tapping = false;
        scrollMethod = "twofinger";
        accelSpeed = "0.7";
        naturalScrolling = true; # seriously, try it for a day
      };
    };

    displayManager = {
      lightdm.enable = true;
      defaultSession = "none+herbstluftwm";
      autoLogin = {
        enable = true;
        user = "felix";
      };
      # lock on suspend
      sessionCommands = ''
        ${pkgs.xss-lock}/bin/xss-lock -- ${pkgs.i3lock}/bin/i3lock -c 292D3E &
      '';
    };
    desktopManager.xterm.enable = false;
    windowManager = {
      herbstluftwm.enable = true;
      session = [
        {
          name = "herbstluftwm";
          # workaround for https://github.com/NixOS/nixpkgs/pull/237364
          # fix: https://github.com/NixOS/nixpkgs/pull/271198
          start = ''
            ${pkgs.herbstluftwm}/bin/herbstluftwm --locked 2>&1 > /tmp/herbstlog
          '';
        }
      ];
    };
  };

  fonts = {
    enableDefaultPackages = true;
    enableGhostscriptFonts = true;
    packages = with pkgs; [
      corefonts # Arial, Verdana, ...
      vistafonts # Consolas, ...
      google-fonts # Droid Sans, Roboto, ...
      ubuntu_font_family
      nerdfonts # common fonts with icons and glyphs: https://www.nerdfonts.com/
      commit-mono # https://commitmono.com/
    ];
    fontconfig = {
      includeUserConf = false; # no user fonts.conf
      defaultFonts.monospace = ["Commit Mono" "Noto Color Emoji"];
    };
    fontDir.enable = true;
  };

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

    #printing = {
    #  enable = true;
    #  drivers = [ pkgs.gutenprint pkgs.hplip pkgs.epson-escpr ];
    #};

    acpid.enable = true;

    upower = {
      enable = true;
      percentageLow = 20;
      percentageCritical = 10;
    };

    tlp = {
      enable = true;
      settings = {
        tlp_DEFAULT_MODE = "BAT";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth";
      };
    };

    throttled = {
      # Workaround for Intel CPU Throttling on Linux
      # https://github.com/erpalma/throttled
      # default config: https://github.com/erpalma/throttled/blob/master/etc/throttled.conf
      enable = true;
      extraConfig = ''
        [GENERAL]
        # Enable or disable the script execution
        Enabled: True
        # SYSFS path for checking if the system is running on AC power
        Sysfs_Power_Path: /sys/class/power_supply/AC*/online
        # Auto reload config on changes
        Autoreload: True

        ## Settings to apply while connected to Battery power
        [BATTERY]
        # Update the registers every this many seconds
        Update_Rate_s: 30
        # Max package power for time window #1
        PL1_Tdp_W: 29
        # Time window #1 duration
        PL1_Duration_s: 28
        # Max package power for time window #2
        PL2_Tdp_W: 44
        # Time window #2 duration
        PL2_Duration_S: 0.002
        # Max allowed temperature before throttling
        Trip_Temp_C: 70
        # Set cTDP to normal=0, down=1 or up=2 (EXPERIMENTAL)
        cTDP: 0
        # Disable BDPROCHOT (EXPERIMENTAL)
        Disable_BDPROCHOT: False

        ## Settings to apply while connected to AC power
        [AC]
        # Update the registers every this many seconds
        Update_Rate_s: 5
        # Max package power for time window #1
        PL1_Tdp_W: 44
        # Time window #1 duration
        PL1_Duration_s: 28
        # Max package power for time window #2
        PL2_Tdp_W: 44
        # Time window #2 duration
        PL2_Duration_S: 0.002
        # Max allowed temperature before throttling
        Trip_Temp_C: 90
        # Set HWP energy performance hints to 'performance' on high load (EXPERIMENTAL)
        # Uncomment only if you really want to use it
        # HWP_Mode: False
        # Set cTDP to normal=0, down=1 or up=2 (EXPERIMENTAL)
        cTDP: 0
        # Disable BDPROCHOT (EXPERIMENTAL)
        Disable_BDPROCHOT: False

        # All voltage values are expressed in mV and *MUST* be negative (i.e. undervolt)!
        [UNDERVOLT.BATTERY]
        # CPU core voltage offset (mV)
        CORE: 0
        # Integrated GPU voltage offset (mV)
        GPU: 0
        # CPU cache voltage offset (mV)
        CACHE: 0
        # System Agent voltage offset (mV)
        UNCORE: 0
        # Analog I/O voltage offset (mV)
        ANALOGIO: 0

        # All voltage values are expressed in mV and *MUST* be negative (i.e. undervolt)!
        [UNDERVOLT.AC]
        # CPU core voltage offset (mV)
        CORE: 0
        # Integrated GPU voltage offset (mV)
        GPU: 0
        # CPU cache voltage offset (mV)
        CACHE: 0
        # System Agent voltage offset (mV)
        UNCORE: 0
        # Analog I/O voltage offset (mV)
        ANALOGIO: 0

        # [ICCMAX.AC]
        # # CPU core max current (A)
        # CORE:
        # # Integrated GPU max current (A)
        # GPU:
        # # CPU cache max current (A)
        # CACHE:

        # [ICCMAX.BATTERY]
        # # CPU core max current (A)
        # CORE:
        # # Integrated GPU max current (A)
        # GPU:
        # # CPU cache max current (A)
        # CACHE:
      '';
    };
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

  users = {
    defaultUserShell = pkgs.bash;
    extraUsers.felix = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "video" "disk" "docker" "vboxusers" "adbusers"];
      shell = pkgs.zsh;
    };
  };

  system.stateVersion = "18.03";
}
