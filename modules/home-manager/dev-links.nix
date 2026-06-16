# Temporärer Dev-Link-Schalter: gelistete repo-relative Pfade werden out-of-store
# ans Working Tree gelinkt (schnelles Feedback ohne Rebuild pro Edit), statt aus
# dem Store gepinnt. Default leer = voll reproduzierbar. Siehe
# docs/superpowers/specs/2026-06-16-dev-links-design.md.
#
# `mkDevSource relPath storePath` liefert den `source`-Wert für home.file/
# xdg.configFile: gelistet -> mkOutOfStoreSymlink, sonst die gepinnte Store-Quelle.
{
  config,
  lib,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
in {
  options.my.devLinks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    example = ["modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts"];
    description = ''
      Repo-relative Pfade (ab Repo-Wurzel), die temporär out-of-store ans
      Working Tree gelinkt werden statt aus dem Store. Für schnelles Feedback
      während der Entwicklung; nach Stabilisierung wieder entfernen.
    '';
  };

  config._module.args.mkDevSource = relPath: storePath:
    if builtins.elem relPath config.my.devLinks
    then config.lib.file.mkOutOfStoreSymlink "${repoDir}/${relPath}"
    else storePath;
}
