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
in

{
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
    # "acpi_backlight=vendor"
    # "acpi.ec_no_wakeup=1"
    # "psmouse.synaptics_intertouch=1" # https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_5)#Bug:_Trackpoint.2FTrackpad_not_working
  ];
  boot.kernel.sysctl = {
      "kernel.sysrq" = 1;
      "vm.swappiness" = 0;
      "fs.inotify.max_user_watches" = "4096000";
  };
  # zramSwap.enable = true;
  # boot.cleanTmpDir = true;
  boot.tmpOnTmpfs = true;

  boot.extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];

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

    nameservers = [ "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
  };

  # networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh
  networking.firewall.allowedTCPPorts = [ 12345 5000 ]; # devserver

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  time.timeZone = "Atlantic/Azores";
  # time.timeZone = "Europe/Lisbon";
  # time.timeZone = "Europe/Berlin";
  # time.timeZone = "America/Guadeloupe";
  # time.timeZone = "Chile/Continental";

  hardware = {
    pulseaudio = {
      enable = true;
      package = pkgs.pulseaudioFull; # bluetooth support
    };

    # for 32bit steam games
    opengl.driSupport32Bit = true;
    opengl.extraPackages32 = with pkgs.pkgsi686Linux; [ libva ];
    pulseaudio.support32Bit = true;

    sane.enable = true;
    bluetooth.enable = true;

    cpu.intel.updateMicrocode = true;
  };


  powerManagement = {
    enable = true;
  #   cpuFreqGovernor = "powersave"; # not working: https://github.com/NixOS/nixpkgs/issues/64368
  #   # powertop.enable = true;
  };

  nixpkgs.config = {
    packageOverrides = pkgs: {
      unstable = import <nixos-unstable> {
        config = config.nixpkgs.config;
      };
    };

    allowUnfree = true;
    chromium = {
      # enablePepperFlash = true;
      # enablePepperPDF = true;
      enableWideVine = true;
    };
    oraclejdk.accept_license = true;
  };

  environment = {
    systemPackages = with pkgs; [
      # system tools
      man
      pciutils usbutils hdparm gparted ntfs3g ntfsprogs testdisk exfat lm_sensors linuxPackages.cpupower
      xorg.xkill psmisc wirelesstools pmount xorg.xbacklight
      acpi samba cifs-utils

      # defaults
      wget curl htop atop git git-fire netcat nmap calc tree inotify-tools unzip
      pavucontrol light mimeo xsel xclip xdotool

      # tools
      ncdu pv pkgs.unstable.fzf ripgrep tig ctags tmate scrot nix-zsh-completions haskellPackages.yeganesh termite mosh playerctl pamixer
      


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
      mate.atril inkscape gimp
      # sane-frontends
      mpv vlc imv
      # wine winetricks mono
      # libreoffice-fresh hunspell hunspellDicts.en-us languagetool mythes

      # development
      # neovim
      msgpack-tools # for neovim
      scala sbt maven visualvm
      gnumake
      meld
      docker docker_compose
      jdk11
      python2
      python3
      # rust.rustc rust.cargo
      # nim
      texlive.combined.scheme-full
      # biber

    ];

    shellAliases = {
      l = "ls -l";
      t = "${pkgs.tree}/bin/tree -C"; # -C is for color=always
      # vn = "${neovim}/bin/nvim /etc/nixos/configuration.nix";
      rcp = "${pkgs.rsync}/bin/rsync --archive --partial --info=progress2 --human-readable";
      sys = "sudo systemctl";
      sysu = "systemctl --user";
    };

    sessionVariables = {
      SUDO_EDITOR = "nvim";
      EDITOR = "nvim";
      BROWSER = "chromium";
    };
  };
  documentation.enable = true;

  nix.gc.automatic = true;
  nix.gc.dates = "monthly";
  nix.gc.options = "--delete-older-than 7d";
  nix.daemonIONiceLevel = 7;
  nix.daemonNiceLevel = 19;
  system.autoUpgrade.enable = true;

  programs = {
    zsh = {
      enable = true;
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

  programs.xss-lock = {
    enable = true;
    lockerCommand = "-- ${pkgs.i3lock}/bin/i3lock -c 292D3E";
  };

  fonts = {
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      corefonts # Arial, Verdana, ...
      vistafonts # Consolas, ...
      google-fonts # Droid Sans, Roboto, ...
      ubuntu_font_family
      dejavu_fonts
      symbola # unicode symbols
      powerline-fonts
    ];
    fontconfig = {
      includeUserConf = false;
      defaultFonts.monospace = [ "Roboto Mono" "DejaVu Sans Mono" ];
    };
  };


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

  virtualisation.virtualbox = {
    host.enable = true;
    host.enableExtensionPack = true;
  };
  virtualisation.docker.enable = true;

  users.extraUsers.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "vboxusers" "docker" "adbusers"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
    ];
  };
  };

  services = {
    fstrim.enable = true;
    locate.enable = true;

    upower.enable  = true;
    gvfs.enable  = true;
    gnome3.gnome-keyring.enable = true;
    udisks2.enable = true;

    geoclue2.enable = true; # location service
    blueman.enable = true;

    tlp = {
      enable = true;
      extraConfig = ''
        tlp_DEFAULT_MODE=BAT
        CPU_SCALING_GOVERNOR_ON_BAT=powersave
        CPU_SCALING_GOVERNOR_ON_AC=powersave
      '';
    };

    # logind = {
    #   lidSwitch = "ignore";
    #   lidSwitchExternalPower = "ignore";
    #   lidSwitchDocked = "ignore";
    # };

    # # usbmuxd.enable = true; # ios debugging

    # # https://github.com/NixOS/nixpkgs/issues/41189#issuecomment-491757154
  # vsliveshare = {
  #   enable = true;
  #   extensionsDir = "$HOME/.vscode/extensions";
  #   nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/61cc1f0dc07c2f786e0acfd07444548486f4153b";
  # };


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
      videoDrivers = ["modesetting"];
      useGlamor = true; # Glamor module for 2D acceleration
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
        autoLogin = {
          enable = true;
          user = "felix";
        };
        defaultSession = "none+herbstluftwm";
        lightdm = {
          enable = true;
        };
        # lock on suspend
        sessionCommands = ''
          ${pkgs.xss-lock}/bin/xss-lock -- ${pkgs.i3lock}/bin/i3lock -c 292D3E &
        '';
      };
      desktopManager.xterm.enable = false;
      windowManager.xmonad = {
        enable = true;
        enableContribAndExtras = true;
      };
      windowManager.herbstluftwm.enable = true;
      windowManager.herbstluftwm.package = pkgs.unstable.herbstluftwm;
      desktopManager.plasma5.enable = false;
      windowManager.i3.enable = false;
    };

    # picom.enable = true;

    # Redshift adjusts the color temperature of your screen according to your surroundings. This may help your eyes hurt less if you are working in front of the screen at night.
    redshift.enable = true;

    ## hide mouse after some seconds of no movement
    unclutter-xfixes.enable = true;

    acpid.enable = true;
    udev.extraRules = ''
      SUBSYSTEM=="power_supply", ATTR{status}=="Discharging", ATTR{capacity}=="[0-8]", RUN+="${pkgs.systemd}/bin/systemctl hibernate"
    '';

    # cache browser profiles in ram
    psd.enable = true;

    syncthing = {
      enable = true;
      user = "felix";
      dataDir = "/home/felix/.config/syncthing";
      openDefaultPorts = true;
      package = pkgs.unstable.syncthing;
    };

    keybase = {
      enable = false;
    };
    kbfs = {
      enable = false;
      mountPoint = "/keybase"; # mountpoint important for keybase-gui
    };

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
