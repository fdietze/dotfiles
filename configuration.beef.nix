# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

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
      device = "/dev/disk/by-uuid/aa5f9930-f418-4c35-91c9-24c295e4efca";
      preLVM = true;
      allowDiscards = true;
    }
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  i18n = {
    #consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "neo";
    defaultLocale = "en_US.UTF-8";
  };


  networking = {
    hostName = "beef";
    networkmanager.enable = true;
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  };


  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  time.timeZone = "Europe/Berlin";

  nixpkgs.config = {
    allowUnfree = true;
    chromium = {
      # enablePepperFlash = true;
      enablePepperPDF = true;
      enableWideVine = false;
    };
  };

  environment = {
    systemPackages = with pkgs; [
      wget pv htop atop git netcat nmap xorg.xkill psmisc lm_sensors calc tree gparted gksu ntfs3g inotify-tools unzip
      ncdu fzf fasd silver-searcher tig ctags xclip tmate pmount scrot nix-zsh-completions haskellPackages.yeganesh
      termite numix-gtk-theme nitrogen unclutter-xfixes grc #cope
      dzen2 dmenu rofi conky lua lua51Packages.luafilesystem trayer polybar # panel
      # chromium firefox
      jdk scala sbt maven visualvm
      # gnumake cmake clang gcc autoconf automake
      meld
      nodejs yarn
      docker docker_compose
      # # rust.rustc rust.cargo
      # nim
      # texlive.combined.scheme-full
      # biber

      # boost
      # wine winetricks mono

      # libreoffice-fresh hunspell hunspellDicts.en-us languagetool mythes
      # samba cifs-utils

      neovim
      python2
      python27Packages.neovim # ensime?
      python27Packages.websocket_client # ensime?
      python27Packages.sexpdata # ensime?
      python3
      python35Packages.neovim

      # mosh

      mate.atril inkscape gimp
      spotify
      # sane-frontends
      mpv vlc playerctl pamixer imv

      # vulkan-loader

      shared_mime_info # file-type associations?

      gnome3.dconf # needed for meld
      gnome3.nautilus gnome3.gvfs mtpfs
      # gnome3.gnome_keyring gnome3.seahorse libsecret
    ];

    shellAliases = {
      l = "ls -l";
      t = "tree -C"; # -C is for color=always
      vn = "nvim /etc/nixos/configuration.nix";
    };

    variables = {
      SUDO_EDITOR = "nvim";
      EDITOR = "nvim";
      BROWSER = "firefox";
    };
  };

  nix.gc.automatic = true;
  nix.gc.dates = "01:15";
  nix.gc.options = "--delete-older-than 7d";
  system.autoUpgrade.enable = true;

  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.command-not-found.enable = true;
  users.defaultUserShell = "/run/current-system/sw/bin/zsh";
  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };


  security = {
    wrappers = {
      pmount.source = "${pkgs.pmount}/bin/pmount";
      pumount.source = "${pkgs.pmount}/bin/pumount";
      eject.source = "${pkgs.eject}/bin/eject";
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
    #gnome3.gnome-keyring.enable = true;
    udisks2.enable = true;

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
    };

    xserver = {
      enable = true;
      #  videoDrivers = [ "nvidia" ];
      layout = "de,de";
      xkbVariant = "neo,basic";
      xkbOptions = "grp:menu_toggle";
      # libinput.enable = true;
      synaptics.enable = true;
      synaptics.twoFingerScroll = true;
      displayManager.lightdm.enable = true;
      windowManager.herbstluftwm.enable = true;
      #  windowManager.i3.enable = true;
    };

    # compton.enable = true;
    redshift = {
      enable = true;
      latitude = "50.77";
      longitude = "6.08";
    };
    # unclutter-xfixes.enable = true; # not working?

    syncthing = {
      enable = true;
      user = "felix";
      dataDir = "/home/felix/.config/syncthing";
      useInotify = true;
      openDefaultPorts = true;
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

  fonts = {
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      corefonts
      dejavu_fonts
      # opensans-ttf
      symbola # many unicode symbols
      ubuntu_font_family
      inconsolata
      font-droid # needed for firefox
      siji # polybar icon font
    ];
    fontconfig = {
      includeUserConf = false;
      defaultFonts.monospace = [ "Inconsolata" "DejaVu Sans Mono" ];
    };
  };

  # virtualisation.virtualbox.host.enable = true;
  # nixpkgs.config.virtualbox.enableExtensionPack = true;
  virtualisation.docker.enable = true;

  users.extraUsers.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "vboxusers" "docker"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
    ];
  };





  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "17.09"; # Did you read the comment?

}
