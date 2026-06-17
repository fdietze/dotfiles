{
  lib,
  pkgs,
  ...
}: {
  boot = {
    kernelParams = [
      # Keep USB runtime suspend enabled so idle devices do not pin the CPU
      # package out of deep sleep states; the value is the kernel default delay.
      "usbcore.autosuspend=2"
    ];

    # iwlwifi exposes power_save as a module parameter; setting it here makes
    # the driver default match NetworkManager's per-connection powersave policy.
    extraModprobeConfig = ''
      options iwlwifi power_save=1
    '';
  };

  networking.networkmanager = {
    wifi.powersave = true; # NetworkManager.conf wifi.powersave writes mode 3.
    dispatcherScripts = [
      {
        type = "basic";
        source = pkgs.writeText "wifi-powersave" ''
          if [ "''${DEVICE_IFACE:-}" = "wlp2s0" ]; then
            case "$2" in
              up | connectivity-change | dhcp4-change)
                # NetworkManager can still leave the driver with power_save
                # off after reconnects; enforce the actual iwlwifi state too.
                ${pkgs.iw}/bin/iw dev "$DEVICE_IFACE" set power_save on || true
                ;;
            esac
          fi
        '';
      }
    ];
  };

  powerManagement = {
    enable = true;
    # powertop --auto-tune is a broad one-shot writer for kernel power knobs.
    # Keep TLP as the declarative policy owner and use powertop only manually
    # when investigating wakeups or power draw.
    powertop.enable = false;
  };

  services = {
    # GNOME enables power-profiles-daemon by default for its UI. Keep GNOME as
    # display/session behavior only; TLP is the single host power policy owner.
    power-profiles-daemon.enable = lib.mkForce false;

    thermald.enable = true;

    # nixos-hardware enables TLP for laptops by default; keep it explicit here
    # because host power policy should not depend on the selected desktop.
    tlp = {
      enable = true;
      settings = {
        # intel_pstate "powersave" still boosts on demand, then drops back down
        # according to EPP when work is done.
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_performance";

        # TLP does not reset omitted P-state limits when switching profiles;
        # keep AC explicitly uncapped and battery capped.
        CPU_MIN_PERF_ON_AC = 10;
        CPU_MAX_PERF_ON_AC = 100;

        # Use percentage P-state limits instead of fixed frequencies so the
        # battery cap scales with each CPU's own performance range.
        CPU_MIN_PERF_ON_BAT = 10;
        CPU_MAX_PERF_ON_BAT = 50;

        # AC may use turbo for responsiveness; battery should trade peak speed
        # for lower heat and longer runtime.
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;
        CPU_HWP_DYN_BOOST_ON_AC = 0;
        CPU_HWP_DYN_BOOST_ON_BAT = 0;

        # Keep the currently active ThinkPad battery care thresholds.
        START_CHARGE_THRESH_BAT0 = 75;
        STOP_CHARGE_THRESH_BAT0 = 80;

        # TLP's USB_DENYLIST keeps matching devices out of USB autosuspend;
        # tlp.conf(5) documents the supported vendor:product syntax.
        USB_DENYLIST = ["046d:c52b"];
      };
    };
  };
}
