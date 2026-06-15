# pi-spezifische Extensions in den Auto-Discovery-Pfad ~/.pi/agent/extensions/
# verlinken (siehe pi-Doku: extensions.md → "Extension Locations"). Top-Level-*.ts
# werden als einzelne Extensions verlinkt; Unterverzeichnisse mit index.ts als
# mehrdateiige Extensions (pi lädt nur deren index.ts; engine.ts/feed.ts/*.test.ts
# bleiben inert). Bearbeitung im Repo + Home-Manager-Switch; danach `/reload` in pi.
{lib, ...}: let
  dir = ./pi-extensions;
  # Extensions, die zwar im Repo liegen, aber nicht verlinkt (= nicht von pi
  # geladen) werden sollen. Name = Top-Level-Dateiname bzw. Unterverzeichnisname.
  disabled = ["actor-swarm"];
  entries = lib.filterAttrs (name: _: !(builtins.elem name disabled)) (builtins.readDir dir);

  # Top-Level *.ts -> ~/.pi/agent/extensions/<name>
  files =
    lib.mapAttrs' (name: _: {
      name = ".pi/agent/extensions/${name}";
      value.source = dir + "/${name}";
    })
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".ts" name) entries);

  # Unterverzeichnisse mit index.ts -> ~/.pi/agent/extensions/<dir>
  subdirs =
    lib.mapAttrs' (name: _: {
      name = ".pi/agent/extensions/${name}";
      value.source = dir + "/${name}";
    })
    (lib.filterAttrs
      (name: type: type == "directory" && builtins.pathExists (dir + "/${name}/index.ts"))
      entries);
in {
  home.file = files // subdirs;
}
