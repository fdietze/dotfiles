{
  config,
  lib,
  pkgs,
  flake-inputs,
  hostLocal,
  uiFonts,
  ...
}: let
  specialisationHelpers = import ../../modules/nixos/specialisation-helpers.nix {
    inherit lib;
  };
  allowedSudoCommands =
    [
      "/run/current-system/sw/bin/cpupower frequency-set -u 400MHz"
      "/run/current-system/sw/bin/cpupower frequency-set -u 800MHz"
      "/run/current-system/sw/bin/cpupower frequency-set -u 2GHz"
      "/run/current-system/sw/bin/cpupower frequency-set -u 3GHz"
      "/run/current-system/sw/bin/cpupower frequency-set -u 4GHz"
      "/run/current-system/sw/bin/cpupower frequency-set -g powersave"
      "/run/current-system/sw/bin/cpupower frequency-set -g performance"
    ]
    ++ specialisationHelpers.sudoSwitchCommands;
in {
  imports = [
    # Hardware-Quirks dieses ThinkPad X1 (6th gen). Früher in flake.nix; seit der
    # generischen mkHost-Auto-Discovery zieht jeder Host sein nixos-hardware-Modul
    # selbst, da mkHost host-agnostisch ist.
    flake-inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-6th-gen
    ../../modules/options.nix
    ./power.nix
    ../../modules/nixos/stylix.nix
    ../../modules/nixos/desktops/gnome.nix
    ../../modules/nixos/desktops/herbstluftwm.nix
    ../../modules/nixos/desktops/noctalia-niri.nix
  ];

  nixpkgs.config.permittedInsecurePackages = [
    # add some here whenever needed
  ];
  nixpkgs.overlays = [
    (_: prev: {
      openldap = prev.openldap.overrideAttrs (oldAttrs: {
        # https://github.com/NixOS/nixpkgs/issues/514113
        doCheck = (oldAttrs.doCheck or true) && !prev.stdenv.hostPlatform.isi686;
      });
    })
  ];

  system.autoUpgrade.enable = false;
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
    # https://docs.noctalia.dev/v5/getting-started/nixos/
    # cache.numtide.com: vorgebaute AI-Agents aus llm-agents.nix (default-Overlay),
    # vermeidet lokales Kompilieren z.B. des Rust-Codex.
    settings.substituters = [
      "https://noctalia.cachix.org"
      "https://cache.numtide.com"
    ];
    settings.trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];

    # useful for using traditional nix-shell, but with nixpkgs pointing to the system flake
    # registry entries
    registry = {
      nixpkgs.flake = flake-inputs.nixpkgs;
    };
    # nix path to correspond to my flakes
    nixPath = ["nixpkgs=${flake-inputs.nixpkgs}"];
  };

  home-manager.backupFileExtension = "hm-bak";

  boot = {
    # kernelPackages = pkgs.linuxPackages_zen;
    kernelParams = [
      "kvm.enable_virt_at_load=0" # fix virtualbox
      # "zswap.enabled=1" # enables zswap
      # "zswap.compressor=zstd" # compression algorithm
      # "zswap.max_pool_percent=5" # maximum percentage of RAM that zswap is allowed to use
    ]; # https://github.com/NixOS/nixpkgs/issues/363887
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    # systemd-boot writes the current plain generation as loader.conf's default,
    # which keeps the first menu entry preselected.
    loader.timeout = null; # Show the boot menu until a specialization is chosen.
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [
      "ntfs"
      "exfat"
    ];

    initrd.kernelModules = [
      # "zstd"
      # "zsmalloc"
    ];

    # Howto: Installation of NixOS with encrypted root
    # https://gist.github.com/martijnvermaat/76f2e24d0239470dd71050358b4d5134
    initrd.luks.devices = {
      root = {
        device = hostLocal.disks.luksRoot;
        preLVM = true;
        allowDiscards = true;
      };
    };

    kernel.sysctl = {
      "kernel.sysrq" = 1; # enable REISUB: https://blog.kember.net/posts/2008-04-reisub-the-gentle-linux-restart/
      "vm.swappiness" = 10;
    };

    tmp = {
      useTmpfs = false;
      cleanOnBoot = true;
    };

    # Enable ARM64 emulation for Docker cross-architecture builds
    binfmt.emulatedSystems = ["aarch64-linux"];

    # extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];
  };

  # 3. Enable EarlyOOM (The Safety Net)
  # Prevents complete system lockups by killing the heaviest process
  # (usually a browser tab) when you have < 5% RAM left.
  # services.earlyoom = {
  #   enable = true;
  #   enableNotifications = true; # You get a popup if something is killed
  #   freeMemThreshold = 5; # Kill if less than 5% RAM free
  #   freeSwapThreshold = 5; # Kill if less than 5% Swap free
  # };

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
      wheelNeedsPassword = true;
      extraRules = [
        {
          users = ["felix"];
          commands =
            map (command: {
              inherit command;
              options = ["NOPASSWD"];
            })
            allowedSudoCommands;
        }
      ];
    };
  };

  networking = {
    hostName = "gurke";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager = {
      enable = true;
      dispatcherScripts = [
        {
          type = "basic";
          source = pkgs.writeText "network-timezone-update" ''
            case "$2" in
              up | connectivity-change)
                ${pkgs.systemd}/bin/systemctl --no-block start update-timezone-on-network.service || true
                ;;
            esac
          '';
        }
      ];
      plugins = with pkgs; [
        networkmanager-openvpn
      ];
    };
    # NetworkManager enables ModemManager by default. Disable it on this host
    # because the internal WWAN device is unused and the probes show up in logs.
    modemmanager.enable = false;
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
    firewall.allowedUDPPorts = lib.mkIf config.services.printing.enable [
      427 # SLP (Service Location Protocol) for printer discovery
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

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  # time.timeZone = "Europe/Berlin";
  # time.timeZone = "Europe/Sofia";
  # time.timeZone = "Europe/Lisbon";
  # time.timeZone = "Indian/Mauritius";
  location.provider = "geoclue2";
  services.automatic-timezoned.enable = true; # relies on geoclue to work: https://github.com/NixOS/nixpkgs/issues/321121
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
  users.users.geoclue.extraGroups = ["networkmanager"];

  systemd.services = {
    # Keep automatic-timezoned available, but run it only after NetworkManager
    # reports a network change. Geoclue is then stopped again after one update
    # window so location polling does not remain a background cost.
    automatic-timezoned.wantedBy = lib.mkForce [];
    automatic-timezoned-geoclue-agent.wantedBy = lib.mkForce [];
    # Keep the package and unit installed for manual use, but do not start the
    # daemon at boot. `systemctl start tailscaled` brings it online when needed.
    tailscaled.wantedBy = lib.mkForce [];
    update-timezone-on-network = {
      description = "Update timezone after network changes";
      after = ["NetworkManager.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.systemd}/bin/systemctl start automatic-timezoned.service
        ${pkgs.coreutils}/bin/sleep 90
        ${pkgs.systemd}/bin/systemctl stop \
          automatic-timezoned.service \
          automatic-timezoned-geoclue-agent.service \
          geoclue.service || true
      '';
    };
  };

  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 10;
    criticalPowerAction = "Hibernate";
  };

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
    extraPackages32 = with pkgs.pkgsi686Linux; [libva];
  };
  hardware.acpilight.enable = true;
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  }; # Force intel-media-driver
  hardware.sane = {
    enable = true; # scanners
    extraBackends = [pkgs.hplipWithPlugin]; # HP scanner support
  };

  hardware.bluetooth = {
    # https://nixos.wiki/wiki/Bluetooth
    enable = true;
    # powerOnBoot = false;
    settings.General.Experimental = true; # bluetooth battery percentage
  };
  services.blueman = {
    enable = false;
    # Home Manager owns blueman-applet.service. If NixOS also starts the applet,
    # systemd merges duplicate ExecStart= entries; systemd.service(5) only
    # allows that for Type=oneshot.
    # withApplet = false;
  };

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
  # libvirt + virt-manager for KVM/QEMU VMs (alternative to VirtualBox).
  # Wayland-native, virtio-gpu+virgl gives proper 3D for Linux guests.
  # KVM and VBox coexist since kernel 6.0.
  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true; # vTPM (needed by Win11 etc.); OVMF is on by default
    };
    # Disable the global ssh_config.d ProxyCommand include (for `ssh qemu:system/vm`).
    # The store-owned include (nobody:nogroup) is rejected by OpenSSH as
    # "Bad owner or permissions", breaking every ssh invocation. Unused: VMs run
    # via virt-manager, not ssh-by-name.
    sshProxy = false;
  };
  # SPICE USB redirect + virt-viewer integration
  virtualisation.spiceUSBRedirection.enable = true;
  services.spice-vdagentd.enable = true;
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
    systemPackages = with pkgs;
      [
        # only the bare minimum here
        git
        neovim

        # xdg-utils # Provides xdg-screensaver and other desktop integration tools
        # Remove lockers managed by home-manager or unused
        # i3lock       # Dependency for betterlockscreen
        # betterlockscreen # The new locker

        # workaround for rust-analyzer with openblas not finding CC
        # gcc
        # gfortran
      ]
      ++ lib.optionals config.services.printing.enable [
        hplipWithPlugin # HP printer utilities (hp-setup, hp-toolbox, etc.)
      ];
  };

  services.ollama.enable = false; # local ai models
  services.qdrant.enable = false; # vector search engine, used for kilo code indexing

  # Remove PAM configuration for i3lock
  # security.pam.services.i3lock = { ... };

  # Remove PAM configuration for betterlockscreen
  # security.pam.services.betterlockscreen = { ... };

  programs.nix-ld.enable = true; # run non-nixos binaries on nixos
  programs.nix-ld.libraries = [];
  programs.appimage.enable = true;
  programs.zsh.enable = true;
  programs.fish.enable = false;
  programs.java = {
    enable = true; # provide JAVA_HOME
    package = pkgs.jdk17; # needed for flutter builds in android studio
  };
  programs.dconf.enable = true; # useful for: blueman-applet, ...
  programs.iotop.enable = true;

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

  my = {
    # The unnamed generation is the boot menu's top entry. Keep it explicit so
    # option defaults cannot silently turn it into a GNOME configuration.
    desktop = "herbstluftwm";
    theme = "dark";
  };

  system.activationScripts."current-specialisation" = ''
    mkdir -p /run/nixos
    printf '%s\n' ${
      lib.escapeShellArg (
        if config.isSpecialisation
        then
          specialisationHelpers.specialisationName {
            inherit (config.my) desktop theme;
          }
        else ""
      )
    } > /run/nixos/current-specialisation
  '';

  home-manager.extraSpecialArgs = {
    desktop = config.my.desktop;
    theme = config.my.theme;
    hostLabel = config.networking.hostName;
    inherit flake-inputs;
    nvf = flake-inputs.nvf;
    inherit hostLocal;
    inherit uiFonts;
  };

  specialisation = specialisationHelpers.specialisations;

  # Start the driver at boot
  systemd.services.fprintd = {
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "simple";
  };
  # Install the driver
  services.fprintd.enable = true;

  services.xserver = {
    enable = true;
    videoDrivers = ["modesetting"];

    xkb.layout = "de,de";
    xkb.variant = "neo,basic";
    xkb.options = "altwin:swap_lalt_lwin";

    desktopManager.xterm.enable = false;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "felix";
  };

  fonts = {
    enableDefaultPackages = true;
    enableGhostscriptFonts = true;
    packages = lib.unique (
      [
        uiFonts.serif.package
        uiFonts.sans.package
        uiFonts.monospace.package
        uiFonts.emoji.package
        uiFonts.icons.package
      ]
      ++ (with pkgs; [
        corefonts # Arial, Verdana, ...
        vista-fonts # Consolas, ...
        # google-fonts # Droid Sans, Roboto, ...
        roboto
        # ubuntu_font_family
      ])
    );
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
    fontconfig = {
      includeUserConf = false; # no user fonts.conf
      defaultFonts = {
        serif = [
          uiFonts.serif.name
          uiFonts.emoji.name
        ];
        sansSerif = [
          uiFonts.sans.name
          uiFonts.emoji.name
        ];
        monospace = [
          uiFonts.monospace.name
          uiFonts.emoji.name
        ];
        emoji = [uiFonts.emoji.name];
      };
    };
    fontDir.enable = true;
  };

  services = {
    cron.enable = true;
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.X11Forwarding = true;
    };
    tailscale.enable = true;

    fstrim.enable = true; # periodic SSD TRIM of mounted partitions in background

    avahi = {
      # Network discovery. Keep disabled by default; enable when mDNS service
      # discovery or printer discovery is actually needed.
      enable = false;
      nssmdns4 = true;
      publish.enable = true;
      publish.addresses = true;
      openFirewall = true;
    };

    gvfs.enable = true; # virtual file system support for graphical file managers
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
      enable = false;
      drivers = [pkgs.hplip];
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
  users.groups.plugdev = {};
  users.groups.usb = {};

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="cafe", ATTR{idProduct}=="4000", MODE="0660", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8771", MODE="0660", GROUP="plugdev"
    # The Logitech Unifying receiver can miss wakeups after system suspend when
    # USB runtime autosuspend is enabled globally; keep only this dongle active.
    ACTION=="add|change", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="046d", ATTR{idProduct}=="c52b", TEST=="power/control", ATTR{power/control}="on"
  '';

  # KEYBOARD_KEY_70052=slash
  services.udev.extraHwdb = ''
    evdev:input:b0005v04E8p7021*
     KEYBOARD_KEY_700e2=leftmeta
     KEYBOARD_KEY_700e3=leftalt
     KEYBOARD_KEY_700e6=rightmeta
     KEYBOARD_KEY_700e7=rightalt
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
        "libvirtd" # virt-manager / libvirtd socket access
        "scanner" # for HP scanner support
        "lp" # for printer access
      ];
      shell = pkgs.zsh;
    };
  };

  system.stateVersion = "26.05";
  # system.stateVersion = "18.03";
}
