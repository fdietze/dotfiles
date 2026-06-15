# Agent-Skills in den geteilten, harness-agnostischen Ordner ~/.agents/skills/
# verlinken. Das ist der Standardpfad des Agent Skills Standards, den alle Agents
# lesen: pi direkt, claude über den Symlink ~/.claude/skills -> ~/.agents/skills,
# codex/opencode über ihre skills-Konfig.
#
# Zwei Quellen, beide als read-only In-Store-Symlinks:
#   * superpowers (obra/superpowers) — Upstream, als Flake-Input gepinnt
#     (flake.lock). Update via `nix flake update superpowers`.
#   * ./skills/ — eigene, handgepflegte Skills im Repo. Bearbeitung im Repo +
#     Home-Manager-Switch (wie alle anderen dotfiles auch).
#
# Jedes Skill-Verzeichnis wird einzeln (eine Ebene tief) verlinkt — maximale
# Kompatibilität, da manche Harnesses nur top-level <skill>/SKILL.md entdecken.
{
  lib,
  flake-inputs,
  ...
}: let
  # Symlinks ~/.agents/skills/<name> -> <dir>/<name> für jedes Unterverzeichnis.
  linkSkills = dir:
    lib.listToAttrs (map (name: {
        name = ".agents/skills/${name}";
        value.source = dir + "/${name}";
      })
      (builtins.attrNames
        (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir))));
in {
  home.file = linkSkills (flake-inputs.superpowers + "/skills") // linkSkills ./skills;
}
