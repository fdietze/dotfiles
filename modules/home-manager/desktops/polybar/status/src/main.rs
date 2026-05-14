mod collectors;
mod render;
mod state;

use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    time::Duration,
};

use clap::{Parser, Subcommand};
use collectors::{active_window_title, read_cpu_freq, watch_bluetooth, Samplers};
use render::{render_right, render_title};
use state::RenderConfig;
use tokio::{sync::mpsc, time};

#[derive(Debug, Parser)]
#[command(version, about = "Low-wakeup Polybar status helper")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Right(RightArgs),
    CpuFreq(CpuFreqArgs),
    Title(TitleArgs),
    Battery(BatteryArgs),
    ToggleHeartRate,
}

#[derive(Debug, Parser)]
struct RightArgs {
    #[arg(long)]
    tail: bool,

    #[arg(long)]
    once: bool,

    #[arg(long)]
    foreground_alt: String,

    #[arg(long)]
    peak: String,

    #[arg(long)]
    warn: String,

    #[arg(long)]
    overskride: String,

    #[arg(long)]
    timew: String,
}

#[derive(Debug, Parser)]
struct CpuFreqArgs {
    #[arg(long)]
    tail: bool,

    #[arg(long)]
    once: bool,
}

#[derive(Debug, Parser)]
struct TitleArgs {
    #[arg(long)]
    tail: bool,

    #[arg(long)]
    once: bool,

    #[arg(long)]
    close_command: String,
}

#[derive(Debug, Parser)]
struct BatteryArgs {
    #[arg(long)]
    tail: bool,

    #[arg(long)]
    once: bool,

    #[arg(long)]
    foreground_alt: String,

    #[arg(long)]
    warn: String,

    #[arg(long, default_value_t = 15)]
    low_at: u8,

    #[arg(long, default_value_t = 98)]
    full_at: u8,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow_free::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Right(args) => run_right(args).await,
        Command::CpuFreq(args) => run_cpu_freq(args).await,
        Command::Title(args) => run_title(args).await,
        Command::Battery(args) => run_battery(args).await,
        Command::ToggleHeartRate => toggle_heart_rate(),
    }
}

async fn run_right(args: RightArgs) -> anyhow_free::Result<()> {
    let interval = Duration::from_secs(5);
    let config = RenderConfig::new(
        args.foreground_alt,
        args.peak,
        args.warn,
        args.overskride,
        std::env::args()
            .next()
            .unwrap_or_else(|| "polybar-status".to_owned()),
    );
    let mut samplers = Samplers::default();
    let (bluetooth_sender, mut bluetooth_receiver) = mpsc::channel(4);
    tokio::spawn(watch_bluetooth(bluetooth_sender));

    if args.once {
        // Prime delta-based collectors once so --once still prints meaningful
        // rates after a short sample window without keeping old shell loops.
        let _ = samplers.sample(interval, &args.timew).await;
        time::sleep(Duration::from_millis(500)).await;
        let state = samplers
            .sample(Duration::from_millis(500), &args.timew)
            .await;
        println!("{}", render_right(&state, &config));
        return Ok(());
    }

    let mut previous = String::new();
    let state = samplers.sample(interval, &args.timew).await;
    let rendered = render_right(&state, &config);
    if rendered != previous {
        println!("{rendered}");
        io::stdout().flush()?;
        previous = rendered;
    }
    if !args.tail {
        return Ok(());
    }

    loop {
        let state = tokio::select! {
            Some(bluetooth) = bluetooth_receiver.recv() => samplers.set_bluetooth(bluetooth),
            _ = time::sleep(interval) => samplers.sample(interval, &args.timew).await,
        };
        let rendered = render_right(&state, &config);
        if rendered != previous {
            println!("{rendered}");
            io::stdout().flush()?;
            previous = rendered;
        }
    }
}

async fn run_cpu_freq(args: CpuFreqArgs) -> anyhow_free::Result<()> {
    let mut previous = String::new();
    loop {
        let rendered = render_cpu_freq();
        if rendered != previous {
            println!("{rendered}");
            io::stdout().flush()?;
            previous = rendered;
        }

        if args.once || !args.tail {
            break;
        }
        time::sleep(Duration::from_secs(5)).await;
    }

    Ok(())
}

async fn run_battery(args: BatteryArgs) -> anyhow_free::Result<()> {
    let mut previous = String::new();
    let mut low_blink_on = true;

    loop {
        let rendered = render_battery(&args, low_blink_on);
        if rendered != previous {
            println!("{rendered}");
            io::stdout().flush()?;
            previous = rendered;
        }

        if !args.tail {
            break;
        }

        let low = read_battery_info().is_some_and(|battery| {
            battery.state == BatteryState::Discharging && battery.capacity <= args.low_at
        });
        if low {
            low_blink_on = !low_blink_on;
            time::sleep(Duration::from_millis(750)).await;
        } else {
            low_blink_on = true;
            time::sleep(Duration::from_secs(30)).await;
        }
    }

    Ok(())
}

