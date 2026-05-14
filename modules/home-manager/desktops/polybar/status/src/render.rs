use crate::state::{BluetoothState, HeartRateState, LinkState, RenderConfig, StatusState};

const FONT_ICON: u8 = 4;
const FONT_BOLD: u8 = 2;

// Icons mirror the Material Design codepoints configured in settings.nix.
const ICON_BLUETOOTH: &str = "󰂯";
const ICON_BLUETOOTH_OFF: &str = "󰂲";
const ICON_DOWNLOAD: &str = "󰇚";
const ICON_ETHERNET: &str = "󰈀";
const ICON_HEART_RATE: &str = "󰋑";
const ICON_UPLOAD: &str = "󰕒";
const ICON_WIFI: &str = "󰖩";

const RAMPS: [&str; 8] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];

pub fn render_right(state: &StatusState, config: &RenderConfig) -> String {
    let mut parts = Vec::new();

    if let Some(process) = &state.hot_process {
        if !process.is_empty() {
            parts.push(format!(
                "%{{F{}}}%{{T{}}}{}%{{T-}}%{{F-}}",
                config.peak, FONT_BOLD, process
            ));
        }
    }

    if let Some(temp) = state.temperature_c {
        if temp >= 90 {
            parts.push(format!(
                "%{{F{}}}%{{T{}}}{}C%{{T-}}%{{F-}}",
                config.warn, FONT_BOLD, temp
            ));
        } else {
            parts.push(format!("{temp}C"));
        }
    }

    if let Some(memory) = state.memory_percent {
        parts.push(render_memory(
            memory,
            state.swap_percent.unwrap_or(0),
            config,
        ));
    }

    if let Some(root_free) = &state.root_free {
        parts.push(format!("/ {root_free}"));
    }

    parts.push(format!(
        "%{{F{}}}R%{{F-}} {} %{{F{}}}W%{{F-}} {}",
        config.foreground_alt,
        format_rate(state.disk_read_bytes_per_s, true, config),
        config.foreground_alt,
        format_rate(state.disk_write_bytes_per_s, true, config)
    ));

    if let Some(ethernet) = render_link(ICON_ETHERNET, &state.ethernet, false, config) {
        parts.push(ethernet);
    }
    if let Some(wifi) = render_link(ICON_WIFI, &state.wifi, true, config) {
        parts.push(wifi);
    }

    parts.push(render_bluetooth(&state.bluetooth, config));

    if let Some(watts) = state.battery_watts {
        parts.push(format!(
            "%{{F{}}}{}%{{F-}}",
            config.foreground_alt,
            format_watts(watts)
        ));
    }

    parts.push(render_heart_rate(&state.heart_rate, config));

    if let Some(timewarrior) = &state.timewarrior {
        if !timewarrior.is_empty() {
            parts.push(format!("%{{F{}}}{}%{{F-}}", config.peak, timewarrior));
        }
    }

    parts.join("  ")
}

pub fn render_title(title: &str, close_command: &str) -> String {
    let sanitized = sanitize_title(title);
    if sanitized.is_empty() {
        String::new()
    } else {
        format!("%{{A2:{close_command}:}}{}%{{A}}", truncate(&sanitized, 49))
    }
}

pub fn sanitize_title(title: &str) -> String {
    let mut sanitized = String::new();
    let mut previous_space = false;

    for character in title.chars() {
        if character.is_control()
            || ('\u{2800}'..='\u{28ff}').contains(&character)
            || character == '%'
            || character == '\u{1b}'
        {
            continue;
        }

        let character = if character.is_whitespace() {
            ' '
        } else {
            character
        };
        if character == ' ' {
            if previous_space {
                continue;
            }
            previous_space = true;
        } else {
            previous_space = false;
        }
        sanitized.push(character);
    }

    sanitized.trim().to_owned()
}

