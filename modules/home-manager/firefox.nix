{
  config,
  flake-inputs,
  lib,
  pkgs,
  ...
}: let
  firefoxAddons = flake-inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
  extensionXpi = addon: "${addon}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addon.addonId}.xpi";
  managedExtensions = with firefoxAddons; [
    consent-o-matic
    ctrl-number-to-switch-tabs
    darkreader
    facebook-container
    keepassxc-browser
    localcdn
    multi-account-containers
    refined-github
    skip-redirect
    ublock-origin
    vimium
  ];
  profilePath = "${config.home.homeDirectory}/.mozilla/firefox/pcakttgr.default-default";
  ensureKeyword = keyword: url: ''
    DELETE FROM moz_keywords
      WHERE keyword = '${keyword}'
         OR place_id IN (SELECT id FROM moz_places WHERE url = '${url}');
    INSERT INTO moz_keywords (keyword, place_id, post_data)
      SELECT '${keyword}', id, NULL FROM moz_places WHERE url = '${url}' LIMIT 1;
  '';
  bookmarkKeywordSql = pkgs.writeText "firefox-bookmark-keywords.sql" ''
    PRAGMA foreign_keys = ON;
    BEGIN IMMEDIATE;
    ${ensureKeyword "blend" "https://fdietze.github.io/blend/"}
    ${ensureKeyword "cal" "https://calendar.google.com/calendar/u/0/r"}
    ${ensureKeyword "dkb" "https://www.dkb.de/banking"}
    ${ensureKeyword "gm" "https://mail.google.com/mail/u/0/#inbox"}
    ${ensureKeyword "todo" "https://to-do.live.com/tasks/AQMkADAwATNiZmYAZC04NGQ3LTIwZjgtMDACLTAwCgAuAAAD3baDRxAbx0_y4oq963F-OgEAsXRJSnW4pka7P111dILhqAAGgNCMBQAAAA=="}
    COMMIT;
  '';
in {
  stylix.targets.firefox = {
    enable = true;
    profileNames = ["default-default"];
  };

  programs.firefox = {
    # https://gitlab.com/usmcamp0811/dotfiles/-/blob/fb584a888680ff909319efdcbf33d863d0c00eaa/modules/home/apps/firefox/default.nix
    enable = true;
    configPath = ".mozilla/firefox";
    policies = {
      Extensions.Install = map extensionXpi managedExtensions;
    };
    profiles = {
      "default-default" = {
        id = 0;
        name = "default-default";
        path = "pcakttgr.default-default";
        isDefault = true;
        settings = {
          "accessibility.typeaheadfind.enablesound" = false;
          "accessibility.typeaheadfind.flashBar" = 0;
          "browser.download.autohideButton" = false;
          "browser.download.dir" = config.xdg.userDirs.download;
          "browser.download.folderList" = 2;
          "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
          "browser.newtabpage.activity-stream.showSearch" = false;
          "browser.newtabpage.enabled" = false;
          "browser.search.separatePrivateDefault.urlbarResult.enabled" = false;
          "browser.search.suggest.enabled" = false;
          "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
          "browser.tabs.inTitlebar" = 0;
          "browser.theme.toolbar-theme" = 2;
          "browser.theme.content-theme" = 2;
          "browser.urlbar.showSearchSuggestionsFirst" = false;
          "font.default.x-western" = "sans-serif";
          "layout.css.devPixelsPerPx" = "1.6";
          "layout.css.dpi" = 0;
          "layout.css.scrollbar-width-thin.disabled" = true;
          "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;
          "network.trr.excluded-domains" = "login.wifionice.de";
          "network.trr.mode" = 3;
          "network.trr.uri" = "https://mozilla.cloudflare-dns.com/dns-query";
          "privacy.clearOnShutdown_v2.formdata" = true;
          "privacy.userContext.enabled" = true;
          "privacy.userContext.longPressBehavior" = 2;
          "privacy.userContext.ui.enabled" = true;
          "signon.rememberSignons" = false;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };
        search = {
          force = true;
          default = "ddg";
          privateDefault = "ddg";
          order = [
            "ddg"
            "google"
            "Google Maps"
            "Home Manager Options"
            "Nix Packages"
            "NixOS Options"
            "youtube"
            "Wikipedia"
            "GitHub"
            "GitHub Code"
          ];
          engines = {
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
              definedAliases = ["ddg"];
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
              definedAliases = ["g"];
            };
            "Google Maps" = {
              urls = [
                {
                  template = "https://www.google.com/maps/search/{searchTerms}";
                }
              ];
              definedAliases = ["m"];
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
              definedAliases = ["vh"];
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
              definedAliases = ["np"];
            };
            "NixOS Options" = {
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
              definedAliases = ["no"];
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
              definedAliases = ["y"];
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
              definedAliases = ["w"];
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
              definedAliases = ["gh"];
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
              definedAliases = ["ghc"];
            };
          };
        };
      };
    };
  };

  home.activation.firefoxBookmarkKeywords = lib.hm.dag.entryAfter ["writeBoundary"] ''
    profile=${lib.escapeShellArg profilePath}
    places="$profile/places.sqlite"

    if [[ -e "$profile/lock" || -e "$profile/.parentlock" ]]; then
      echo "Skipping Firefox bookmark keyword migration because Firefox appears to be running."
    elif [[ ! -w "$places" ]]; then
      echo "Skipping Firefox bookmark keyword migration because $places is not writable."
    else
      ${pkgs.sqlite}/bin/sqlite3 "$places" < ${bookmarkKeywordSql}
    fi
  '';
}
