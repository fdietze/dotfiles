# https://mipmip.github.io/home-manager-option-search/
{
  config,
  pkgs,
  theme,
  ...
}:

{
  imports = [
    ./home/shell.nix
    ./home/git.nix
    ./home/yazi.nix
    ./home/herbstluftwm.nix
    ./home/dictate.nix
  ];

  # https://nix-community.github.io/home-manager/index.xhtml
  home.username = "felix";
  home.homeDirectory = "/home/felix";

  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.cargo/bin"
    "$HOME/.npm-packages/bin"
  ];

  # home.sessionCommand

  home.file.".theme".text = theme;

  home.sessionVariables = {
    CLICOLOR_FORCE = 1; # ANSI colors should be enabled no matter what. (https://bixense.com/clicolors/)

    EDITOR = "${pkgs.neovim}/bin/nvim";
    BROWSER = "${pkgs.firefox}/bin/firefox";
    # BROWSER = "${pkgs.librewolf}/bin/librewolf";
    PAGER = "less --RAW-CONTROL-CHARS"; # less with colors

    # colorize less
    LESS = "--use-color --RAW-CONTROL-CHARS --incsearch --ignore-case --redraw-on-quit --mouse --wheel-lines=3";

    MOZ_USE_XINPUT2 = 1; # fix firefox scrolling, enable touchpad gestures

    # QT_QPA_PLATFORMTHEME = "gtk2"; # let qt apps use gtk 2 themes
    # QT_AUTO_SCREEN_SCALE_FACTOR = 1; # honor screen DPI
  };

  xdg.userDirs = {
    download = "${config.home.homeDirectory}/downloads";
  };
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "image/jpeg" = [ "feh.desktop" ];
      "image/png" = [ "feh.desktop" ];
      "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
    };
  };

  programs.bat.enable = true;
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = { }; # don't generate direnv.toml and use the existing one instead
  };

  home.shellAliases = {
    # /home/felix.old-2024-03-01/.aliases
    # /home/felix.old-2024-03-01/.sh_aliases

    # incubator
    s = "${pkgs.ddgr}/bin/ddgr";
    vf = ''$EDITOR "$HOME"/nixos/flake.nix'';
    vt = ''$EDITOR "$HOME"/MEGAsync/notes/todo.md'';
    lg = "lazygit";
    nrb = "sudo nixos-rebuild boot";
    t1a = "exa --tree --color=always -L 1 -a";
    t2a = "exa --tree --color=always -L 2 -a";
    t3a = "exa --tree --color=always -L 3 -a";
    cat = "bat -n --paging=never";
    cd = "z";
    # rm = "${pkgs.trashy}/bin/trash put";
    sec = "source $HOME/bin/secret-envs";
    # aider = "sec && ${pkgs.aider-chat}/bin/aider --no-check-update";
    alors = "sec && alors";
    opencode = "sec && opencode";
    oc = "sec && opencode";
    c = ''sec && AICHAT_LIGHT_THEME=$(grep -q "light" ~/.theme && echo "true" || echo "false") ${pkgs.aichat}/bin/aichat --session $(date --iso-8601=seconds) --save-session'';
    cb = "sec && $HOME/bin/cb";
    cq = "sec && $HOME/bin/cq";
    ssh = "sec && TERM=xterm-256color ssh"; # fix colors in some ssh connections
    scp = "sec && scp";
    rg = "rg --hidden  --no-follow --no-heading --glob '!.git/*' --smart-case"; # https://github.com/BurntSushi/ripgrep/issues/623

    qrscan = "LD_PRELOAD=/usr/lib/libv4l/v4l1compat.so ${pkgs.zbar}/bin/zbarcam --raw /dev/video0";
    qr = "${pkgs.qrencode}/bin/qrencode -t ansiutf8";
    tclip = ''tmate display -p "#{tmate_ssh}" | xclip -selection clipboard''; # tmate session token to clipboard
    tw = "${pkgs.timewarrior}/bin/timew";
    feh = "feh --auto-zoom --scale-down";
    im = ''
      ${pkgs.feh}/bin/feh --fullscreen --auto-zoom --sort mtime \
              --action '${pkgs.trashy}/bin/trash put %F' \
              --action1 'mkdir -p 1; mv %F 1/' \
              --action2 'mkdir -p 2; mv %F 2/' \
              --action3 'mkdir -p 3; mv %F 3/' \
    '';
    zed = "sec && ${pkgs.zed-editor}/bin/zeditor";
    # gemini = "sec && gemini";
    # gmc = "geminicommit";
    signal-desktop = ''sec && signal-desktop --password-store="gnome-libsecret"'';

    ##################
    # well established
    dc = "docker-compose";

    vim = "$EDITOR";

    v = ''nvim -c "FzfLua files"'';
    vg = ''nvim -c "FzfLua live_grep"'';
    vr = ''nvim -c "FzfLua oldfiles"''; # recently used files
    p = "cd $(select-project)";

    ls = "${pkgs.eza}/bin/eza --all --group-directories-first";
    l = "ls -l";
    la = "ls -la";
    lt = "ls -l --sort newest";
    lta = "ls -la --sort newest";
    t = "${pkgs.eza}/bin/eza --tree --color=always";
    ta = "${pkgs.eza}/bin/eza --tree --color=always -a";
    t1 = "${pkgs.eza}/bin/eza --tree --color=always -L 1";
    t2 = "${pkgs.eza}/bin/eza --tree --color=always -L 2";
    t3 = "${pkgs.eza}/bin/eza --tree --color=always -L 3";
    tg = "tree-git";
    vv = ''nvim -c "FzfLua files cwd=~/.config/nvim"'';
    vn = ''$EDITOR "$HOME"/nixos/configuration.nix'';
    vh = ''$EDITOR "$HOME"/nixos/home.nix'';
    vb = ''$EDITOR "$HOME"/.config/polybar/config.ini'';
    nrs = "sudo nixos-rebuild switch";
    ns = "nix-shell --run zsh";
    ni = "nix profile install nixpkgs#";
    md = "mkdir -p";
    cdd = "cd ~/downloads";
    cdp = "cd ~/projects";
    rcp = "rsync --archive --partial --info=progress2 --human-readable";
    sys = "sudo systemctl";
    sysu = "systemctl --user";
    w = "watch --color --differences "; # trailing space is for alias expansion: https://unix.stackexchange.com/a/25329
    chromium = "chromium --force-device-scale-factor=1.5"; # fix highdpi for chromium
    google-chrome-stable = "google-chrome-stable --force-device-scale-factor=1.5"; # fix highdpi for chromium
    chromium-no-plugins = "chromium --disable-extensions --disable-plugins";

    lsblk = "lsblk -o NAME,RM,SIZE,FSTYPE,LABEL,MOUNTPOINT,RO,UUID";

    ".." = "cd ..";
    cdt = "cd-tmp";

    m = "make";
    # mc = "make clean";
    drs = "$HOME/projects/ubunix/ubunix.sh";

    online = "ping -c 1 8.8.8.8 -W 5 && ping -c 1 google.com -W 5"; # -c <retries>  -W <timout>
    online-wait = "until online; do; sleep 3; done; ${pkgs.espeak}/bin/espeak -p 30 'online'; ${pkgs.espeak}/bin/espeak -p 80 'online'; ${pkgs.espeak}/bin/espeak -p 50 'online'";
    # alias on="w --interval=1 '$ONLINECMD'"

  };

  # programs.command-not-found.enable = true;
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  services.podman.enable = true;

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
  };

  stylix = {
    autoEnable = true;
    cursor = {
      name = "Vanilla-DMZ";
      package = pkgs.vanilla-dmz;
      size = 128;
    };
    fonts.sizes.applications = 8;
    fonts.sizes.terminal = 8;

    targets = {
      dunst.enable = true;
      rofi.enable = false;
      neovim.enable = false;
    };
  };

  programs.neovim = {
    # ~/.config/nvim/init.lua
    enable = true;
    # plugins = with pkgs.vimPlugins; [ nvim-treesitter.withAllGrammars ];
  };

  # programs.atuin = {
  #   enable = true;
  #   enableZshIntegration = true;
  #   flags = [
  #     "--disable-up-arrow"
  #   ];
  #   settings = {
  #     # https://docs.atuin.sh/configuration/config/
  #     theme = "tokyo_night";
  #     style = "compact";
  #     enter_accept = true;
  #     inline_height = 10;
  #   };
  # };

  programs.ghostty = {
    enable = false;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    settings = {
      window-padding-x = 2;
      window-decoration = "none";
      font-size = 17; # stylix size is too small
      confirm-close-surface = false; # don't confirm to close when a command is running
    };
  };
  programs.alacritty = {
    enable = true;
    settings = {
      font.size = 8;
      scrolling.history = 100000;
      window.padding.x = 2;
      cursor.style = {
        blinking = "Never";
        shape = "Beam";
      };
      general.import = [ "~/.config/alacritty/theme.toml" ];
      keyboard.bindings = [
        # Maps Shift+Enter to send a special escape code.
        # We use a standard CSI sequence: \x1b[13;2u
        # 13 is for the Enter key, ;2 indicates Shift is pressed.
        # {
        #   key = "Enter";
        #   mods = "Shift";
        #   chars = "\x1b[13;2u";
        # }
      ];
    };
  };
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
        color_scheme = "tokyonight_storm",
        default_cursor_style = 'SteadyBar',
        cursor_blink_rate = 0,
        enable_tab_bar = false,
        window_padding = {
          left = "2px",
          right = "2px",
          top = "2px",
          bottom = "2px",
        },
      }
    '';
  };
  programs.helix.enable = false;
  services.copyq.enable = false;

  services.udiskie = {
    enable = true;
    settings = {
      # workaround for
      # https://github.com/nix-community/home-manager/issues/632
      program_options = {
        # replace with your favorite file manager
        file_manager = "${pkgs.nemo-with-extensions}/bin/nemo";
      };
    };
  };

  services.redshift = {
    # Redshift adjusts the color temperature of your screen. This may help your eyes hurt less if you are working in front of the screen at night.
    enable = true;
    provider = "geoclue2";
  };

  services.unclutter = {
    # hide mouse after some seconds of no movement
    enable = true;
  };

  services.espanso = {
    # https://github.com/espanso/espanso
    enable = true;
    matches = {
      base = {
        matches = [
          {
            trigger = ":date";
            replace = "{{currentdate}}";
          }
          {
            trigger = ":opt";
            replace = "What are the decisions we have to make? What are the options, trade-offs and recommendations? "; # needs space, else ? disappear -> nix yaml generator bug?
          }
          {
            trigger = ":hello";
            replace = "line1\nline2&";
          }
          {
            regex = ":hi(?P.*)\\.";
            replace = "Hi {{person}}!";
          }
        ];
      };
      global_vars = {
        global_vars = [
          {
            name = "currentdate";
            type = "date";
            params = {
              format = "%Y-%m-%d";
            };
          }
        ];
      };
    };
  };

  services.playerctld.enable = true;

  services.blueman-applet.enable = true; # bluetooth tray icon, needs dconf
  services.mpris-proxy.enable = true; # bluetooth buttons

  services.dunst = {
    # https://github.com/dunst-project/dunst/blob/master/dunstrc
    # old configFile = "$HOME/.config/dunst/dunstrc.old";
    enable = true;
    # settings = {
    #   global = {
    #     frame_width = 1;
    #     frame_color = "#9ECE6A";
    #     font = "Monospace 7";
    #   };
    #   urgency_normal = {
    #     background = "#191C26";
    #     foreground = "#eceff1";
    #   };
    # };
  };

  services.flameshot = {
    enable = true;
    settings = {
      General = {
        contrastOpacity = 51;
        disabledTrayIcon = false;
        drawColor = "#9ECE6A";
        filenamePattern = "%F_%H-%M-%S";
        savePath = "/home/felix/screenshots";
        savePathFixed = true;
        showStartupLaunchMessage = false;
      };
    };
  };

  services.picom = {
    enable = true;
    vSync = true;
  };
  services.xsettingsd = {
    enable = true;
    settings = {
      "Net/ThemeName" = "adw-gtk3-${theme}";
    };
    # settings = {
    # for dark-light theme switching, the config file needs to be mutable:
    # ~/.config/xsettingsd/xsettingsd.conf
    # It will be modified by the script ~/bin/theme
    #
    # # https://github.com/derat/xsettingsd/wiki/Settings
    #
    # "Xft/Hinting" = 1;
    # "Xft/HintStyle" = "hintslight";
    # "Xft/Antialias" = 1;
    # "Xft/RGBA" = "rgb";
    # "Net/ThemeName" = "Qogir-Dark";
    # "Net/IconThemeName" = "Qogir-dark";
    # };
  };

  systemd.user.services.frottage = {
    Unit = {
      Description = "Frottage";
      After = [
        "graphical-session-pre.target"
        "network-online.target"
        "nss-lookup.target"
      ]; # Ensure graphical session and network are available
      Wants = [
        "network-online.target"
        "nss-lookup.target"
      ]; # Require network connection
      PartOf = [
        "graphical-session.target"
      ]; # Tie service lifetime to graphical session
    };
    Service = {
      Type = "oneshot";
      # Environment = "DISPLAY=:0"; # Might be needed if DISPLAY is not inherited correctly
      # Use sh -c to run a small script determining the wallpaper URL based on ~/.theme
      ExecStart =
        let
          script = pkgs.writeShellScriptBin "frottage-user" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            THEME=${theme}
            case "$THEME" in
              light) TARGET=desktop-light ;;
              *) TARGET=desktop ;;
            esac

            # Ensure the target directory exists
            ${pkgs.coreutils}/bin/mkdir -p "$HOME/frottage"

            DOWNLOAD_URL="https://frottage.app/static/wallpaper-''${TARGET}-latest.jpg"
            OUTPUT_PATH="$HOME/frottage/wallpaper.jpg"
            ${pkgs.feh}/bin/feh --bg-fill "$OUTPUT_PATH" || true

            echo "Starting wallpaper download for theme: ''${TARGET}"
            echo "Downloading $DOWNLOAD_URL to $OUTPUT_PATH with retries"

            if ${pkgs.curl}/bin/curl --retry 5 --retry-delay 10 --retry-all-errors -sfSL -o "$OUTPUT_PATH" "$DOWNLOAD_URL"; then
              echo "Download successful."
              # Set the wallpaper
              echo "Setting wallpaper using feh."
              ${pkgs.feh}/bin/feh --bg-fill "$OUTPUT_PATH"
              exit 0 # Success
            else
              curl_exit_code=$?
              echo "curl command failed after retries with exit code: $curl_exit_code." >&2
              echo "Failed to download wallpaper from $DOWNLOAD_URL." >&2
              echo "Falling back to last wallpaper." >&2
              ${pkgs.feh}/bin/feh --bg-fill "$OUTPUT_PATH"
              exit 1 # Failure
            fi
          '';
        in
        "${script}/bin/frottage-user";
    };
  };

  systemd.user.timers.frottage = {
    Unit = {
      Description = "Frottage Timer";
    };
    Timer = {
      OnActiveSec = "15s";
      OnCalendar = "*-*-* 01,07,13,19:00:00 UTC";
      Persistent = true; # Run job if missed due to suspend/shutdown
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # services.syncthing.enable = true;

  # systemd.user.services.xsettingsd = {
  #   Unit = {
  #     Description = "xsettingsd";
  #     After = ["graphical-session-pre.target"];
  #     PartOf = ["graphical-session.target"];
  #   };
  #
  #   Install.WantedBy = ["graphical-session.target"];
  #
  #   Service = {
  #     Environment = "PATH=${config.home.profileDirectory}/bin";
  #     ExecStart =
  #       "${pkgs.xsettingsd}/bin/xsettingsd"
  #       + optionalString (cfg.configFile != null)
  #       " -c ${escapeShellArg cfg.configFile}";
  #     Restart = "on-abort";
  #   };
  # };

  # services.megasync.enable = true; # is started in ~/.xprofile

  # gtk = {
  #   enable = true;
  #   theme = {
  #     name = "Qogir-Dark";
  #     package = pkgs.qogir-theme;
  #   };
  #   iconTheme = {
  #     name = "Qogir-Dark";
  #     package = pkgs.qogir-icon-theme;
  #   };
  # };

  # gtk.cursorTheme = {
  #   name = "Vanilla-DMZ";
  #   # size = 64;
  # };

  # home.pointerCursor = {
  #   x11.enable = true;
  #   gtk.enable = true;
  #   name = "Vanilla-DMZ";
  #   package = pkgs.vanilla-dmz;
  #   size = 128;
  # };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.ripgrep = {
    enable = true;
  };
  programs.eza = {
    # colorful ls alternative
    enable = true;
    git = true;
    icons = "auto";
  };
  services.network-manager-applet.enable = true;

  # programs.ssh = {
  #   enable = true;
  # };

  services.ssh-agent.enable = true;

  programs.rofi = {
    # application launcher, window switcher, ssh launcher
    enable = true;

    theme =
      let
        fetchedContent = builtins.fetchurl {
          url = "https://raw.githubusercontent.com/newmanls/rofi-themes-collection/c2be059e9507785d42fc2077a4c3bc2533760939/themes/squared-everforest.rasi";
          sha256 = "14p055gbqr7wijahjmd8jr04jn6nscs2zx3fyiy42c4n8yi0v98f";
        };
        fileContent = builtins.readFile fetchedContent;
        # replace font in theme with monospace font.
        replacedContent =
          builtins.replaceStrings
            [
              ''"FiraCode Nerd Font Medium 12"''
              "width:      480;"
            ]
            [ ''"mono 30"'' "width: 1000;" ]
            fileContent;
      in
      builtins.toFile "squared-everforest-modified.rasi" replacedContent;

    plugins = with pkgs; [
      rofi-calc
      rofi-emoji
      # rofi-bluetooth
      # rofi-vpn
      # rofi-systemd
      # rofi-pulse-select
      # rofi-file-browser
    ];
    extraConfig = {
      modi = "run,calc,emoji";
      run-list-command = ''bash -ic "alias | awk -F'[ =]' '{print \$2}'"'';
      run-command = "bash -ic '{cmd}'";
    };
  };

  programs.librewolf = {
    # https://github.com/mjschwenne/dotfiles/blob/f45fbe1e6ea426342be03054d9e26ab1a29bf0f3/home/applications/librewolf/default.nix#L2
    enable = false;
    profiles = {
      default = {
        settings = {
          "network.predictor.enable-prefetch" = true;
          "browser.compactmode.show" = true;
          "browser.uidensity" = 1;
          "browser.display.os-zoom-behavior" = 0;
          "layout.css.devPixelsPerPx" = 1.6;
          "browser.fullscreen.autohide" = false;
          "browser.newtabpage.enabled" = false;
          "browser.tabs.inTitlebar" = 0;
          "browser.translations.neverTranslateLanguages" = "de";
          "ui.key.menuAccessKeyFocuses" = false;
          "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
          # browser.urlbar.quicksuggest.scenario = "history"
          #browser.urlbar.showSearchSuggestionsFirst = false
          # browser.zoom.siteSpecific = false
          #findbar.highlightAll = true
          #layout.css.scrollbar-width-thin.disabled = true;
          #widget.gtk.overlay-scrollbars.enabled = false
          #widget.non-native-theme.scrollbar.size.override = 20
        };
        # extensions.packages =
        #   with inputs.firefox-addons.packages.${pkgs.system};
        #   [ darkreader ];
        search = {
          force = true;
          engines = {
            # don't need these default ones
            "amazondotcom-us".metaData.hidden = true;
            "bing".metaData.hidden = true;
            "ebay".metaData.hidden = true;
            "ddg" = {
              urls = [
                {
                  template = "https://duckduckgo.com";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "ddg" ];
            };
            "google" = {
              urls = [
                {
                  template = "https://google.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "g" ];
            };
            "Home Manager Options" = {
              urls = [
                {
                  template = "https://mipmip.github.io/home-manager-option-search/";
                  params = [
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "vh" ];
            };
            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "np" ];
            };
            "NixOs Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = [
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "np" ];
            };
            "youtube" = {
              urls = [
                {
                  template = "https://www.youtube.com/results";
                  params = [
                    {
                      name = "search_query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "y" ];
            };
            "Wikipedia" = {
              urls = [
                {
                  template = "https://en.wikipedia.org/wiki/Special:Search";
                  params = [
                    {
                      name = "search";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "w" ];
            };
            "GitHub" = {
              urls = [
                {
                  template = "https://github.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "gh" ];
            };
            "GitHub Code" = {
              urls = [
                {
                  template = "https://github.com/search";
                  params = [
                    {
                      name = "type";
                      value = "code";
                    }
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = [ "ghc" ];
            };
          };
          default = "ddg";
        };
      };
    };
  };
  programs.firefox = {
    # https://gitlab.com/usmcamp0811/dotfiles/-/blob/fb584a888680ff909319efdcbf33d863d0c00eaa/modules/home/apps/firefox/default.nix
    enable = false;
    profiles = {
      my-profile = { };
    };
  };
  programs.qutebrowser = {
    enable = false;
    loadAutoconfig = true;
    enableDefaultBindings = true;
    keyBindings = {
      normal = {
        "l" = "tab-next";
        "L" = "tab-prev";
        "ü" = "tab-close";
        "ä" = "close";
        "<Ctrl-f>" = "cmd-set-text /";
        "<Ctrl-t>" = "cmd-set-text --space :open -t";
        "<Ctrl-l>" = "command-accept";
        "<Ctrl-o>" = "back";
        "<Ctrl-i>" = "forward";
        "F12" = "devtools";
      };
    };
    extraConfig = ''
      config.source('config-theme.py')
    '';
  };
  programs.chromium.enable = true;

  programs.autorandr = {
    enable = true;
    profiles = {
      default = {
        fingerprint = {
          eDP-1 = "00ffffffffffff0006af362000000000001b0104a51f117802fbd5a65334b6250e505400000001010101010101010101010101010101e65f00a0a0a040503020350035ae100000180000000f0000000000000000000000000020000000fe0041554f0a202020202020202020000000fe004231343051414e30322e30200a00d2";
        };
        config = {
          eDP-1 = {
            enable = true;
            crtc = 0;
            primary = true;
            position = "0x0";
            mode = "2560x1440";
            rate = "60.01";
          };
        };
      };
      portable-monitor-left = {
        fingerprint = {
          DP-2 = "00ffffffffffff004a8bb5a501010101141e0104b5351d783fee91a3544c99260f5054210800d1c001010101950001018180010181c040d000a0f0703e803020350061632100001a000000fc004d473134302d555430310a2020000000ff0064656d6f7365742d310a203020000000fd00283d88883c010a20202020202001d702032df2529001020304131f2021223c3d3e4c5d5e5f60e200c023097f0783010000e305c000e6060501525200023a801871382d40582c250061632100001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032";
          eDP-1 = "00ffffffffffff0006af362000000000001b0104a51f117802fbd5a65334b6250e505400000001010101010101010101010101010101e65f00a0a0a040503020350035ae100000180000000f0000000000000000000000000020000000fe0041554f0a202020202020202020000000fe004231343051414e30322e30200a00d2";
        };
        config = {
          DP-2 = {
            enable = true;
            crtc = 1;
            position = "0x0";
            mode = "3840x2160";
            rate = "59.98";
          };
          eDP-1 = {
            enable = true;
            crtc = 0;
            primary = true;
            position = "3840x360";
            mode = "2560x1440";
            rate = "60.01";
          };
        };
      };
    };
    hooks.postswitch = {
      run-theme = "$HOME/bin/theme";
    };
  };

  services.keynav = {
    # TODO: https://github.com/portothree/dotfiles/blob/ef2274393816b8a2df0c8efbb80f852f9d0d20bd/config/keynav.nix#L7
    enable = false;
  };

  home.packages = with pkgs; [
    # command line fu
    # https://github.com/ibraheemdev/modern-unix
    tmux
    wget # download files
    htop # fancy top
    ncdu # disk space analyzer
    gdu # disk space analyzer
    pv # shell progress bar
    pistol # file preview
    bat # cat with syntax highlighting
    lazygit # git tui
    tig # git tui
    dasel # transform data from csv/json/... (used by theme switcher)
    jq # json parser
    feh # image viewer
    neovim-remote # send commands to neovim instances (used by theme switcher)
    trashy # put files in trash instead of deleting them
    playerctl # control media players, like spotify, vlc via cli / keybindings
    pamixer # control pulseaudio via cli / keybindings
    fd # find files by filename, alternative to `find`
    tldr # quick command examples
    comma # run nix packages without installing them
    speedtest-cli
    gh # github cli
    autorandr # automatic monitor profiles
    xsel # clipboard
    xclip # clipboard
    tmate # invite someone else into your terminal via ssh
    upterm # tmate alternative
    imagemagick
    ffmpeg-full
    mediainfo
    entr # run commands when files change
    xcolor # simple color picker
    qrencode
    duf # better df
    socat
    ripgrep-all # ripgrep, but for documents
    ngrok # remote http tunnel
    chafa # preview images
    dragon-drop # file drag and drop initiated from command line
    pandoc # convert document formats
    texliveSmall # required by pandoc
    diff-so-fancy # diff viewer. TODO: replace with delta
    kondo # clear project files
    ouch # file compression
    btop # system monitor
    # curl-impersonate # curl mocking a real browser
    helix # modal text editor
    espeak # text to speech
    whisper-cpp # audio transcription
    alsa-utils # audo recording
    timewarrior # time tracking
    nrfconnect # bluetooth ble
    typst # modern latex alternative
    pulsemixer # audio mixer tui
    bluetuith # bluetooth tui

    networkmanagerapplet
    xcwd # returns current directory of x application, used to spawn new termanals in the current directory: ~/bin/xcwd-home
    arandr # manage monitors

    # system tools
    openssl
    man
    pciutils
    usbutils
    hdparm
    gparted
    exfatprogs
    ntfs3g
    ntfsprogs
    testdisk
    lm_sensors
    linuxPackages.cpupower
    xorg.xkill
    psmisc
    wirelesstools
    xorg.xbacklight
    acpi
    samba
    cifs-utils
    # mtpfs
    jmtpfs
    file
    smem
    dnsutils
    smartmontools # hard drive diagnostics

    # defaults
    lsof
    wget
    curl
    htop
    atop
    git-fire
    moreutils # vipe, sponge
    netcat
    nmap
    calc
    tree
    inotify-tools
    zip
    unzip
    unrar
    pavucontrol
    light
    mimeo
    xdotool
    gnumake
    macchanger
    miniserve
    atool # archiver
    p7zip # compressor
    gnupg # cryptographic signing
    ghostscript # pdf (nvim)
    mermaid-cli # mermaid diagrams

    # development
    python3
    nodejs
    earthly # better Dockerfiles
    devbox # install dev tools in project
    sqlite-interactive
    visualvm
    clang # c-compiler, cc is required for nvim treesitter
    coursier # scala package manager, used to install metals
    helix # modal editor
    sccache # compile cache
    devenv # nix based dev environments
    # code-cursor # ai code editor
    # antigravity-fhs # ai code editor from google
    opencode # ai coding agent
    # cursor-cli # ai coding agent
    tree-sitter # syntax highlighting toolkit (used by nvim)
    meld # git conflict resolution ui

    # language servers/formatters/linters
    nixd # nix language server
    lua-language-server
    luarocks
    stylua
    lua
    # alejandra # nix code formatter
    nil # nix language server
    nixfmt
    statix # nix linter
    # go language server
    gopls
    # gotools
    gofumpt
    gomodifytags
    impl
    delve
    # vtsls # TODO
    tailwindcss-language-server
    nodePackages.prettier # css/js formatter
    taplo # toml language server
    docker-ls
    # llm-ls
    kotlin
    kotlin-language-server
    ktlint
    ruff # python
    pyright
    codeium # ai completion
    hadolint # docker lint
    vtsls # typescript
    vscode-langservers-extracted

    nodePackages.bash-language-server
    shellcheck # shell language server
    shfmt
    marksman # markdown language server
    markdownlint-cli2

    # themeing
    polybar # status bar
    # qogir-theme # gtk theme
    # qogir-icon-theme # gtk theme
    # tokyonight-gtk-theme
    # gtk-engine-murrine
    # gnome-themes-extra
    # sassc # gtk theme engine
    elementary-xfce-icon-theme
    xsettingsd
    lxappearance
    libsForQt5.qtstyleplugins # gtk style for qt
    libsForQt5.qt5ct
    lxappearance
    ueberzugpp # view images in terminals without sixel support
    i3lock

    # guis
    # anydesk # simple remote desktop
    google-chrome
    nemo-with-extensions # file manager
    file-roller
    vscode
    # jetbrains.idea-community-bin
    android-studio
    # jetbrains-toolbox # to install fleet editor: https://github.com/NixOS/nixpkgs/issues/242322#issuecomment-2264995861
    # (jetbrains.plugins.addPlugins jetbrains.idea-community [
    #   # https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/jetbrains/plugins/plugins.json
    #   "github-copilot"
    # ])
    # code-cursor # ai code editor
    # windsurf # ai code editor
    # zed-editor # ai code editor
    # goose-cli # cli ai agent
    # geminicommit
    inkscape # svg editor
    gcolor3
    screenkey # screencast tool to display key presses
    zoom-us # TODO
    vlc # video player
    mpv # video player
    neovide # neovim gui
    megasync # cloud file storage and sync
    krusader # file manager with good directory comparison
    keepassxc # password manager
    libsecret.out # secret-tool to retrieve secrets from keepassxc
    signal-desktop
    telegram-desktop
    spotify
    psst # alternative spotify client
    gthumb
    libreoffice
    sublime-merge
    # scribus
    # nheko # matrix client
    kvirc # irc client
    zathura # minimal pdf viewer with vim bindings
    firefox # browser
    librewolf # firefox privacy fork
    kazam
    vdhcoapp # for video download helper browser extension
    # anytype # p2p note taking
    # gitbutler # Git client for simultaneous branches on top of your existing workflow
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
