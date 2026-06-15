# pi-spezifische Extensions in den Auto-Discovery-Pfad ~/.pi/agent/extensions/
# verlinken (siehe pi-Doku: extensions.md → "Extension Locations"). Jede *.ts aus
# ./pi-extensions/ wird als read-only In-Store-Symlink ausgelegt, analog zu
# skills.nix. Bearbeitung im Repo + Home-Manager-Switch; danach `/reload` in pi.
{lib, ...}: let
  dir = ./pi-extensions;
  linkExtensions =
    lib.mapAttrs' (name: _: {
      name = ".pi/agent/extensions/${name}";
      value.source = dir + "/${name}";
    })
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".ts" name)
      (builtins.readDir dir));
in {
  home.file = linkExtensions;
}
