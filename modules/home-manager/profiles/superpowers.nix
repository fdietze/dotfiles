# Superpowers-Skills (obra/superpowers) in den geteilten, harness-agnostischen
# Skill-Ordner ~/.agents/skills/ verlinken. Das ist der Standardpfad des Agent
# Skills Standards, den alle Agents lesen: pi direkt, claude über den Symlink
# ~/.claude/skills -> ~/.agents/skills, codex/opencode über ihre skills-Konfig.
#
# Jedes Skill-Verzeichnis wird einzeln (eine Ebene tief) verlinkt — maximale
# Kompatibilität, da manche Harnesses nur top-level <skill>/SKILL.md entdecken.
# Die hand-gepflegten Skills in ~/.agents/skills/ (project-setup, ...) bleiben
# unberührt, weil Home Manager nur die hier erzeugten Pfade besitzt.
#
# Quelle ist als Flake-Input gepinnt (flake.lock); Update via
# `nix flake update superpowers`.
{
  lib,
  flake-inputs,
  ...
}: let
  skillsDir = flake-inputs.superpowers + "/skills";
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
in {
  home.file =
    lib.listToAttrs (map (name: {
        name = ".agents/skills/${name}";
        value.source = skillsDir + "/${name}";
      })
      skillNames);
}