pub fn render_cpu_load(cores: &[u8], foreground_alt: &str, peak: &str) -> String {
    cores
        .iter()
        .map(|percent| {
            let ramp = ramp(*percent);
            if *percent >= 88 {
                format!("%{{F{}}}{}%{{F-}}", peak, ramp)
            } else if *percent == 0 {
                format!("%{{F{}}}{}%{{F-}}", foreground_alt, ramp)
            } else {
                ramp.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("")
}

fn render_memory(memory: u8, swap: u8, config: &RenderConfig) -> String {
    let memory_ramp = if memory >= 88 {
        format!("%{{F{}}}{}%{{F-}}", config.warn, ramp(memory))
    } else if memory == 0 {
        format!("%{{F{}}}{}%{{F-}}", config.foreground_alt, ramp(memory))
    } else {
        ramp(memory).to_owned()
    };

    if swap == 0 {
        memory_ramp
    } else {
        format!("{}%{{F{}}}{}%{{F-}}", memory_ramp, config.warn, ramp(swap))
    }
}

fn render_link(
    icon: &str,
    link: &LinkState,
    show_ssid: bool,
    config: &RenderConfig,
) -> Option<String> {
    if !link.connected {
        return None;
    }

    let mut prefix = format!(
        "%{{F{}}}%{{T{}}}{}%{{T-}}%{{F-}} ",
        config.foreground_alt, FONT_ICON, icon
    );
    if show_ssid {
        if let Some(ssid) = &link.ssid {
            if !ssid.is_empty() {
                prefix.push_str(&sanitize_title(ssid));
                prefix.push_str("  ");
            }
        }
    }

    Some(format!(
        "{}%{{F{}}}%{{T{}}}{}%{{T-}}%{{F-}}{}  %{{F{}}}%{{T{}}}{}%{{T-}}%{{F-}}{}",
        prefix,
        config.foreground_alt,
        FONT_ICON,
        ICON_DOWNLOAD,
        format_rate(link.rx_bytes_per_s, false, config),
        config.foreground_alt,
        FONT_ICON,
        ICON_UPLOAD,
        format_rate(link.tx_bytes_per_s, false, config)
    ))
}

fn render_bluetooth(bluetooth: &BluetoothState, config: &RenderConfig) -> String {
    let label = if !bluetooth.powered {
        format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} %{{F-}}",
            config.foreground_alt, FONT_ICON, ICON_BLUETOOTH_OFF
        )
    } else if bluetooth.connected_devices > 0 {
        format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} %{{F-}}%{{F{}}}{}%{{F-}}",
            config.foreground_alt,
            FONT_ICON,
            ICON_BLUETOOTH,
            config.peak,
            bluetooth.connected_devices
        )
    } else {
        format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} 0%{{F-}}",
            config.foreground_alt, FONT_ICON, ICON_BLUETOOTH
        )
    };

    format!("%{{A1:{} &:}}{}%{{A}}", config.overskride, label)
}

fn render_heart_rate(heart_rate: &HeartRateState, config: &RenderConfig) -> String {
    let label = match heart_rate {
        HeartRateState::Disabled => format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} %{{F-}}",
            config.foreground_alt, FONT_ICON, ICON_HEART_RATE
        ),
        HeartRateState::Enabled(None) => format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} --%{{F-}}",
            config.foreground_alt, FONT_ICON, ICON_HEART_RATE
        ),
        HeartRateState::Enabled(Some(bpm)) if *bpm > 65 => format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} %{{F-}}%{{F{}}}%{{T{}}}{}%{{T-}}%{{F-}}",
            config.foreground_alt, FONT_ICON, ICON_HEART_RATE, config.warn, FONT_BOLD, bpm
        ),
        HeartRateState::Enabled(Some(bpm)) => format!(
            "%{{F{}}}%{{T{}}}{}%{{T-}} %{{F-}}{}",
            config.foreground_alt, FONT_ICON, ICON_HEART_RATE, bpm
        ),
    };

    format!(
        "%{{A1:{} toggle-heart-rate:}}{}%{{A}}",
        config.status_command, label
    )
}

