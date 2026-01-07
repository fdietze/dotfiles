{ pkgs, ... }:
{
  home.shellAliases = {
    g = "git";
    gs = "git status";
    gb = "git branch";
    gu = "sec && git up";
    gp = "sec && git p";
    gpf = "sec && git pf";
    gh = "sec && gh"; # github cli
    gl = "git lg";
    gla = "git lga";
    gdf = "git df --no-index";
    tig = "tig status";
  };

  programs.git = {
    # enable = true;
    # userName = "Felix Dietze";
    # userEmail = "github@felx.me";
    difftastic = {
      enable = true;
    };
  };

  programs.difftastic = {
    git.enable = true;
    options = {
      display = "inline";
    };
  };
}
