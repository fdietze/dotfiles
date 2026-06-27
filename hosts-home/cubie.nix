# Cubie A7Z (Radxa A733): aarch64 SBC, Debian 11, Determinate Nix (multi-user).
# Permanent remote AI-agent host (replaces the destroyed Fly Sprite). Runs under
# a dedicated "felix" user (isolated from the board's primary "radxa" desktop
# user). Standalone Home Manager; repo cloned under ~/projects/dotfiles,
# activated with
#   home-manager switch -b backup --flake ~/projects/dotfiles#cubie
# User/home come from shell-core's defaults (felix, /home/felix).
# Agents unsandboxed (vanilla.nix) for now — nono/Landlock fit on this kernel
# still to be verified.
{
  config,
  pkgs,
  flake-inputs,
  ...
}: let
  # Paseo daemon for cubie: serves the AI-agent orchestration API over tailscale
  # ONLY (no app.paseo.sh relay). Native mobile/desktop Paseo clients on the
  # tailnet connect to <cubie-tailscale-ip>:6767; the daemon spawns pi/claude
  # (the vanilla wrappers on PATH) here on the SBC. There is no browser web UI
  # in the daemon — that lives at app.paseo.sh and needs the relay, which we skip.
  paseoPkg = flake-inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.paseo;

  # Resolve the tailscale IPv4 at start and bind only to it (defence in depth on
  # top of the daemon password). tailscaled is a Debian *system* service that may
  # come up after this user service at boot, so wait for tailscale0 to get an IP.
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

  # paseo detects provider availability by running `<cmd> --version` with a
  # hardcoded 2 s timeout. pi is a node CLI whose cold start is ~2.2 s on this
  # 1 GB SBC, so the probe always times out and pi shows "unavailable" (claude
  # starts fast enough). This shim answers --version instantly from the build-time
  # version string; every real call execs pi at low priority (matching
  # ai-agents/vanilla.nix). PI_COMMAND below points paseo's pi provider at it.
  piPkg = pkgs.llm-agents.pi;
  piForPaseo = pkgs.writeShellScriptBin "pi" ''
    if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
      echo "${piPkg.version}"
      exit 0
    fi
    exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 ${piPkg}/bin/pi "$@"
  '';
in {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    # paseo CLI + daemon package (paseo, paseo-server). Imported here, not in
    # vanilla.nix, so the heavy aarch64 npm build lands only on this host and not
    # on the other vanilla hosts (korken phone, Le-Big-Mac).
    ../modules/home-manager/profiles/ai-agents/paseo.nix
    ../modules/home-manager/profiles/standalone-extras.nix
    # Base Neovim arrives via shell-core (modules/home-manager/nvf.nix); this
    # host opts into the full LSP/language toolchain for remote editing. LSP
    # servers/formatters + grammars are cached for aarch64-linux (unlike codex's
    # Rust source build), so it stays a mostly-substituted closure on the 1 GB SBC.
    ../modules/home-manager/nvf-lsp.nix
  ];

  # pi + claude on this 1 GB SBC. Skip codex (slow aarch64 Rust source build,
  # no binary cache) and opencode. claude-code is a light npm fetch.
  aiAgents.names = ["pi" "claude"];

  # Boot-start the Paseo daemon (tailscale-only) as a systemd user service.
  # One-time manual prerequisites on the SBC (not expressible in felix's
  # home-manager; need root, which is the radxa user — felix is unprivileged):
  #   loginctl enable-linger felix   # start at boot without an active login
  #   paseo daemon set-password      # stores a *hashed* secret in ~/.paseo/config.json
  # And, because paseo OOMs when built on this 1 GB board (node code 134 in tsc),
  # add the fdietze cachix cache so the CI-built aarch64 paseo is substituted
  # (.github/workflows/build-paseo.yml). felix is not a nix trusted-user, so it
  # must go in the system daemon config; append to /etc/nix/nix.custom.conf
  # (Determinate's user-editable include) and restart nix-daemon:
  #   extra-substituters = https://fdietze.cachix.org
  #   extra-trusted-public-keys = fdietze.cachix.org-1:9XRlZtrv6HM2ZPnx5Vn+DnqZ8GbxsfAQ2/FMbwiCfiY=
  # Clients authenticate with the password and connect by tailscale IP (IPs
  # always pass the daemon's DNS-rebind check — no PASEO_HOSTNAMES needed).
  systemd.user.services.paseo = {
    Unit = {
      Description = "Paseo daemon (AI coding agents), tailscale-only";
      # Never stop retrying: a client can shut the daemon down over the websocket
      # ("shutdown_server_request", a clean exit 0), and the boot race may need
      # several tries before tailscale0 has an IP. Disable the start-rate limiter.
      StartLimitIntervalSec = 0;
    };
    Install.WantedBy = ["default.target"];
    Service = {
      ExecStart = "${paseoStart}";
      # always (not on-failure): bounce back even after a clean shutdown request
      # from a client, and after the boot-race wait-loop exits non-zero.
      Restart = "always";
      RestartSec = 5;
      # paseo-server spawns the agent CLIs; give it the home-manager profile bin
      # (pi/claude wrappers) plus the Debian/Nix system paths.
      Environment = [
        "NODE_ENV=production"
        "PASEO_HOME=%h/.paseo"
        "PATH=${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
        # Fast-`--version` pi shim so the 2 s availability probe doesn't time out
        # on this slow SBC (see piForPaseo above).
        "PI_COMMAND=${piForPaseo}/bin/pi"
        # DNS Rebinding Protection: allow connecting via tailscale hostname
        "PASEO_HOSTNAMES=cubie,cubie.local"
      ];
    };
  };

  # Per-repo GitHub deploy keys, now nix-managed (was hand-written ~/.ssh/config).
  # Each alias forces exactly one repo's write-scoped key via IdentitiesOnly, so
  # remotes git@github-dotfiles:… / git@github-ct:… push only to their repo.
  # Private keys live on the SBC (~/.ssh/deploy_*), outside nix.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # only these aliases, no global Host-* defaults
    settings = {
      "github-dotfiles" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/deploy_dotfiles";
        identitiesOnly = true;
      };
      "github-ct" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/deploy_causal_transformer";
        identitiesOnly = true;
      };
    };
  };
}
