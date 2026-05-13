{
  config,
  flake-inputs,
  pkgs,
  ...
}: let
  firefoxAddons = flake-inputs.firefox-addons.packages.${pkgs.system};
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
}
