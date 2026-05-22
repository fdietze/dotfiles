# https://mipmip.github.io/home-manager-option-search/
{
  config,
  lib,
  pkgs,
  theme,
  uiFonts,
  ...
}:
let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
in
{
  imports = [
    ./shell.nix
    ./dotfiles.nix
    ./git.nix
    ./yazi.nix
    ./xdg.nix
    ./packages.nix
    ./stylix.nix
    ./theme-switching.nix
    ./wallpaper.nix
    # ./home/dictate.nix
    ./nvf.nix
  ];

  # https://nix-community.github.io/home-manager/index.xhtml
  home.username = "felix";
  home.homeDirectory = "/home/felix";

  home.sessionPath = [
    # Keep personal scripts live-editable without requiring a Home Manager switch.
    "${repoDir}/home/bin"
    "$HOME/bin"
    "$HOME/.cargo/bin"
    "$HOME/.npm-packages/bin"
  ];

  # home.sessionCommand

  home.sessionVariables = {
    CLICOLOR_FORCE = 1; # ANSI colors should be enabled no matter what. (https://bixense.com/clicolors/)

    BROWSER = "${pkgs.firefox}/bin/firefox";
    # BROWSER = "${pkgs.librewolf}/bin/librewolf";
    PAGER = "less --RAW-CONTROL-CHARS"; # less with colors

    # colorize less
    LESS = "--use-color --RAW-CONTROL-CHARS --incsearch --ignore-case --redraw-on-quit --mouse --wheel-lines=3";

    MOZ_USE_XINPUT2 = 1; # fix firefox scrolling, enable touchpad gestures

    # QT_QPA_PLATFORMTHEME = "gtk2"; # let qt apps use gtk 2 themes
    # QT_AUTO_SCREEN_SCALE_FACTOR = 1; # honor screen DPI
  };

  programs.bat.enable = true;
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = { }; # don't generate direnv.toml and use the existing one instead
  };

  home.shell = {
    enableIonIntegration = true;
  };

  home.shellAliases = {
    # /home/felix.old-2024-03-01/.aliases
    # /home/felix.old-2024-03-01/.sh_aliases

    # incubator
    s = "${pkgs.ddgr}/bin/ddgr";
    vf = ''$EDITOR "$HOME"/projects/dotfiles/flake.nix'';
    vt = ''$EDITOR "$HOME"/MEGAsync/notes/todo.md'';
    lg = "lazygit";
    nrb = "sudo nixos-rebuild boot";
    t1a = "exa --tree --color=always -L 1 -a";
    t2a = "exa --tree --color=always -L 2 -a";
    t3a = "exa --tree --color=always -L 3 -a";
    cat = "bat -n --paging=never";
    cd = "z";
    # rm = "${pkgs.trashy}/bin/trash put";
    sec = "source ${repoDir}/home/bin/secret-envs";
    # aider = "sec && ${pkgs.aider-chat}/bin/aider --no-check-update";
    alors = "sec && alors";
    opencode = "sec && opencode";
    oc = "sec && opencode";
    c = "sec && opencode --agent 'chat' ";
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
              --action '${pkgs.trashy}/bin/trash put %F && ${pkgs.libnotify}/bin/notify-send -a feh -t 1500 "Trashed" "%n"' \
              --action1 ';mkdir -p 1 && cp %F 1/ && ${pkgs.libnotify}/bin/notify-send -a feh -t 1500 "Copied to 1" "%n"' \
              --action2 ';mkdir -p 2 && cp %F 2/ && ${pkgs.libnotify}/bin/notify-send -a feh -t 1500 "Copied to 2" "%n"' \
              --action3 ';mkdir -p 3 && cp %F 3/ && ${pkgs.libnotify}/bin/notify-send -a feh -t 1500 "Copied to 3" "%n"' \
    '';
    zed = "sec && ${pkgs.zed-editor}/bin/zeditor";
    # gemini = "sec && gemini";
    # gmc = "geminicommit";
    signal-desktop = ''sec && signal-desktop --password-store="gnome-libsecret"'';

    ##################
    # well established
    dc = "docker-compose";

    vim = "nvim";

    v = ''nvim -c "FzfLua files"'';
    vg = ''nvim -c "FzfLua live_grep"'';
    vr = ''nvim -c "FzfLua oldfiles"''; # recently used files
    p = "cd $(select-project)";

    ls = "${pkgs.eza}/bin/eza --all --group-directories-first";
    l = "${pkgs.eza}/bin/eza -l";
    la = "${pkgs.eza}/bin/eza -la";
    lt = "${pkgs.eza}/bin/eza -l --sort newest";
    lta = "${pkgs.eza}/bin/eza -la --sort newest";
    t = "${pkgs.eza}/bin/eza --tree --color=always";
    ta = "${pkgs.eza}/bin/eza --tree --color=always -a";
    t1 = "${pkgs.eza}/bin/eza --tree --color=always -L 1";
    t2 = "${pkgs.eza}/bin/eza --tree --color=always -L 2";
    t3 = "${pkgs.eza}/bin/eza --tree --color=always -L 3";
    tg = "tree-git";
    vv = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/nvf.nix'';
    vn = ''$EDITOR "$HOME"/projects/dotfiles/hosts/gurke/default.nix'';
    vh = ''$EDITOR "$HOME"/projects/dotfiles/hosts/gurke/home.nix'';
    vp = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/packages.nix'';
    vb = ''$EDITOR "$HOME"/.config/polybar/config.ini'';
    nrs = "nrs";
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

  programs.ion = {
    # currently missing: I-Beam cursor in insert mode
    enable = true;
    shellAliases = config.home.shellAliases;
    initExtra = ''
      keybindings vi
    '';
  };

  # programs.command-not-found.enable = true;
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  services.podman.enable = true;

  programs.fish = {
    enable = false;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
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
      font-family = uiFonts.monospace.name;
      font-size = uiFonts.sizes.terminal;
      confirm-close-surface = false; # don't confirm to close when a command is running
    };
  };
  programs.alacritty = {
    enable = true;
    settings = {
      terminal.osc52 = "CopyPaste";
      # font = {
      #   normal.family = uiFonts.monospace.name;
      #   size = uiFonts.sizes.terminal;
      # };
      scrolling.history = 100000;
      window.padding.x = 2;
      cursor.style = {
        blinking = "Never";
        shape = "Beam";
      };
      # general.import = ["~/.config/alacritty/theme.toml"];
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
  programs.kitty = {
    enable = false;
  };
  programs.wezterm = {
    enable = true;
    package = pkgs.wezterm.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ./patches/wezterm-pr4991-fix-additional-emit.patch
        ];
    });
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
        enable_kitty_keyboard = true,
      }
    '';
  };
  # programs.helix.enable = false;
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

  services.espanso = {
    # https://github.com/espanso/espanso
    enable = true;
    configs = {
      default = {
        show_notifications = false;
      };
    };
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

  # Bluetooth is managed on demand via Polybar and Overskride, avoiding a tray
  # applet that keeps waking up during otherwise idle sessions.
  services.blueman-applet.enable = false;
  # NixOS' blueman package still exports an XDG autostart file for
  # blueman-applet; a user-level Hidden entry masks it for this session.
  xdg.configFile."autostart/blueman.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Blueman Applet
    Hidden=true
  '';
  services.mpris-proxy.enable = true; # bluetooth buttons

  programs.keepassxc = {
    autostart = true;
    enable = true;
    settings = {
      # For available settings, see https://github.com/keepassxreboot/keepassxc/blob/develop/src/core/Config.cpp
      General = {
        AutoReloadOnChange = true;
        AutoSaveAfterEveryChange = true;
        AutoSaveOnExit = true;
        AutoTypeDelay = 25;
        AutoTypeEntryTitleMatch = true;
        AutoTypeEntryURLMatch = true;
        AutoTypeStartDelay = 500;
        BackupBeforeSave = false;
        ConfigVersion = 2;
        DropToBackgroundOnCopy = false;
        FaviconDownloadTimeout = 10;
        GlobalAutoTypeKey = 0;
        GlobalAutoTypeModifiers = 0;
        HideWindowOnCopy = false;
        MinimizeAfterUnlock = false;
        MinimizeOnCopy = true;
        MinimizeOnOpenUrl = false;
        OpenPreviousDatabasesOnStartup = true;
        RememberLastDatabases = true;
        RememberLastKeyFiles = true;
        SingleInstance = true;
        UseAtomicSaves = true;
        UseGroupIconOnEntryCreation = true;
      };

      Browser = {
        AllowExpiredCredentials = false;
        AlwaysAllowAccess = true;
        AlwaysAllowUpdate = true;
        BestMatchOnly = true;
        CustomProxyLocation = "";
        Enabled = true;
        HttpAuthPermission = false;
        MatchUrlScheme = false;
        NoMigrationPrompt = false;
        SearchInAllDatabases = true;
        ShowNotification = true;
        SortByUsername = true;
        SupportBrowserProxy = true;
        SupportKphFields = true;
        UnlockDatabase = true;
        UpdateBinaryPath = false; # Home Manager manages the native messaging manifest.
        UseCustomProxy = false;
      };

      FdoSecrets = {
        ConfirmAccessItem = false;
        Enabled = true;
        NoConfirmDeleteItem = false;
        ShowNotification = true;
      };

      GUI = {
        ApplicationTheme = "auto";
        CheckForUpdates = false;
        CheckForUpdatesIncludeBetas = false;
        CompactMode = true;
        HidePreviewPanel = false;
        HideToolbar = false;
        HideUsernames = false;
        Language = "system";
        MinimizeOnClose = false;
        MinimizeOnStartup = false;
        MinimizeToTray = false;
        MonospaceNotes = true;
        MovableToolbar = false;
        ShowTrayIcon = false;
        ToolButtonStyle = 0;
        TrayIconAppearance = "monochrome-light";
      };

      PasswordGenerator = {
        AdditionalChars = "";
        AdvancedMode = true;
        EnsureEvery = true;
        ExcludeAlike = false;
        ExcludedChars = "";
        Length = 64;
        Logograms = true;
        Math = false;
        SpecialChars = true;
      };

      SSHAgent.Enabled = true;

      Security = {
        ClearClipboardTimeout = 20;
        IconDownloadFallback = true;
        LockDatabaseIdleSeconds = 3600;
      };
    };
  };

  # systemd.user.services.keepassxc = {
  #   Unit = {
  #     Description = "KeePassXC password manager";
  #     PartOf = ["graphical-session.target"];
  #     After = ["graphical-session.target"];
  #   };
  #   Service = {
  #     ExecStart = "${pkgs.keepassxc}/bin/keepassxc";
  #     Restart = "on-failure";
  #   };
  # };

  # services.syncthing.enable = true;

  # services.megasync.enable = true;

  gtk = {
    enable = true;
    iconTheme = {
      # Prefer Adwaita's symbolic status icons for tray clients. Polybar's
      # tray-foreground is only a protocol hint, so the GTK icon theme is the
      # stronger declarative source for monochrome-capable apps.
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    theme = {
      # Force the polarity-matched adw-gtk3 variant; Stylix's gtk target sets
      # `adw-gtk3` (the light/base variant) and would otherwise win/conflict.
      # Stylix's base16 recolor is applied via gtk.css on top of this base.
      name = lib.mkForce (if theme == "light" then "adw-gtk3" else "adw-gtk3-dark");
      package = lib.mkForce pkgs.adw-gtk3;
    };
  };

  # gtk.cursorTheme = {
  #   name = "Vanilla-DMZ";
  #   # size = 64;
  # };

  home.pointerCursor = {
    x11.enable = true;
    gtk.enable = true;
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

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
  # programs.ssh = {
  #   enable = true;
  # };

  services.ssh-agent.enable = true;

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

  services.keynav = {
    # TODO: https://github.com/portothree/dotfiles/blob/ef2274393816b8a2df0c8efbb80f852f9d0d20bd/config/keynav.nix#L7
    enable = false;
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "26.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
