{ config, pkgs, lib, ... }:

let
  # how to use unstable packages: https://gist.github.com/LnL7/e645b9075933417e7fd8f93207787581
  # Import unstable channel.
  # sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs-unstable
  # sudo nix-channel --update nixpkgs-unstable
  # nixpkgsUnstableSrc = import <nixpkgs-unstable> {};
  # nixpkgsUnstableSrc = builtins.fetchTarball {
  #   # nixpkgs-unstable as of 2019/05/30.
  #   url = "https://github.com/NixOS/nixpkgs-channels/archive/nixos-unstable.tar.gz";
  #   # sha256 = "0ffa84mp1fgmnqx2vn43q9pypm3ip9y67dkhigsj598d8k1chzzw";
  # };

  # nixpkgsUnstable = import nixpkgsUnstableSrc {
  # config = config.nixpkgs.config;
  # };

in {
  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "18.03"; # Did you read the comment?

  imports = [
    <nixos-hardware/lenovo/thinkpad/x1/6th-gen>

    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # VSCode with live share
    # (fetchTarball "https://github.com/msteen/nixos-vsliveshare/tarball/master")

  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Howto: Installation of NixOS with encrypted root
  # https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134
  boot.initrd.luks.devices = {
    root = {
      device = "/dev/disk/by-uuid/81409765-5560-4b29-8f5c-235f27b58f85";
      preLVM = true;
      allowDiscards = true;
    };
  };

  # boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelPackages = pkgs.linuxPackages_4_19;
  boot.kernelParams = [
    # "thermal.crt=85" # critical
    # "thermal.act=80" # set all critical temperatures, to throttle cpu speed 
    # "acpi_backlight=vendor"
    # "acpi.ec_no_wakeup=1"
    # "psmouse.synaptics_intertouch=1" # https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_5)#Bug:_Trackpoint.2FTrackpad_not_working
  ];
  boot.kernel.sysctl = {
    "kernel.sysrq" = 1; # enable REISUB
    "vm.swappiness" = 1;
    "fs.inotify.max_user_watches" = "4096000";
  };
  zramSwap.enable = true;
  boot.tmpOnTmpfs = true;

  # boot.extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];

  console.font = "Lat2-Terminus16";
  console.keyMap = "neo";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = { LC_TIME = "de_DE.UTF-8"; };
  };

  networking = {
    hostName = "gurke";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager.enable = true;
    # networkmanager.dns = "none";

    nameservers =
      [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
  };

  # networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh
  networking.firewall.allowedTCPPorts = [ 12345 5000 ]; # devserver
  networking.firewall.allowedUDPPorts = [ 8123 ]; # Stream Audio from VirtualBox

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  # time.timeZone = "Atlantic/Azores";
  # time.timeZone = "Europe/Lisbon";
  time.timeZone = "Europe/Berlin";
  # time.timeZone = "America/Mexico_City";
  # time.timeZone = "America/Guatemala";
  # time.timeZone = "America/Guadeloupe";
  # time.timeZone = "Chile/Continental";

  hardware = {
    # pulseaudio = {
    #   enable = true;
    #   package = pkgs.pulseaudioFull; # bluetooth support
    # };

    # for 32bit steam games
    opengl.driSupport32Bit = true;
    opengl.extraPackages32 = with pkgs.pkgsi686Linux; [ libva ];
    # pulseaudio.support32Bit = false;

    sane.enable = true;
    bluetooth.enable = true;

    cpu.intel.updateMicrocode = true;
  };

  powerManagement = {
    enable = true;
    #   # powertop.enable = true;
  };

  nixpkgs.config = {
    packageOverrides = pkgs: {
      unstable = import <nixos-unstable> { config = config.nixpkgs.config; };
    };

    allowUnfree = true;
    chromium = {
      # enablePepperFlash = true;
      # enablePepperPDF = true;
      enableWideVine = true;
    };
    polybar = pkgs.polybar.override {
      i3Support = true;
    };
    oraclejdk.accept_license = true;
  };

  environment = {
    systemPackages = with pkgs; [
      # system tools
      man
      pciutils
      usbutils
      hdparm
      gparted
      ntfs3g
      ntfsprogs
      testdisk
      exfat
      lm_sensors
      linuxPackages.cpupower
      xorg.xkill
      psmisc
      wirelesstools
      xorg.xbacklight
      acpi
      samba
      cifs-utils
      mtpfs
      jmtpfs
      file

      # defaults
      lsof
      wget
      curl
      htop
      atop
      git
      git-fire
      moreutils
      netcat
      nmap
      calc
      tree
      inotify-tools
      unzip
      pavucontrol
      light
      mimeo
      xsel
      xclip
      xdotool

      # tools
      ncdu
      pv
      pkgs.unstable.fzf
      ripgrep
      tig
      tmate
      scrot
      nix-zsh-completions
      haskellPackages.yeganesh
      termite
      alacritty
      mosh
      playerctl
      pamixer
      direnv
      jq
      yq-go

      # desktop
      gnome.gnome-themes-extra
      nordic # gtk theme
      qogir-theme # gtk theme
      qogir-icon-theme
      gnome3.zenity
      nitrogen
      slock
      dzen2
      dmenu
      networkmanager_dmenu
      networkmanagerapplet
      polybarFull
      xcwd
      libnotify
      shared-mime-info # file-type associations?
      dconf # needed for meld / networkmanager(?)
      gnome3.nautilus
      gnome3.gvfs
      gnome3.file-roller
      gnome3.gnome-keyring
      gnome3.seahorse
      libsecret
      # gnome3.gnome_keyring gnome3.seahorse libsecret
      paper-icon-theme
      vanilla-dmz
      xsettingsd

      # applications
      keepassxc
      firefox
      mate.atril
      inkscape
      gimp
      # sane-frontends
      mpv
      vlc
      imv
      kvirc
      # wine winetricks mono
      # libreoffice-fresh hunspell hunspellDicts.en-us languagetool mythes
      libsForQt5.qtstyleplugins
      libsForQt5.qt5ct

      # development
      # neovim
      msgpack-tools # for neovim
      # scala
      # sbt
      # maven
      # visualvm
      # gnumake
      # meld
      # docker
      # docker-compose
      # jdk17
      # python2
      python3
      python3Packages.isodate
      # rust.rustc rust.cargo
      # nim
      # texlive.combined.scheme-full
      # biber

    ];
  };
  documentation.enable = true;

  nix.gc.automatic = true;
  nix.gc.dates = "weekly";
  nix.gc.options = "--delete-older-than 7d";
  nix.daemonIOSchedPriority = 7;
  # nix.daemonCPUSchedPolicy = "idle";
  system.autoUpgrade.enable = true;

  # nixdirenv requires this to stop nix from garbage collecting its stuff
  nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
  '';

  programs = {
    zsh = {
      enable = true;
      interactiveShellInit = ''
        # color output of common commands
        source "${pkgs.grc}/etc/grc.zsh"
      '';
    };
    java.enable = true; # otherwise, JAVA_HOME is not set
  };

  programs.command-not-found.enable = true;
  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };
  programs.ssh.startAgent = true;
  programs.adb.enable = true;
  programs.dconf.enable = true;
  programs.light.enable = true;

  programs.xss-lock = {
    enable = true;
    lockerCommand = "-- ${pkgs.i3lock}/bin/i3lock -c 292D3E";
  };

  programs.file-roller.enable = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true; # so that gtk works properly
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty # Alacritty is the default terminal in the config
      dmenu # Dmenu is the default in the config but i recommend wofi since its wayland native
    ];
  };

  fonts = {
    enableDefaultFonts = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      corefonts # Arial, Verdana, ...
      vistafonts # Consolas, ...
      google-fonts # Droid Sans, Roboto, ...
      ubuntu_font_family
      powerline-fonts
    ];
    fontconfig = {
      includeUserConf = false;
      defaultFonts.monospace = [ "Ubuntu Mono - Bront" "Noto Color Emoji" ];
    };
    fontDir.enable = true;
  };

  location = {
    # provider = "geoclue2";

    # Mexico City
    # latitude = 19.433;
    # longitude = -99.133;
    # Lisbon
    # latitude = 38.72;
    # longitude = -9.15;
    # Aachen
    latitude = 50.77;
    longitude = 6.08;
    # Montreal
    # latitude = "45.50";
    # longitude = "-73.56";
    # Guadeloupe
    # latitude = 16.2411;
    # longitude = -61.5331;
  };

  security = {
    wrappers = {
        # pmount.source = "${pkgs.pmount}/bin/pmount";
        # pumount.source = "${pkgs.pmount}/bin/pumount";
      #   slock.source = "${pkgs.slock}/bin/slock";
      #   fusermount.source = "${pkgs.fuse}/bin/fusermount";

      iotop = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${pkgs.iotop}/bin/iotop";
      };
    };
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  virtualisation.virtualbox = {
    host.enable = true;
    host.enableExtensionPack = true;
  };
  virtualisation.docker.enable = true;

  users.extraUsers.felix = {
    isNormalUser = true;
    extraGroups =
      [ "wheel" "networkmanager" "vboxusers" "docker" "adbusers" "video" "disk" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ ];
  };

  users.extraUsers.tiphanie = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "vboxusers" "docker" "adbusers" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };

  environment.etc = {
    "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
      bluez_monitor.properties = {
        ["bluez5.enable-sbc-xq"] = true,
        ["bluez5.enable-msbc"] = true,
        ["bluez5.enable-hw-volume"] = true,
        ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
      }
    '';
  };

  services = {
    fstrim.enable = true;
    lorri.enable = true; # faster nix-shell replacement
    # locate.enable = true;

    upower = {
      enable = true;
      percentageLow = 20;
      percentageCritical = 15;
    };

    gvfs.enable = true;
    gnome = {
      gnome-keyring.enable = true;
      sushi.enable = true; # quick previewer for nautilus
    };
    udisks2.enable = true;

    geoclue2.enable = true; # location service
    blueman.enable = true;

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
      # Fix Intel CPU Throttling on Linux
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

    logind = {
      extraConfig = ''
        RuntimeDirectorySize=5G
      '';
    };

    # # https://github.com/NixOS/nixpkgs/issues/41189#issuecomment-491757154
    # vsliveshare = {
    #   enable = true;
    #   extensionsDir = "$HOME/.vscode/extensions";
    #   nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/61cc1f0dc07c2f786e0acfd07444548486f4153b";
    # };

    journald = {
      extraConfig = ''
        Storage=persist
        Compress=yes
        SystemMaxUse=128M
        RuntimeMaxUse=8M
      '';
    };

    openssh = {
      enable = false;
      passwordAuthentication = false;
      forwardX11 = true;
    };

    avahi = {
      enable = true;
      nssmdns = true;
      publish.enable = true;
      publish.addresses = true;
    };

    xserver = {
      enable = true;
      videoDrivers = [ "modesetting" ];
      # useGlamor = true; # Glamor module for 2D acceleration
      dpi = 210;
      layout = "de,de";
      xkbVariant = "neo,basic";
      xkbOptions = "grp:menu_toggle";

      libinput = {
        enable = true;
        touchpad = {
          disableWhileTyping = true;
          tapping = false;
          scrollMethod = "twofinger";
          accelSpeed = "0.9";
          naturalScrolling = true;
        };
      };

      displayManager = {
        autoLogin = {
          enable = true;
          user = "felix";
        };
        defaultSession = "none+i3";
        lightdm = { enable = true; };
        # gdm = { enable = true; };
        # lock on suspend
        sessionCommands = ''
          ${pkgs.xss-lock}/bin/xss-lock -- ${pkgs.i3lock}/bin/i3lock -c 292D3E &
        '';
      };
      desktopManager.xterm.enable = false;
      windowManager.xmonad = {
        enable = false;
        enableContribAndExtras = true;
      };
      windowManager.herbstluftwm.enable = true;
      # windowManager.herbstluftwm.package = pkgs.unstable.herbstluftwm;
      desktopManager.plasma5.enable = false;
      desktopManager.gnome.enable = false;
      windowManager.i3.enable = true;
    };

    # picom.enable = true;

    # Redshift adjusts the color temperature of your screen according to your surroundings. This may help your eyes hurt less if you are working in front of the screen at night.
    redshift.enable = true;

    # hide mouse after some seconds of no movement
    unclutter-xfixes.enable = true;

    acpid.enable = true;

    # cache browser profiles in ram
    # psd.enable = true;

    syncthing = {
      enable = true;
      user = "felix";
      dataDir = "/home/felix/.config/syncthing";
      openDefaultPorts = true;
      package = pkgs.unstable.syncthing;
    };

    # keybase = { enable = true; };
    # kbfs = {
    #   enable = true;
    #   mountPoint = "/keybase"; # mountpoint important for keybase-gui
    # };

    ## btsync = {
    ##   enable = true;
    ##   enableWebUI = true;
    ##   package = pkgs.bittorrentSync20;
    ## };

    ##clamav = {
    ##  daemon.enable   = true;
    ##  daemon.extraConfig = ''
    ##    TCPAddr   127.0.0.1
    ##    TCPSocket 3310
    ##  '';
    ##  updater.enable  = true;
    ##};

    ## ipfs = {
    ##   enable = true;
    ## };

    #printing = {
    #  enable = true;
    #  drivers = [ pkgs.gutenprint pkgs.hplip pkgs.epson-escpr ];
    #};
  };

  # workaround to from https://discourse.nixos.org/t/systemd-user-units-and-no-such-path/8399
  # systemd.user.extraConfig = ''
  #   DefaultEnvironment="PATH=/run/current-system/sw/bin"
  # '';

  # systemd.user = {
  #   services.megamount = {
  #     description = "Mount mega cloud storage";
  #     after = [ "network-online.target" ];
  #     wants = [ "network-online.target" ];
  #     wantedBy = [ "multi-user.target" ];
  #     serviceConfig = {
  #       ExecStartPre = "/run/current-system/sw/bin/mkdir -p /home/felix/mega";
  #       ExecStart =
  #         "/usr/bin/env PATH=$PATH:/run/wrappers/bin ${pkgs.rclone}/bin/rclone mount mega: /home/felix/mega --vfs-cache-mode full --no-modtime";
  #       Restart = "always";
  #       RestartSec = "10";
  #     };
  #   };
  # };

  # systemd.services.delayedHibernation = {
  #   description = "Delayed hibernation trigger";
  #   documentation = [ "https://wiki.archlinux.org/index.php/Power_management#Delayed_hibernation_service_file" ];
  #   conflicts = ["hibernate.target" "hybrid-sleep.target"];
  #   before = ["sleep.target"];
  #   # stopWhenUnneeded = true; # TODO
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = "yes";
  #     Environment = [ "WAKEALARM=/sys/class/rtc/rtc0/wakealarm" "SLEEPLENGTH=+2hour" ];
  #     ExecStart = "-/usr/bin/sh -c 'echo -n \"alarm set for \"; date +%%s -d$SLEEPLENGTH | tee $WAKEALARM'";
  #     ExecStop = ''
  #       -/usr/bin/sh -c '\
  #         alarm=$(cat $WAKEALARM); \
  #         now=$(date +%%s); \
  #         if [ -z "$alarm" ] || [ "$now" -ge "$alarm" ]; then \
  #            echo "hibernate triggered"; \
  #            systemctl hibernate; \
  #         else \
  #            echo "normal wakeup"; \
  #         fi; \
  #         echo 0 > $WAKEALARM; \
  #       '
  #     '';
  #   };

  #   wantedBy = [ "sleep.target" ];
  # };

  # systemd.services.delayedHibernation.enable = true;

  # systemd.user = {
  # https://vdirsyncer.pimutils.org/en/stable/tutorials/systemd-timer.html
  # services.vdirsyncer = {
  #   description = "Synchronize calendars and contacts";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.vdirsyncer}/bin/vdirsyncer sync";
  #   };
  # };
  # timers.vdirsyncer = {
  #   description = "Synchronize vdirs";

  #   timerConfig = {
  #     OnBootSec = "5m";
  #     OnUnitActiveSec = "60m";
  #     AccuracySec = "5m";
  #   };
  #   wantedBy = [ "timers.target" ];
  # };

  # services.tmate = {
  #   description = "tmate reverse tunnel";
  #   serviceConfig = {
  #     Type = "oneshot";
  #   };
  #   path = [pkgs.bash pkgs.tmate pkgs.hostname];
  #   script = ''
  #     TOKENPATH=/media/external/tmate
  #     [[ -n "$TOKENPATH" ]] || (echo "no token path given"; exit 1)
  #     HOST=$(hostname)

  #     TOKENFILE="$TOKENPATH/connect-$HOST"
  #     SOCKET=/tmp/tmate.sock

  #     function ssh-command() {
  #         tmate -S $SOCKET display -p '#{tmate_ssh}'
  #     }
  #     function init() {
  #         echo "opening new session"
  #         tmate -S $SOCKET new-session -d
  #     }
  #     function wait-tmate-ready() {
  #         tmate -S /tmp/tmate.sock wait tmate-ready
  #     }

  #     function write-token-file() {
  #         mkdir -p $TOKENPATH
  #         ssh-command > $TOKENFILE
  #     }

  #     echo "writing ssh command to $TOKENFILE..."
  #     if ! write-token-file; then
  #         echo "failed."
  #         echo "opening new session"
  #         init
  #         echo "waiting until tmate is ready..."
  #         wait-tmate-ready
  #         write-token-file && echo "written to $TOKENFILE"
  #     else
  #         echo "successful."
  #     fi
  #   '';
  # };
  # timers.tmate = {
  #   description = "tmate reverse tunnel";

  #   timerConfig = {
  #     OnBootSec = "5m";
  #     OnUnitActiveSec = "60m";
  #     AccuracySec = "5m";
  #   };
  #   wantedBy = [ "timers.target" ];
  # };
  # };
}