fn render_cpu_freq() -> String {
    read_cpu_freq()
        .map(|frequency| format!("%{{A1:#freqmenu.open.0:}}{}%{{A}}", truncate(&frequency, 8)))
        .unwrap_or_default()
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

async fn run_title(args: TitleArgs) -> anyhow_free::Result<()> {
    let mut previous = String::new();
    loop {
        let title = active_window_title().unwrap_or_default();
        let rendered = render_title(&title, &args.close_command);
        if rendered != previous {
            println!("{rendered}");
            io::stdout().flush()?;
            previous = rendered;
        }

        if !args.tail {
            break;
        }
        time::sleep(Duration::from_secs(1)).await;
    }

    Ok(())
}

fn toggle_heart_rate() -> anyhow_free::Result<()> {
    let state_dir = runtime_dir().join("polybar-heart-rate");
    let enabled = state_dir.join("enabled");
    fs::create_dir_all(&state_dir)?;

    if enabled.exists() {
        fs::remove_file(enabled)?;
    } else {
        fs::write(enabled, b"")?;
    }

    Ok(())
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BatteryState {
    Charging,
    Discharging,
    Full,
    Unknown,
}

#[derive(Debug, Clone, Copy)]
struct BatteryInfo {
    state: BatteryState,
    capacity: u8,
    seconds: Option<u64>,
}

fn render_battery(args: &BatteryArgs, low_blink_on: bool) -> String {
    let Some(battery) = read_battery_info() else {
        return String::new();
    };

    if battery.state == BatteryState::Full || battery.capacity >= args.full_at {
        return String::new();
    }

    let time = battery
        .seconds
        .map(format_hhmm)
        .unwrap_or_else(|| "--:--".to_owned());
    let icon = match battery.state {
        BatteryState::Charging => "󰂄",
        BatteryState::Discharging | BatteryState::Unknown => capacity_icon(battery.capacity),
        BatteryState::Full => "󰂄",
    };

    match battery.state {
        BatteryState::Charging => format!(
            "%{{F{}}}%{{T4}}{}%{{T-}} %{{F-}}{}",
            args.foreground_alt, icon, time
        ),
        BatteryState::Discharging if battery.capacity <= args.low_at => {
            let color = if low_blink_on {
                &args.warn
            } else {
                &args.foreground_alt
            };
            format!("%{{F{color}}}%{{T4}}{icon}%{{T-}} {time}%{{F-}}")
        }
        BatteryState::Discharging if battery.capacity <= 10 => {
            format!("%{{F{}}}%{{T4}}{}%{{T-}}%{{F-}} {}", args.warn, icon, time)
        }
        _ => format!("%{{T4}}{}%{{T-}} {}", icon, time),
    }
}

fn read_battery_info() -> Option<BatteryInfo> {
    let battery = Path::new("/sys/class/power_supply/BAT0");
    let capacity = read_trimmed(battery.join("capacity"))
        .ok()?
        .parse::<u8>()
        .ok()?;
    let state = match read_trimmed(battery.join("status"))
        .unwrap_or_default()
        .as_str()
    {
        "Charging" => BatteryState::Charging,
        "Discharging" => BatteryState::Discharging,
        "Full" => BatteryState::Full,
        _ => BatteryState::Unknown,
    };
    let power = read_trimmed(battery.join("power_now"))
        .or_else(|_| read_trimmed(battery.join("current_now")))
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
        .filter(|value| *value > 0.0);
    let now = read_trimmed(battery.join("energy_now"))
        .or_else(|_| read_trimmed(battery.join("charge_now")))
        .ok()
        .and_then(|value| value.parse::<f64>().ok());
    let full = read_trimmed(battery.join("energy_full"))
        .or_else(|_| read_trimmed(battery.join("charge_full")))
        .ok()
        .and_then(|value| value.parse::<f64>().ok());

    let seconds = match (state, power, now, full) {
        (BatteryState::Discharging, Some(power), Some(now), _) => {
            Some((now / power * 3600.0) as u64)
        }
        (BatteryState::Charging, Some(power), Some(now), Some(full)) if full > now => {
            Some(((full - now) / power * 3600.0) as u64)
        }
        _ => None,
    };

    Some(BatteryInfo {
        state,
        capacity,
        seconds,
    })
}

fn read_trimmed(path: impl AsRef<Path>) -> io::Result<String> {
    Ok(fs::read_to_string(path)?.trim().to_owned())
}

fn format_hhmm(seconds: u64) -> String {
    let minutes = seconds / 60;
    format!("{:02}:{:02}", minutes / 60, minutes % 60)
}

fn capacity_icon(capacity: u8) -> &'static str {
    match capacity {
        0..=9 => "󰂎",
        10..=19 => "󰁺",
        20..=39 => "󰁻",
        40..=59 => "󰁽",
        60..=69 => "󰁿",
        70..=79 => "󰂀",
        80..=89 => "󰂁",
        _ => "󰁹",
    }
}

mod anyhow_free {
    pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
}
