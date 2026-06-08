{...}: {
  imports = [
    ../../modules/home-manager/shared.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/desktops/gnome.nix
    ../../modules/home-manager/desktops/herbstluftwm.nix
    ../../modules/home-manager/desktops/noctalia-niri.nix
    # NVF Neovim configuration explicitly enabled for this host.
    ../../modules/home-manager/nvf.nix
  ];
}
