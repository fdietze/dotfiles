{
  pkgs,
  lib,
  config,
  ...
}:
let
  # yazi-plugins = pkgs.fetchFromGitHub {
  #   owner = "yazi-rs";
  #   repo = "plugins";
  #   rev = "139c36e4a77660b85fd919b1c813257c938f3db3";
  #   hash = "sha256-84lrFEdJ2oqEaZj5VfLU1HLrvX6LziWo+HtKNT2JErw=";
  # };
  # mkYaziPlugin = name: text: {
  #   "${name}" = toString (pkgs.writeTextDir "${name}.yazi/init.lua" text)
  #     + "/${name}.yazi";
  # };
in
lib.mkMerge [
  {
    programs.yazi = {
      enable = true;
      enableZshIntegration = true;
      shellWrapperName = "n"; # switches directory in shell when exiting yazi

      settings = {
        manager = {
          ratio = [
            0
            5
            5
          ];
          sort_dir_first = true;
          sort_by = "mtime";
          sort_reverse = true;
          linemode = "mtime";
          show_hidden = true;
        };
        preview = {
          max_width = 1280;
        };
        plugin = {
          # prepend_fetchers = [
          #   {
          #     id = "git";
          #     name = "*";
          #     run = "git";
          #   }
          #   {
          #     id = "git";
          #     name = "*/";
          #     run = "git";
          #   }
          # ];
          prepend_previewers = [
            {
              name = "*.parquet";
              run = "${pkgs.pqrs}/bin/pqrs head";
            }
            # Archive previewer
            {
              mime = "application/*zip";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/x-tar";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/x-bzip2";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/x-7z-compressed";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/x-rar";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/x-xz";
              run = "${pkgs.ouch}/bin/ouch";
            }
            {
              mime = "application/xz";
              run = "${pkgs.ouch}/bin/ouch";
            }
            # {name = "*.parquet"; run = "${pkgs.pqrs}/bin/pqrs head";}
            # {name = "*.parquet"; run = "file";}
          ];
        };
        opener = {
          # https://yazi-rs.github.io/docs/configuration/yazi#opener
          image = [
            {
              run = "${pkgs.feh}/bin/feh --auto-zoom --scale-down \"$@\"";
              for = "unix"; # feh is a Unix utility
              desc = "Open with feh (auto-zoom, scale-down)";
              orphan = true; # Run feh in the background, detached from yazi
              block = false; # Don't block yazi while feh is running
            }
          ];
        };
        open = {
          prepend_rules = [
            {
              mime = "image/*";
              use = "image";
            }
          ];
        };
      };

      theme = {
        manager = {
          preview_hovered = {
            underline = false;
          };
        };
      };

      plugins = {
        # git = "${yazi-plugins}/git.yazi";
        # max-preview = "${yazi-plugins}/max-preview.yazi";
        starship = pkgs.fetchFromGitHub {
          # https://github.com/Rolv-Apneseth/starship.yazi
          owner = "Rolv-Apneseth";
          repo = "starship.yazi";
          rev = "6c639b474aabb17f5fecce18a4c97bf90b016512";
          sha256 = "sha256-0J6hxcdDX9b63adVlNVWysRR5htwAtP5WhIJ2AK2+Gs=";
        };
      };

      # initLua = ''
      #   require("git"):setup()
      #   require("starship"):setup()
      # '';

      keymap =
        let
          homeDir = config.home.homeDirectory;
          username = config.home.username;
          shortcuts = {
            h = homeDir;
            p = "${homeDir}/projects";
            d = "${homeDir}/downloads";
            m = "${homeDir}/MEGAsync";
            s = "${homeDir}/screenshots";
            D = "${homeDir}/Downloads";
            r = "/run/media/${username}";
          };
        in
        {
          manager.prepend_keymap = [
            {
              on = "O"; # like tig
              run = "plugin --sync max-preview";
              desc = "Maximize or restore the preview pane";
            }
            {
              on = "ä"; # neo layout
              run = "quit";
              desc = "quit";
            }
            # close input by a single Escape press
            {
              on = "<Esc>";
              run = "close";
              desc = "Cancel input";
            }
            # cd back to root of current git repo
            {
              on = [
                "g"
                "r"
              ];
              run = ''shell 'ya pub dds-cd --str "$(git rev-parse --show-toplevel)"' --confirm'';
              desc = "Cd to root of current git repo";
            }
            {
              on = [ "C" ];
              run = "plugin ouch";
              desc = "Compress with ouch";
            }
          ]
          ++ lib.flatten (
            lib.mapAttrsToList (keys: loc: [
              # cd
              {
                on = [ "g" ] ++ lib.stringToCharacters keys;
                run = "cd ${loc}";
                desc = "cd to ${loc}";
              }
              # new tab
              {
                on = [ "t" ] ++ lib.stringToCharacters keys;
                run = "tab_create ${loc}";
                desc = "open new tab to ${loc}";
              }
            ]) shortcuts
          );
          help.prepend_keymap = [
            {
              on = "ä"; # neo layout
              run = "quit";
              desc = "quit";
            }
          ];
        };
    };

  }
  # smart-enter: enter for directory, open for file
  # https://yazi-rs.github.io/docs/tips/#smart-enter
  # {
  #   programs.yazi = {
  #     plugins = mkYaziPlugin "smart-enter" ''
  #       return {
  #       	entry = function()
  #           local h = cx.active.current.hovered
  #           ya.manager_emit(h and h.cha.is_dir and "enter" or "open", { hovered = true })
  #         end,
  #       }
  #     '';
  #     keymap.manager.prepend_keymap = [{
  #       on = "<Enter>";
  #       run = "plugin --sync smart-enter";
  #       desc = "Enter the child directory, or open the file";
  #     }];
  #   };
  # }

  # smart-paste: paste files without entering the directory
  # https://yazi-rs.github.io/docs/tips/#smart-paste
  # {
  #   programs.yazi = {
  #     plugins = mkYaziPlugin "smart-paste" ''
  #       return {
  #         entry = function()
  #           local h = cx.active.current.hovered
  #           if h and h.cha.is_dir then
  #             ya.manager_emit("enter", {})
  #             ya.manager_emit("paste", {})
  #             ya.manager_emit("leave", {})
  #           else
  #             ya.manager_emit("paste", {})
  #           end
  #         end,
  #       }
  #     '';
  #     keymap.manager.prepend_keymap = [{
  #       on = "p";
  #       run = "plugin --sync smart-paste";
  #       desc = "Paste into the hovered directory or CWD";
  #     }];
  #   };
  # }
]