fn ramp(percent: u8) -> &'static str {
    let index = ((percent as usize) * RAMPS.len() / 101).min(RAMPS.len() - 1);
    RAMPS[index]
}

fn format_rate(bytes_per_second: u64, disk: bool, config: &RenderConfig) -> String {
    let (tenths, unit) = if bytes_per_second >= 1_073_741_824 {
        ((bytes_per_second * 10 + 536_870_912) / 1_073_741_824, "G/s")
    } else if bytes_per_second >= 1_048_576 {
        ((bytes_per_second * 10 + 524_288) / 1_048_576, "M/s")
    } else {
        ((bytes_per_second * 10 + 512) / 1024, "K/s")
    };
    let rate = format!("{:>3}.{}{}", tenths / 10, tenths % 10, unit);
    let threshold = if disk { 1_048_576 } else { 1_048_576 };

    if bytes_per_second > threshold {
        format!("%{{F{}}}{}%{{F-}}", config.peak, rate)
    } else {
        rate
    }
}

fn format_watts(watts: f64) -> String {
    if watts >= 10.0 {
        format!("{watts:.0}W")
    } else {
        format!("{watts:.1}W")
    }
}

fn truncate(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let mut truncated = String::new();
    for _ in 0..max_chars {
        let Some(character) = chars.next() else {
            return value.to_owned();
        };
        truncated.push(character);
    }
    if chars.next().is_some() {
        truncated.push_str("...");
    }
    truncated
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{BluetoothState, HeartRateState, LinkState, RenderConfig, StatusState};

    fn config() -> RenderConfig {
        RenderConfig::new(
            "#555555".to_owned(),
            "#00ff00".to_owned(),
            "#ff0000".to_owned(),
            "overskride".to_owned(),
            "polybar-status".to_owned(),
        )
    }

    #[test]
    fn sanitizes_spinner_title_for_polybar() {
        assert_eq!(sanitize_title("⠋ dotfiles %{F#fff}\n"), "dotfiles {F#fff}");
    }

    #[test]
    fn renders_title_with_middle_click_close_action() {
        assert_eq!(
            render_title("⠦ dotfiles", "xdotool getwindowfocus windowkill"),
            "%{A2:xdotool getwindowfocus windowkill:}dotfiles%{A}"
        );
    }

    #[test]
    fn renders_zero_cpu_cores_dimmed() {
        assert_eq!(
            render_cpu_load(&[0, 1, 100], "#555555", "#00ff00"),
            "%{F#555555}▁%{F-}▁%{F#00ff00}█%{F-}"
        );
    }

    #[test]
    fn renders_wifi_bluetooth_battery_and_time_shape() {
        let state = StatusState {
            cpu_cores: vec![0, 20, 40, 60],
            wifi: LinkState {
                connected: true,
                ssid: Some("home".to_owned()),
                rx_bytes_per_s: 1024,
                tx_bytes_per_s: 2048,
            },
            bluetooth: BluetoothState {
                powered: true,
                connected_devices: 2,
            },
            battery_watts: Some(8.42),
            heart_rate: HeartRateState::Disabled,
            ..StatusState::default()
        };

        let output = render_right(&state, &config());
        assert!(output.contains("%{T4}󰖩%{T-}"));
        assert!(output.contains("home"));
        assert!(output.contains("%{T4}󰂯%{T-}"));
        assert!(output.contains("8.4W"));
        assert!(!output.contains("09:41"));
    }

    #[test]
    fn suppresses_disconnected_links_and_hot_process_absence() {
        let state = StatusState {
            bluetooth: BluetoothState::default(),
            ..StatusState::default()
        };

        let output = render_right(&state, &config());
        assert!(!output.contains("󰖩"));
        assert!(!output.contains("󰈀"));
        assert!(output.contains("󰂲"));
    }
}
