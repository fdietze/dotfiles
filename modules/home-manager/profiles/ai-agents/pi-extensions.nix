# pi-spezifische Extensions in den Auto-Discovery-Pfad ~/.pi/agent/extensions/
# verlinken (siehe pi-Doku: extensions.md → "Extension Locations"). Top-Level-*.ts
# werden als einzelne Extensions verlinkt; Unterverzeichnisse mit index.ts als
# mehrdateiige Extensions (pi lädt nur deren index.ts; engine.ts/feed.ts/*.test.ts
# bleiben inert). Bearbeitung im Repo + Home-Manager-Switch; danach `/reload` in pi.
#
# Quelle pro Extension via mkDevSource: per my.devLinks gelistete Pfade werden
# out-of-store ans Working Tree gelinkt (schnelles Feedback), sonst Store.
{
  lib,
  mkDevSource,
  ...
}: let
  dir = ./pi-extensions;
  # Repo-relativer Präfix dieses Verzeichnisses (Matching-Key für my.devLinks).
  relRoot = "modules/home-manager/profiles/ai-agents/pi-extensions";
  entries = builtins.readDir dir;

  mkEntry = name: {
    name = ".pi/agent/extensions/${name}";
    value.source = mkDevSource "${relRoot}/${name}" (dir + "/${name}");
  };

  # Top-Level *.ts -> ~/.pi/agent/extensions/<name>
  files =
    lib.mapAttrs' (name: _: mkEntry name)
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".ts" name) entries);

  # Unterverzeichnisse mit index.ts -> ~/.pi/agent/extensions/<dir>
  subdirs =
    lib.mapAttrs' (name: _: mkEntry name)
    (lib.filterAttrs
      (name: type: type == "directory" && builtins.pathExists (dir + "/${name}/index.ts"))
      entries);
in {
  home.file = files // subdirs;
}
