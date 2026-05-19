{
  dark = {
    plugin = "tokyonight";
    style = "moon";
    applyCommands = [
      "set background=dark"
      "colorscheme tokyonight-moon"
    ];
  };
  light = {
    plugin = "catppuccin";
    style = "latte";
    applyCommands = [
      "set background=light"
      "lua require('catppuccin').setup({ flavour = 'latte' })"
      "colorscheme catppuccin"
    ];
  };
}
