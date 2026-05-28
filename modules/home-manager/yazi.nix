{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkMerge [
  {
    programs.yazi = {
      enable = true;
      enableZshIntegration = true;
      shellWrapperName = "n"; # switches directory in shell when exiting yazi

      settings = {
        mgr = {
          ratio = [
            0
            5
            5
          ];
          sort_dir_first = true;
          sort_by = "mtime";
          sort_reverse = true;
          linemode = "size_and_mtime";
          show_hidden = true;
        };
        preview = {
          max_width = 1280;
        };
        plugin = {
          prepend_fetchers = [
            {
              id = "git";
              group = "git";
              url = "*";
              run = "git";
            }
            {
              id = "git";
              group = "git";
              url = "*/";
              run = "git";
            }
          ];
          prepend_previewers = [
            {
              url = "*.parquet";
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
        mgr = {
          preview_hovered = {
            underline = false;
          };
        };
      };

      plugins = {
        inherit
          (pkgs.yaziPlugins)
          git
          starship
          vcs-files
          ;
      };

      initLua = ''
        function Linemode:size_and_mtime()
          local time = math.floor(self._file.cha.mtime or 0)
          if time == 0 then
            time = ""
          elseif os.date("%Y", time) == os.date("%Y") then
            time = os.date("%b %d %H:%M", time)
          else
            time = os.date("%b %d  %Y", time)
          end

          local size = self._file:size()
          return string.format("%s %s", size and ya.readable_size(size) or "", time)
        end

          th.git = th.git or {}
          th.git.clean_sign = "  "
          th.git.ignored = ui.Style():fg("darkgray"):dim()
          th.git.ignored_sign = "◌ "
          th.git.unknown_sign = "  "

          require("git"):setup({ order = 1500 })
          require("starship"):setup()
      '';

      keymap = let
        homeDir = config.home.homeDirectory;
        username = config.home.username;
        shortcuts = {
          h = homeDir;
          p = "${homeDir}/projects";
          d = "${homeDir}/downloads";
          o = "${homeDir}/documents";
          c = "${homeDir}/.config";
          m = "${homeDir}/MEGAsync";
          s = "${homeDir}/screenshots";
          D = "${homeDir}/Downloads";
          r = "/run/media/${username}";
        };
      in {
        mgr.prepend_keymap =
          [
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
              on = [
                "g"
                "C"
              ];
              run = "plugin vcs-files";
              desc = "Show changed files in current git repo";
            }
            {
              on = ["C"];
              run = "plugin ouch";
              desc = "Compress with ouch";
            }
          ]
          ++ lib.flatten (
            lib.mapAttrsToList (keys: loc: [
              # cd
              {
                on = ["g"] ++ lib.stringToCharacters keys;
                run = "cd ${loc}";
                desc = "cd to ${loc}";
              }
              # new tab
              {
                on = ["t"] ++ lib.stringToCharacters keys;
                run = "tab_create ${loc}";
                desc = "open new tab to ${loc}";
              }
            ])
            shortcuts
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
