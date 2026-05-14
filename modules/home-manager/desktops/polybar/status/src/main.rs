mod collectors;
mod render;
mod state;

use std::{
    fs,
    io::{self, Write},
    path::PathBuf,
    time::Duration,
};

use clap::{Parser, Subcommand};
use collectors::{active_window_title, Samplers};
use render::{render_right, render_title};
use state::RenderConfig;
use tokio::time;

#[derive(Debug, Parser)]
#[command(version, about = "Low-wakeup Polybar status helper")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Right(RightArgs),
    Title(TitleArgs),
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
struct TitleArgs {
    #[arg(long)]
    tail: bool,

    #[arg(long)]
    once: bool,

    #[arg(long)]
    close_command: String,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow_free::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Right(args) => run_right(args).await,
        Command::Title(args) => run_title(args).await,
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

    if args.once {
        // Prime delta-based collectors once so --once still prints meaningful
        // rates after a short sample window without keeping old shell loops.
        let _ = samplers.sample(interval, &args.timew);
        time::sleep(Duration::from_millis(500)).await;
        let state = samplers.sample(Duration::from_millis(500), &args.timew);
        println!("{}", render_right(&state, &config));
        return Ok(());
    }

    let mut previous = String::new();
    loop {
        let state = samplers.sample(interval, &args.timew);
        let rendered = render_right(&state, &config);
        if rendered != previous {
            println!("{rendered}");
            io::stdout().flush()?;
            previous = rendered;
        }

        if !args.tail {
            break;
        }
        time::sleep(interval).await;
    }

    Ok(())
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

mod anyhow_free {
    pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
}
