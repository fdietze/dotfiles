{ config, pkgs, ... }:
# let

#   gnome3 = config.environment.gnome3.packageSet;

# in

{
  imports =
  [
    ./hardware-configuration.nix
  ];

  boot = {
    loader = {
      # Use the systemd-boot EFI boot loader
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;

      grub = {
        efiSupport = true;
        device = "/dev/nvme0n1";
        memtest86.enable = true;
      };
    };

    kernelParams = ["processor.max_cstate=1"]; # fix for ryzen freeze?

    # kernelPackages = pkgs.linuxPackages_4_4;
    kernelPackages = pkgs.linuxPackages_latest;
    blacklistedKernelModules = [ "pinctrl-amd" ]; # else: kernel panic with ryzen


    tmpOnTmpfs = true;

    kernel.sysctl = {
      "vm.swappiness" = 0;
      "fs.inotify.max_user_watches" = "409600";
    };
  };



  nixpkgs.config = {
    allowUnfree = true;
    chromium = {
      # enablePepperFlash = true;
      enablePepperPDF = true;
      enableWideVine = false;
    };
    #  --param l1-cache-line-size=64 --param l2-cache-size=8192 -mtune=nehalem
    # stdenv.userHook = ''
    #   NIX_CFLAGS_COMPILE+="-march=native"
    # '';

    programs.qt5ct.enable = true;

  };

  # nix.extraOptions = ''
  #   auto-optimise-store = true
  #   build-fallback = true
  # '';

  hardware = {
    pulseaudio.enable = true;
    pulseaudio.support32Bit = true; # This might be needed for Steam games
    opengl.driSupport32Bit = true;
    sane.enable = true;

    cpu.amd.updateMicrocode = true;
  };

  networking.hostName = "fff";

  i18n = {
    #consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "neo";
    defaultLocale = "en_US.UTF-8";
  };

  time.timeZone = "Europe/Berlin";

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment = {
    systemPackages = with pkgs; [
      wget pv htop atop git netcat nmap xorg.xkill psmisc lm_sensors calc tree gparted gksu ntfs3g inotify-tools unzip
      ncdu fzf fasd silver-searcher tig ctags xclip tmate pmount scrot nix-zsh-completions haskellPackages.yeganesh
      termite xcwd numix-gtk-theme nitrogen unclutter-xfixes grc #cope
      dzen2 dmenu rofi conky lua lua51Packages.luafilesystem trayer polybar # panel
      chromium firefox
      jdk scala sbt maven visualvm
      gnumake cmake clang gcc autoconf automake
      meld
      nodejs yarn
      docker docker_compose
      # rust.rustc rust.cargo
      nim
      texlive.combined.scheme-full
      biber

      boost
      wine winetricks mono

      libreoffice-fresh hunspell hunspellDicts.en-us languagetool mythes
      samba cifs-utils

      neovim
      python2
      python27Packages.neovim # ensime
      python27Packages.websocket_client # ensime
      python27Packages.sexpdata # ensime
      python3
      python35Packages.neovim

      mosh

      mate.atril inkscape gimp
      # spotify
      sane-frontends
      mpv vlc playerctl pamixer imv

      vulkan-loader

      xdg_utils
      shared_mime_info # file-type associations?
      desktop_file_utils

      gnome3.dconf # needed for meld
      gnome3.nautilus gnome3.gvfs
      gnome3.gnome_keyring gnome3.seahorse libsecret
    ];

    shellAliases = {
      l = "ls -l";
      t = "tree -C"; # -C is for color=always
      vn = "vim /etc/nixos/configuration.nix";
    };

    variables = {
      SUDO_EDITOR = "nvim";
      EDITOR = "nvim";
      # BROWSER = "firefox";
      BROWSER = "chromium";
      SSH_AUTH_SOCK = "%t/keyring/ssh";
    };


  };

  nix.maxJobs = 16;
  nix.buildCores = 16;

  nix.gc.automatic = true;
  nix.gc.dates = "23:00";
  nix.gc.options = "--delete-older-than 7d";
  system.autoUpgrade.enable = true;
  system.autoUpgrade.dates = "23:15";

  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.command-not-found.enable = true;
  users.defaultUserShell = "/run/current-system/sw/bin/zsh";

  security = {
    # pam.services = [
    #   {
    #     name = "gnome_keyring";
    #     text = ''
    #       auth     optional    ${gnome3.gnome_keyring}/lib/security/pam_gnome_keyring.so
    #       session  optional    ${gnome3.gnome_keyring}/lib/security/pam_gnome_keyring.so auto_start
    #       password optional    ${gnome3.gnome_keyring}/lib/security/pam_gnome_keyring.so
    #     '';
    #   }
    # ];
    wrappers = {
      pmount.source = "${pkgs.pmount}/bin/pmount";
      pumount.source = "${pkgs.pmount}/bin/pumount";
      eject.source = "${pkgs.eject}/bin/eject";
    };
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  networking.firewall.allowedUDPPortRanges = [ { from = 60000; to = 61000; } ]; # for mosh

  services = {
    openssh = {
      enable = true;
      passwordAuthentication = false;
    };

    journald = {
      extraConfig =
      ''
        Storage=persist
        Compress=yes
        SystemMaxUse=128M
        RuntimeMaxUse=8M
      '';
    };

    fstrim.enable = true;

    printing = {
      enable = true;
      drivers = [ pkgs.gutenprint pkgs.hplip pkgs.epson-escpr ];
    };

    xserver = {
      enable = true;
      videoDrivers = [ "nvidia" ];
      layout = "de,de";
      xkbVariant = "neo,basic";
      xkbOptions = "grp:menu_toggle";
      displayManager.lightdm.enable = true;
      windowManager.herbstluftwm.enable = true;
      windowManager.i3.enable = true;
    };
    # compton.enable = true;
    redshift = {
      enable = true;
      latitude = "50.77";
      longitude = "6.08";
    };

    # hide mouse after some seconds of no movement
    unclutter-xfixes.enable = true;


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

    locate = {
      enable = true;
      interval = "22:00";
    };

    psd = {
      enable = true;
      users = ["felix" "jelias"];
    };

    # clamav = {
    #   daemon.enable   = true;
    #   daemon.extraConfig = ''
    #     TCPAddr   127.0.0.1
    #     TCPSocket 3310
    #   '';
    #   updater.enable  = true;
    # };

    upower.enable  = true;
    gnome3.gvfs.enable  = true;
    gnome3.gnome-keyring.enable = true;
    udisks2.enable = true;

    # ipfs = {
    #   enable = true;
    # };
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

  virtualisation.virtualbox.host.enable = true;
  nixpkgs.config.virtualbox.enableExtensionPack = true;
  virtualisation.docker.enable = true;

  #users.mutableUsers = false;
  users.extraUsers.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "vboxusers" "docker"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDU3dAvm/F8DksvT2fQ1804/ScajO20OxadixGD8lAPINLbCj7mRpLJmgnVjdJSSHQpaJXsDHjLul4Z4nuvgcOG2cjtI+/Z2d1AC+j5IDTJNs6yGgyzkRalPYWXKpzrOa/yQcVpJyGsliKyPuyc9puLJIQ0vvosVAUxN6TLMfnrgdtnZMsuQecToJ8AgyEgsGedOnYC2/1ELUJEdh2v2LMr2saWJW/HTptTotbS8Fwz+QWZPAxXWlEbH5r5LEma3xpn/7oiE4JKr7DL7bE4jWVgW0yrOZL0EAVm771oigqcS/ekTqLutVoFmcH0ysInsWKjnuT02+PIjDJdGODwlE5P felix@beef"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDEgFHPfX2zAgJvTYxRN9/M5rRyR2G3MKA7ZDA6qGTYX7eH7qIvBN1krGe+A6PVf2WOlftDQru0Ws3YWgLUfbzXdB5esshvjO1MtkwlwBi6EO7scDDTkcxswQLcpa10fUdkwlqeaPes8oxsA1RMoaYiVx2l+JAXsNhzchCOLkcve6zr8vA5RcWIqd4E9Z0ZJewghJgPSpthdaV8/dJY1Xumz43dbDvJVAs92YiZiaBkMIJeH+sWhhWL1YuQ/WtgtTh+s32DtkCmvyffbs4/5sE+yhZwHcbZcDZ77WVw7EmzNNfGBbS4ABK+T355qSGwbToOiWN2e/ZFKrucSpbCTZgH cornerman@genius"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCuuJUpJb/RaaGtng74AwZngADO5tDBUoDj4gfnDl1C2E6jpzF4iZtIhiSzqKxvmPWYGhsQrdptRH1sQqRaTEODhCThDJ4Z0CkiVk7oVVNM+qD+Z6RMsxRda/aHqnqQuarK3kVhoWQJNj1gjyk9aHmg1Cx0LCpGscH7CPv7H1+qBbwxOgzDYeHP773Lc1tmXicMKGZopfBEgDYVgApnuDU2A9nljAMndBqNS6D3xi0eCaPynESMAHfcZakNuhglsEw8Vmzq3ug0POy1xgWvyBl1KF+XZF/IFmSVRr4wBjW3r0qKdaOZ/0ZLKG5eSHoD+Pkr/x5cTsUWIJlZGJelamNr9X+291Msps6iGXlgY6UncnCqGSJxMXB0JHboXYl1XkX4DjChQg9fL6Qij3HsDHj5JFbP4NGzKirVBmppYB8EKboXCi3BGepPPuNRl965Yx9R8yGoP4daoKVZ63kRxM3k4wQMPS2mBfIrK3kjk5JmAeUxaE9geZS1uey77LFBD9rEx7qQ+afnmhxREARCtIPSZt+onqxOarEJkby6MXZpbCpvD6hk+D0rK7gSixw0YTzUXcwPTWrCVKwViEYN7MjlkvUzXKEiWrwai+AvBX0GdN460vrvSNQttRkYzdr1OFhPAkugsRr+Lff2SYnPmG5jX1cVt5A1dgEOdPinzx/mMQ== felix@neptun"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIILlPXr5xNU6DlafZwUQHOUHtr9FK9qObMn2oxrK+PtW felix@cloud"
    ];
  };

  users.extraUsers.jelias = {
    isNormalUser = true;
    extraGroups = ["wheel" "vboxusers" "docker" "scanner"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM+BIE+0anEEYK0fBIEpjedblyGW0UnuYBCDtjZ5NW6P jelias@merkur"
    ];
  };
}
