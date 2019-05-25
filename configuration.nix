{ config, pkgs, lib, ... }:

let
  # how to use unstable packages: https://gist.github.com/LnL7/e645b9075933417e7fd8f93207787581
  # Import unstable channel.
  # sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs-unstable
  # sudo nix-channel --update nixpkgs-unstable
  unstable = import <nixpkgs-unstable> {};
in

{
  imports =
  [ # Include the results of the hardware scan.
  ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Howto: Installation of NixOS with encrypted root
  # https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134
  boot.initrd.luks.devices = [
    {
      name = "root";
      device = "/dev/disk/by-uuid/81409765-5560-4b29-8f5c-235f27b58f85";
      preLVM = true;
      allowDiscards = true;
    }
  ];

  # boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    # "acpi_backlight=vendor"
    # "acpi.ec_no_wakeup=1"
    # "psmouse.synaptics_intertouch=1" # https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_5)#Bug:_Trackpoint.2FTrackpad_not_working
  ];
  boot.kernel.sysctl = {
      "kernel.sysrq" = 1;
      "vm.swappiness" = 0;
      "fs.inotify.max_user_watches" = "409600";
  };
  # zramSwap.enable = true;
  # boot.cleanTmpDir = true;
  boot.tmpOnTmpfs = true;

  i18n = {
    #consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "neo";
    defaultLocale = "en_US.UTF-8";
  };


  networking = {
    hostName = "gurke";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # connman.enable = true;
    networkmanager.enable = true;
  };

  # networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh
  networking.firewall.allowedTCPPorts = [ 12345 ]; # woost webpack devserver

  time.timeZone = "Europe/Berlin";

  hardware = {
    pulseaudio.enable = true;
    # pulseaudio.support32Bit = true; # This might be needed for Steam games
    # opengl.driSupport32Bit = true;
    sane.enable = true;

    cpu.intel.updateMicrocode = true;
  };


  powerManagement = {
    enable = true;
    # powertop.enable = true;
  };

  nixpkgs.config = {
    allowUnfree = true;
    chromium = {
      # enablePepperFlash = true;
      enablePepperPDF = true;
      enableWideVine = true;
    };
    oraclejdk.accept_license = true;
  };

  environment = {
    systemPackages = with pkgs; [
      # system tools
      pciutils usbutils hdparm gparted ntfs3g lm_sensors 
      xorg.xkill psmisc wirelesstools pmount
      acpi samba cifs-utils

      # defaults
      wget curl htop atop git netcat nmap calc tree inotify-tools unzip
      pavucontrol light mimeo xclip xdotool

      # tools
      ncdu pv fzf silver-searcher tig ctags tmate scrot nix-zsh-completions haskellPackages.yeganesh termite mosh playerctl pamixer


      # desktop
      gnome3.gnome_themes_standard nitrogen grc slock gksu 
      dzen2 dmenu networkmanager_dmenu networkmanagerapplet polybar
      xcwd
      libnotify dunst
      shared_mime_info # file-type associations?
      gnome3.dconf # needed for meld / networkmanager(?)
      gnome3.nautilus gnome3.gvfs mtpfs jmtpfs
      gnome3.file-roller
      gnome3.gnome_keyring gnome3.seahorse libsecret
      # gnome3.gnome_keyring gnome3.seahorse libsecret
      paper-icon-theme
      vanilla-dmz


      # applications
      keepassxc
      firefox
      virtualbox
      mate.atril inkscape gimp
      # sane-frontends
      mpv vlc imv
      # wine winetricks mono
      # libreoffice-fresh hunspell hunspellDicts.en-us languagetool mythes
      
      # development
      neovim
      msgpack-tools # for neovim
      scala sbt maven visualvm
      gnumake
      meld
      docker docker_compose
      jdk8
      python2
      python3
      # rust.rustc rust.cargo
      # nim
      texlive.combined.scheme-full
      # biber

    ];

    shellAliases = {
      l = "ls -l";
      t = "${pkgs.neovim}/bin/tree -C"; # -C is for color=always
      vn = "${pkgs.neovim}/bin/nvim /etc/nixos/configuration.nix";
      rcp = "${pkgs.rsync}/bin/rsync --archive --partial --info=progress2 --human-readable";
    };

    sessionVariables = {
      SUDO_EDITOR = "nvim";
      EDITOR = "nvim";
      BROWSER = "chromium";
    };

    # variables = {
    #   XCURSOR_THEME = "Vanilla-DMZ";
    # };
  };

  nix.gc.automatic = true;
  nix.gc.dates = "monthly";
  nix.gc.options = "--delete-older-than 7d";
  nix.daemonIONiceLevel = 7;
  nix.daemonNiceLevel = 19;
  system.autoUpgrade.enable = true;

  programs = {
    zsh = {
      enable = true;
      syntaxHighlighting.enable = true;
      autosuggestions.enable = true;
      interactiveShellInit = ''
        source "${pkgs.grc}/etc/grc.zsh"
        source "${pkgs.fzf}/share/fzf/completion.zsh"
        source "${pkgs.fzf}/share/fzf/key-bindings.zsh"
      '';
    };
  };

  programs.command-not-found.enable = true;
  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };
  programs.adb.enable = true;

  programs.xss-lock.enable = true;
  programs.xss-lock.lockerCommand = "i3lock";

  security = {
    wrappers = {
      pmount.source = "${pkgs.pmount}/bin/pmount";
      pumount.source = "${pkgs.pmount}/bin/pumount";
      eject.source = "${pkgs.eject}/bin/eject";
      light.source = "${pkgs.light}/bin/light";
      slock.source = "${pkgs.slock}/bin/slock";
    };
    sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };

  services = {
    fstrim.enable = true;
    locate.enable = true;

    upower.enable  = true;
    gnome3.gvfs.enable  = true;
    gnome3.gnome-keyring.enable = true;
    udisks2.enable = true;

    # usbmuxd.enable = true; # ios debugging

    journald = {
      extraConfig =
      ''
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
      videoDrivers = ["intel"]; # modesetting cannot arrange 4k monitors in a row yet. (max 8192x8192 virtual screen size)
      dpi = 210;
      enable = true;
      layout = "de,de";
      xkbVariant = "neo,basic";
      xkbOptions = "grp:menu_toggle";

      libinput = {
        enable = true;
        scrollMethod = "twofinger";
        disableWhileTyping = true;
        tapping = false;
        accelSpeed = "0.9";
      };

      displayManager = {
        lightdm = {
          enable = true;
          autoLogin = {
            enable = true;
            user = "felix";
          };
        };
      };
      desktopManager.xterm.enable = false;
      desktopManager.default      = "none";
      windowManager.default       = "xmonad";
      windowManager.xmonad = {
        enable = true;
        enableContribAndExtras = true;
      };
      windowManager.herbstluftwm.enable = false;
      desktopManager.plasma5.enable = false;
      windowManager.i3.enable = false;
    };

    # Redshift adjusts the color temperature of your screen according to your surroundings. This may help your eyes hurt less if you are working in front of the screen at night.
    redshift = {
      enable = true;
      latitude = "50.77";
      longitude = "6.08";
    };

    # hide mouse after some seconds of no movement
    unclutter-xfixes.enable = true;

    acpid.enable = true;
    udev.extraRules = ''
      SUBSYSTEM=="power_supply", ATTR{status}=="Discharging", ATTR{capacity}=="[0-7]", RUN+="${pkgs.systemd}/bin/systemctl hibernate"
    '';

    psd = {
      enable = true;
    };

    syncthing = {
      enable = true;
      user = "felix";
      dataDir = "/home/felix/.config/syncthing";
      openDefaultPorts = true;
      package = unstable.syncthing;
    };

    keybase = {
      enable = true;
    };
    kbfs = {
      enable = true;
      mountPoint = "/keybase"; # mountpoint important for keybase-gui
    };

    # btsync = {
    #   enable = true;
    #   enableWebUI = true;
    #   package = pkgs.bittorrentSync20;
    # };


    #clamav = {
    #  daemon.enable   = true;
    #  daemon.extraConfig = ''
    #    TCPAddr   127.0.0.1
    #    TCPSocket 3310
    #  '';
    #  updater.enable  = true;
    #};

    # ipfs = {
    #   enable = true;
    # };


    printing = {
      enable = true;
      drivers = [ pkgs.gutenprint pkgs.hplip pkgs.epson-escpr ];
    };
  };

  systemd.services.delayedHibernation = {
    description = "Delayed hibernation trigger";
    documentation = [ "https://wiki.archlinux.org/index.php/Power_management#Delayed_hibernation_service_file" ];
    conflicts = ["hibernate.target" "hybrid-sleep.target"];
    before = ["sleep.target"];
    # stopWhenUnneeded = true; # TODO
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      Environment = [ "WAKEALARM=/sys/class/rtc/rtc0/wakealarm" "SLEEPLENGTH=+2hour" ];
      ExecStart = "-/usr/bin/sh -c 'echo -n \"alarm set for \"; date +%%s -d$SLEEPLENGTH | tee $WAKEALARM'";
      ExecStop = ''
        -/usr/bin/sh -c '\
          alarm=$(cat $WAKEALARM); \
          now=$(date +%%s); \
          if [ -z "$alarm" ] || [ "$now" -ge "$alarm" ]; then \
             echo "hibernate triggered"; \
             systemctl hibernate; \
          else \
             echo "normal wakeup"; \
          fi; \
          echo 0 > $WAKEALARM; \
        '
      '';
    };

    wantedBy = [ "sleep.target" ];
  };

  systemd.services.delayedHibernation.enable = true;

  systemd.user = {
    # https://vdirsyncer.pimutils.org/en/stable/tutorials/systemd-timer.html
    services.vdirsyncer = {
      description = "Synchronize calendars and contacts";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.vdirsyncer}/bin/vdirsyncer sync";
      };
    };
    timers.vdirsyncer = {
      description = "Synchronize vdirs";

      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "15m";
        AccuracySec = "5m";
      };
      wantedBy = [ "timers.target" ];
    };
  };

  fonts = {
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      corefonts
      google-fonts
      ubuntu_font_family
      dejavu_fonts
      symbola # unicode symbols
    ];
    fontconfig = {
      includeUserConf = false;
      defaultFonts.monospace = [ "Roboto Mono" "DejaVu Sans Mono" ];
    };
  };

  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableExtensionPack = true;
  virtualisation.docker.enable = true;

  users.extraUsers.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "vboxusers" "docker" "adbusers"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
    ];
  };





  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "18.03"; # Did you read the comment?

}
