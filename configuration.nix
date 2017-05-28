{ config, pkgs, ... }:

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

    # kernelPackages = pkgs.linuxPackages_4_4;
    kernelPackages = pkgs.linuxPackages_latest;
    blacklistedKernelModules = [ "pinctrl-amd" ]; # else: kernel panic with ryzen


    tmpOnTmpfs = true;

    kernel.sysctl = {
      "vm.swappiness" = 0;
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
  };

  # nix.extraOptions = ''
  #   auto-optimise-store = true
  #   build-fallback = true
  # '';

  hardware = {
    pulseaudio.enable = true;
    pulseaudio.support32Bit = true; # This might be needed for Steam games
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
      wget pv htop atop git netcat xorg.xkill psmisc lm_sensors calc tree gparted gksu scrot
      evince
      neovim python35Packages.neovim python27Packages.neovim python
      fzf silver-searcher tig xclip tmate pmount nix-zsh-completions
      termite keepassx-community unclutter-xfixes numix-gtk-theme redshift nitrogen
      dzen2 dmenu conky lua lua51Packages.luafilesystem trayer polybar # panel
      chromium firefox
      jdk scala sbt maven visualvm
      gnumake cmake clang gcc autoconf automake
      nodejs yarn
      docker docker_compose
      rustNightly.rustc rustNightly.cargo
      nim
      texlive.combined.scheme-full
      ntfs3g

      spotify mpv vlc playerctl pamixer
      imv

      bruteforce-luks
      haskellPackages.yeganesh
      gnome3.gvfs
      gnome3.nautilus
    ];

    shellAliases = {
      l = "ls -l";
      t = "tree -C"; # -C is for color=always
      vn = "vim /etc/nixos/configuration.nix";
      };

      variables = {
        SUDO_EDITOR = "nvim";
        EDITOR = "nvim";
        BROWSER = "chromium";
      };
    };

    nix.maxJobs = 32;
    nix.buildCores = 24;

    nix.gc.automatic = true;
    nix.gc.dates = "01:15";
    nix.gc.options = "--delete-older-than 30d";
    system.autoUpgrade.enable = true;

    programs.zsh.enable = true;
    programs.zsh.enableCompletion = true;
    users.defaultUserShell = "/run/current-system/sw/bin/zsh";

    security = {
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

    # Open ports in the firewall.
    # networking.firewall.allowedTCPPorts = [ ... ];
    # networking.firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    # networking.firewall.enable = false;

    # Enable CUPS to print documents.
    # services.printing.enable = true;

    hardware.opengl.driSupport32Bit = true;
    services = {
      sshd = {
        enable = true;
        passwordAuthentication = false;
      };

      xserver = {
        enable = true;
        videoDrivers = [ "nvidia" ];
        layout = "de,de";
        xkbVariant = "neo,basic";
        xkbOptions = "grp:menu_toggle";
      };

      syncthing = {
        enable = true;
        user = "felix";
        dataDir = "/home/felix/.config/syncthing";
      };

      locate = {
        enable = true;
        interval = "22:00";
      };

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
        opensans-ttf
        ubuntu_font_family
        inconsolata
        font-droid # needed for firefox
      ];
      fontconfig = {
        # dpi = 227;
        defaultFonts.monospace = [ "Inconsolata" "DejaVu Sans Mono" ];
      };
    };

    services.xserver.windowManager.herbstluftwm.enable = true;
    services.redshift = {
      enable = true;
      latitude = "50.77";
      longitude = "6.08";
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
        # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDEgFHPfX2zAgJvTYxRN9/M5rRyR2G3MKA7ZDA6qGTYX7eH7qIvBN1krGe+A6PVf2WOlftDQru0Ws3YWgLUfbzXdB5esshvjO1MtkwlwBi6EO7scDDTkcxswQLcpa10fUdkwlqeaPes8oxsA1RMoaYiVx2l+JAXsNhzchCOLkcve6zr8vA5RcWIqd4E9Z0ZJewghJgPSpthdaV8/dJY1Xumz43dbDvJVAs92YiZiaBkMIJeH+sWhhWL1YuQ/WtgtTh+s32DtkCmvyffbs4/5sE+yhZwHcbZcDZ77WVw7EmzNNfGBbS4ABK+T355qSGwbToOiWN2e/ZFKrucSpbCTZgH cornerman@genius"
      ];
    };
  }
