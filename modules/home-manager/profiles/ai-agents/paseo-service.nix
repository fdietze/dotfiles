# Geteilter systemd-User-Service für den Paseo-Daemon.
# Erlaubt das Starten des Daemons auf der Tailscale-IP (tailscale0), wahlweise
# automatisch beim Boot/Login (wie auf cubie) oder rein manuell on-demand (wie auf gurke).
{
  config,
  lib,
  pkgs,
  flake-inputs,
  ...
}: let
  cfg = config.services.paseo-daemon;

  paseoPkg = flake-inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.paseo;

  # Resolvt die tailscale0 IPv4 beim Start und bindet den Daemon nur daran.
  # Wartet bis zu 120s, falls das Interface noch keine IP hat.
  paseoStart = pkgs.writeShellScript "paseo-daemon-start" ''
    set -eu
    ip=""
    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show tailscale0 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{print $4}' | ${pkgs.coreutils}/bin/cut -d/ -f1)
      [ -n "$ip" ] && break
      ${pkgs.coreutils}/bin/sleep 2
    done
    [ -n "$ip" ] || { echo "tailscale0 has no IPv4 after 120s" >&2; exit 1; }
    export PASEO_LISTEN="$ip:6767"
    exec ${paseoPkg}/bin/paseo-server --no-relay
  '';
in {
  options.services.paseo-daemon = {
    enable = lib.mkEnableOption "Paseo daemon user service";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to start the daemon automatically at login/boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.paseo = {
      Unit = {
        Description = "Paseo daemon (AI coding agents), tailscale-only";
        StartLimitIntervalSec = 0;
      };
      Install.WantedBy = lib.mkIf cfg.autoStart ["default.target"];
      Service = {
        ExecStart = "${paseoStart}";
        Restart = "always";
        RestartSec = 5;
        # Reicht das HM-Profil (mit den nono-gesandboxten pi/claude Wrappern)
        # und Systempfade durch.
        Environment = [
          "NODE_ENV=production"
          "PASEO_HOME=%h/.paseo"
          "PATH=${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
          # DNS Rebinding Protection: erlaubt Connects via Name "gurke" oder "cubie"
          "PASEO_HOSTNAMES=gurke,gurke.local,cubie,cubie.local"
        ];
      };
    };
  };
}
