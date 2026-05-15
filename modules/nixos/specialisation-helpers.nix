{
  lib,
}:
let
  desktopRegistry = import ../desktop-registry.nix;
  inherit (desktopRegistry) themes themedDesktops unthemedDesktops;
  base16 = import ../themes/base16.nix;

  hasThemeVariants = desktop: builtins.elem desktop themedDesktops;

  specialisationName =
    {
      desktop,
      theme ? null,
    }:
    if hasThemeVariants desktop then "${desktop}-${theme}" else desktop;

  switchToConfigurationCommand =
    name: "/nix/var/nix/profiles/system/specialisation/${name}/bin/switch-to-configuration switch";

  mkDesktopSpecialisation =
    {
      desktop,
      theme ? null,
      extraConfig ? { },
    }:
    let
      name = specialisationName { inherit desktop theme; };
      myConfig =
        if hasThemeVariants desktop then
          {
            my = {
              desktop = lib.mkForce desktop;
              theme = lib.mkForce theme;
            };
          }
        else
          { my.desktop = lib.mkForce desktop; };
    in
    lib.nameValuePair name {
      configuration = myConfig // extraConfig;
    };

  mkThemedSpecialisation =
    desktop: theme:
    mkDesktopSpecialisation {
      inherit desktop theme;
      extraConfig = lib.optionalAttrs (theme == "light") {
        stylix = {
          polarity = lib.mkForce "light";
          base16Scheme = base16.light;
        };
      };
    };

  themedSpecialisations = lib.concatMap (
    desktop: map (mkThemedSpecialisation desktop) themes
  ) themedDesktops;

  unthemedSpecialisations = map (
    desktop: mkDesktopSpecialisation { inherit desktop; }
  ) unthemedDesktops;

  specialisationNames =
    (lib.concatMap (
      desktop:
      map (
        theme:
        specialisationName {
          inherit desktop theme;
        }
      ) themes
    ) themedDesktops)
    ++ unthemedDesktops;
in
{
  inherit desktopRegistry hasThemeVariants specialisationName;

  sudoSwitchCommands = map switchToConfigurationCommand specialisationNames;
  specialisations = lib.listToAttrs (themedSpecialisations ++ unthemedSpecialisations);
}
