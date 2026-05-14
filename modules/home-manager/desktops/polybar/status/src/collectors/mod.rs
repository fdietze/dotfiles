use std::{
    collections::{HashMap, HashSet},
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use futures_util::TryStreamExt;
use tokio::{sync::mpsc, time};
use x11rb::{
    connection::Connection,
    protocol::{xproto::AtomEnum, xproto::ConnectionExt, xproto::Window},
    rust_connection::RustConnection,
};
use zbus::{
    fdo::ObjectManagerProxy, message::Type as MessageType, zvariant::OwnedValue,
    Connection as DBusConnection, MatchRule, MessageStream, Proxy,
};

use crate::state::{BluetoothState, HeartRateState, LinkState, StatusState};

const CLK_TCK: u64 = 100;
const TOP_PROCESS_THRESHOLD_PERCENT: u64 = 10;

#[derive(Debug, Default)]
pub struct Samplers {
    tick: u64,
    state: StatusState,
    cpu: CpuSampler,
    processes: ProcessSampler,
    disk: DiskSampler,
    ethernet: NetworkSampler,
    wifi: NetworkSampler,
}

impl Samplers {
    pub async fn sample(&mut self, interval: Duration, timew: &str) -> StatusState {
        self.tick = self.tick.saturating_add(1);
        let first_sample = self.tick == 1;

        self.state.hot_process = self.processes.sample(interval);
        self.state.cpu_cores = self.cpu.sample();

        let (read_bytes, write_bytes) = self.disk.sample(interval);
        self.state.disk_read_bytes_per_s = read_bytes;
        self.state.disk_write_bytes_per_s = write_bytes;

        self.state.ethernet = self.ethernet.sample("enp0s20f0u1", interval);
        self.state.wifi = self.wifi.sample("wlp2s0", interval);
        self.state.wifi.ssid = read_networkmanager_wifi_ssid().await;
        self.state.battery_watts = read_battery_watts();
        self.state.heart_rate = read_heart_rate();

        if first_sample || self.tick % 2 == 0 {
            self.state.temperature_c = read_temperature_c();
            let (memory, swap) = read_memory();
            self.state.memory_percent = memory;
            self.state.swap_percent = swap;
            self.state.timewarrior = read_timewarrior(timew);
        }

        if first_sample || self.tick % 6 == 0 {
            // BlueZ D-Bus state is cheap enough at this cadence, but still much
            // slower than the direct /proc and /sys counters.
            self.state.bluetooth = read_bluetooth().await;
        }

        if first_sample || self.tick % 12 == 0 {
            self.state.root_free = read_root_free();
        }

        self.state.clone()
    }

    pub fn set_bluetooth(&mut self, bluetooth: BluetoothState) -> StatusState {
        self.state.bluetooth = bluetooth;
        self.state.clone()
    }
}

#[derive(Debug, Default)]
pub struct CpuSampler {
    previous: Vec<CpuTimes>,
}

impl CpuSampler {
    pub fn sample(&mut self) -> Vec<u8> {
        let current = read_cpu_times();
        let percentages = current
            .iter()
            .zip(self.previous.iter())
            .map(|(current, previous)| current.percent_since(previous))
            .collect::<Vec<_>>();
        self.previous = current;
        percentages
    }
}

#[derive(Debug, Clone, Copy, Default)]
struct CpuTimes {
    idle: u64,
    total: u64,
}

impl CpuTimes {
    fn percent_since(self, previous: &Self) -> u8 {
        let idle_delta = self.idle.saturating_sub(previous.idle);
        let total_delta = self.total.saturating_sub(previous.total);
        if total_delta == 0 {
            0
        } else {
            (((total_delta.saturating_sub(idle_delta)) * 100 / total_delta).min(100)) as u8
        }
    }
}

#[derive(Debug, Default)]
struct ProcessSampler {
    previous: HashMap<u32, u64>,
}

impl ProcessSampler {
    fn sample(&mut self, interval: Duration) -> Option<String> {
        let processes = read_process_ticks();
        let mut seen = HashSet::with_capacity(processes.len());
        let mut best_command = String::new();
        let mut best_delta = 0;

        for (pid, (command, ticks)) in &processes {
            seen.insert(*pid);
            if let Some(previous_ticks) = self.previous.get(pid) {
                let delta = ticks.saturating_sub(*previous_ticks);
                if delta > best_delta {
                    best_delta = delta;
                    best_command = command.clone();
                }
            }
            self.previous.insert(*pid, *ticks);
        }

        self.previous.retain(|pid, _| seen.contains(pid));
        let percent = best_delta * 100 / (CLK_TCK * interval.as_secs().max(1));

        if percent > TOP_PROCESS_THRESHOLD_PERCENT && !best_command.is_empty() {
            Some(best_command)
        } else {
            None
        }
    }
}

#[derive(Debug, Default)]
struct DiskSampler {
    previous: Option<(u64, u64)>,
}

impl DiskSampler {
    fn sample(&mut self, interval: Duration) -> (u64, u64) {
        let current = read_disk_sectors();
        let Some(previous) = self.previous.replace(current) else {
            return (0, 0);
        };
        let seconds = interval.as_secs().max(1);
        (
            current.0.saturating_sub(previous.0) * 512 / seconds,
            current.1.saturating_sub(previous.1) * 512 / seconds,
        )
    }
}

#[derive(Debug, Default)]
struct NetworkSampler {
    previous: Option<(u64, u64)>,
}

impl NetworkSampler {
    fn sample(&mut self, interface: &str, interval: Duration) -> LinkState {
        let sysfs = PathBuf::from("/sys/class/net").join(interface);
        if !connected(&sysfs) {
            self.previous = None;
            return LinkState::default();
        }

        let current = read_network_bytes(&sysfs).unwrap_or_default();
        let previous = self.previous.replace(current);
        let seconds = interval.as_secs().max(1);
        let (rx_bytes_per_s, tx_bytes_per_s) = previous
            .map(|previous| {
                (
                    current.0.saturating_sub(previous.0) / seconds,
                    current.1.saturating_sub(previous.1) / seconds,
                )
            })
            .unwrap_or_default();

        LinkState {
            connected: true,
            ssid: None,
            rx_bytes_per_s,
            tx_bytes_per_s,
        }
    }
}

pub fn active_window_title() -> Option<String> {
    let (connection, screen_index) = RustConnection::connect(None).ok()?;
    let screen = &connection.setup().roots[screen_index];
    let active_atom = intern_atom(&connection, b"_NET_ACTIVE_WINDOW")?;
    let utf8_atom = intern_atom(&connection, b"UTF8_STRING")?;
    let net_wm_name = intern_atom(&connection, b"_NET_WM_NAME")?;
    let wm_name = AtomEnum::WM_NAME.into();

    let active = connection
        .get_property(false, screen.root, active_atom, AtomEnum::WINDOW, 0, 1)
        .ok()?
        .reply()
        .ok()?
        .value32()?
        .next()?;

    read_window_property(&connection, active, net_wm_name, utf8_atom)
        .or_else(|| read_window_property(&connection, active, wm_name, AtomEnum::STRING.into()))
}

fn intern_atom(connection: &RustConnection, name: &[u8]) -> Option<u32> {
    connection
        .intern_atom(false, name)
        .ok()?
        .reply()
        .ok()
        .map(|reply| reply.atom)
}

fn read_window_property(
    connection: &RustConnection,
    window: Window,
    property: u32,
    property_type: u32,
) -> Option<String> {
    let reply = connection
        .get_property(false, window, property, property_type, 0, 1024)
        .ok()?
        .reply()
        .ok()?;
    String::from_utf8(reply.value).ok()
}

fn read_cpu_times() -> Vec<CpuTimes> {
    let Ok(stat) = fs::read_to_string("/proc/stat") else {
        return Vec::new();
    };

    stat.lines()
        .filter(|line| {
            line.strip_prefix("cpu")
                .and_then(|rest| rest.chars().next())
                .is_some_and(|character| character.is_ascii_digit())
        })
        .filter_map(|line| {
            let values = line
                .split_whitespace()
                .skip(1)
                .filter_map(|value| value.parse::<u64>().ok())
                .collect::<Vec<_>>();
            if values.len() < 5 {
                return None;
            }
            let idle = values[3] + values.get(4).copied().unwrap_or(0);
            let total = values.iter().sum();
            Some(CpuTimes { idle, total })
        })
        .collect()
}

pub fn read_cpu_freq() -> Option<String> {
    let mut mhz_values = Vec::new();
    for entry in fs::read_dir("/sys/devices/system/cpu/cpufreq")
        .ok()?
        .flatten()
    {
        let path = entry.path().join("scaling_cur_freq");
        let Ok(value) = fs::read_to_string(path) else {
            continue;
        };
        if let Ok(khz) = value.trim().parse::<u64>() {
            mhz_values.push(khz / 1000);
        }
    }
    let mhz = mhz_values.into_iter().max()?;
    if mhz >= 1000 {
        Some(format!("{:.1} GHz", mhz as f64 / 1000.0))
    } else {
        Some(format!("{mhz} MHz"))
    }
}

fn read_temperature_c() -> Option<i64> {
    let value = fs::read_to_string("/sys/class/thermal/thermal_zone5/temp").ok()?;
    Some(value.trim().parse::<i64>().ok()? / 1000)
}

fn read_memory() -> (Option<u8>, Option<u8>) {
    let Ok(meminfo) = fs::read_to_string("/proc/meminfo") else {
        return (None, None);
    };
    let values = meminfo
        .lines()
        .filter_map(|line| {
            let (key, rest) = line.split_once(':')?;
            let value = rest.split_whitespace().next()?.parse::<u64>().ok()?;
            Some((key, value))
        })
        .collect::<HashMap<_, _>>();

    let memory = percent_used(
        values.get("MemTotal").copied(),
        values.get("MemAvailable").copied(),
    );
    let swap = percent_used(
        values.get("SwapTotal").copied(),
        values.get("SwapFree").copied(),
    );

    (memory, swap)
}

fn percent_used(total: Option<u64>, free: Option<u64>) -> Option<u8> {
    let total = total?;
    if total == 0 {
        return Some(0);
    }
    Some((((total.saturating_sub(free.unwrap_or(0))) * 100 / total).min(100)) as u8)
}

fn read_root_free() -> Option<String> {
    let metadata = fs::metadata("/").ok()?;
    // statvfs is not in std; blocks() is available from MetadataExt on Linux
    // but not filesystem free space. Use `df` once per sample interval instead
    // of carrying a libc dependency for only this slow-changing value.
    let _ = metadata.dev();
    let output = Command::new("df")
        .args(["-h", "--output=avail", "/"])
        .output()
        .ok()?;
    let text = String::from_utf8(output.stdout).ok()?;
    text.lines().nth(1).map(|line| line.trim().to_owned())
}

fn read_disk_sectors() -> (u64, u64) {
    let mut read_sectors = 0;
    let mut written_sectors = 0;

    let Ok(entries) = fs::read_dir("/sys/block") else {
        return (0, 0);
    };

    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        if !is_physical_disk(name) {
            continue;
        }
        let Ok(stat) = fs::read_to_string(entry.path().join("stat")) else {
            continue;
        };
        let values = stat
            .split_whitespace()
            .filter_map(|value| value.parse::<u64>().ok())
            .collect::<Vec<_>>();
        if values.len() > 6 {
            read_sectors += values[2];
            written_sectors += values[6];
        }
    }

    (read_sectors, written_sectors)
}

fn is_physical_disk(name: &str) -> bool {
    !(name.starts_with("loop")
        || name.starts_with("ram")
        || name.starts_with("zram")
        || name.starts_with("sr")
        || name.starts_with("dm-")
        || name.starts_with("md"))
}

fn connected(sysfs: &Path) -> bool {
    if !sysfs.join("statistics").is_dir() {
        return false;
    }
    let carrier = sysfs.join("carrier");
    if carrier.is_file() {
        return fs::read_to_string(carrier).is_ok_and(|value| value.trim() == "1");
    }
    fs::read_to_string(sysfs.join("operstate")).is_ok_and(|value| value.trim() == "up")
}

fn read_network_bytes(sysfs: &Path) -> Option<(u64, u64)> {
    let rx = fs::read_to_string(sysfs.join("statistics/rx_bytes"))
        .ok()?
        .trim()
        .parse()
        .ok()?;
    let tx = fs::read_to_string(sysfs.join("statistics/tx_bytes"))
        .ok()?
        .trim()
        .parse()
        .ok()?;
    Some((rx, tx))
}

async fn read_networkmanager_wifi_ssid() -> Option<String> {
    let connection = DBusConnection::system().await.ok()?;
    let manager = Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    )
    .await
    .ok()?;
    let active_connection_path: zbus::zvariant::OwnedObjectPath =
        manager.get_property("PrimaryConnection").await.ok()?;
    if active_connection_path.as_str() == "/" {
        return None;
    }

    let active_connection = Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        active_connection_path.as_str(),
        "org.freedesktop.NetworkManager.Connection.Active",
    )
    .await
    .ok()?;
    let connection_type: String = active_connection.get_property("Type").await.ok()?;
    if connection_type != "802-11-wireless" {
        return None;
    }

    let access_point_path: zbus::zvariant::OwnedObjectPath = active_connection
        .get_property("SpecificObject")
        .await
        .ok()?;
    if access_point_path.as_str() == "/" {
        return active_connection.get_property("Id").await.ok();
    }

    let access_point = Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        access_point_path.as_str(),
        "org.freedesktop.NetworkManager.AccessPoint",
    )
    .await
    .ok()?;
    let ssid: Vec<u8> = access_point.get_property("Ssid").await.ok()?;
    String::from_utf8(ssid).ok().filter(|ssid| !ssid.is_empty())
}

async fn read_bluetooth() -> BluetoothState {
    read_bluetooth_dbus().await.unwrap_or_default()
}

pub async fn watch_bluetooth(sender: mpsc::Sender<BluetoothState>) {
    loop {
        if watch_bluetooth_once(&sender).await.is_err() {
            time::sleep(Duration::from_secs(30)).await;
        }
    }
}

async fn watch_bluetooth_once(sender: &mpsc::Sender<BluetoothState>) -> zbus::Result<()> {
    let connection = DBusConnection::system().await?;
    let rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path_namespace("/org/bluez")?
        .build();
    let mut stream = MessageStream::for_match_rule(rule, &connection, Some(8)).await?;

    while stream.try_next().await?.is_some() {
        if let Some(bluetooth) = read_bluetooth_dbus().await {
            let _ = sender.send(bluetooth).await;
        }
    }

    Ok(())
}

async fn read_bluetooth_dbus() -> Option<BluetoothState> {
    let connection = DBusConnection::system().await.ok()?;
    let object_manager = ObjectManagerProxy::builder(&connection)
        .destination("org.bluez")
        .ok()?
        .path("/")
        .ok()?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await
        .ok()?;
    let objects = object_manager.get_managed_objects().await.ok()?;

    let mut powered = false;
    let mut connected_devices = 0;
    for interfaces in objects.values() {
        if let Some(adapter) = interfaces.get("org.bluez.Adapter1") {
            powered |= bool_property(adapter, "Powered").unwrap_or(false);
        }

        if let Some(device) = interfaces.get("org.bluez.Device1") {
            if bool_property(device, "Connected").unwrap_or(false) {
                connected_devices += 1;
            }
        }
    }

    Some(BluetoothState {
        powered,
        connected_devices,
    })
}

fn bool_property(properties: &HashMap<String, OwnedValue>, name: &str) -> Option<bool> {
    bool::try_from(properties.get(name)?).ok()
}

fn read_battery_watts() -> Option<f64> {
    let microwatts = fs::read_to_string("/sys/class/power_supply/BAT0/power_now")
        .ok()?
        .trim()
        .parse::<f64>()
        .ok()?;
    Some(microwatts / 1_000_000.0)
}

fn read_heart_rate() -> HeartRateState {
    let state_dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("polybar-heart-rate");

    if !state_dir.join("enabled").exists() {
        return HeartRateState::Disabled;
    }

    let bpm = fs::read_to_string(state_dir.join("bpm"))
        .ok()
        .and_then(|value| value.trim().parse::<u32>().ok());
    HeartRateState::Enabled(bpm)
}

fn read_timewarrior(timew: &str) -> Option<String> {
    let active = Command::new(timew)
        .args(["get", "dom.active"])
        .output()
        .ok()?;
    if String::from_utf8(active.stdout).ok()?.trim() != "1" {
        return None;
    }

    let tag = Command::new(timew)
        .args(["get", "dom.active.tags.1"])
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_owned())
        .unwrap_or_default();
    let duration = Command::new(timew)
        .args(["get", "dom.active.duration"])
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| human_duration(value.trim()))
        .unwrap_or_default();

    Some(format!("{} {}", tag, duration).trim().to_owned())
}

fn human_duration(duration: &str) -> String {
    let Some(duration) = duration.strip_prefix('P') else {
        return String::new();
    };
    let time = duration
        .split_once('T')
        .map(|(_, time)| time)
        .unwrap_or(duration);
    let hours = component(time, 'H');
    let minutes = component(time, 'M');

    match (hours, minutes) {
        (Some(hours), Some(minutes)) => format!("{hours}h {minutes}m"),
        (Some(hours), None) => format!("{hours}h"),
        (None, Some(minutes)) => format!("{minutes}m"),
        (None, None) => String::new(),
    }
}

fn component(value: &str, suffix: char) -> Option<String> {
    let end = value.find(suffix)?;
    let start = value[..end]
        .rfind(|character: char| !character.is_ascii_digit() && character != '.')
        .map(|index| index + 1)
        .unwrap_or(0);
    Some(value[start..end].to_owned())
}

fn read_process_ticks() -> HashMap<u32, (String, u64)> {
    let mut processes = HashMap::new();

    let Ok(entries) = fs::read_dir("/proc") else {
        return processes;
    };

    for entry in entries.flatten() {
        let file_name = entry.file_name();
        let Some(pid_name) = file_name.to_str() else {
            continue;
        };
        let Ok(pid) = pid_name.parse::<u32>() else {
            continue;
        };
        let Ok(stat) = fs::read_to_string(entry.path().join("stat")) else {
            continue;
        };
        if let Some(process) = parse_process_stat(&stat) {
            processes.insert(pid, process);
        }
    }

    processes
}

fn parse_process_stat(stat: &str) -> Option<(String, u64)> {
    let command_start = stat.find('(')? + 1;
    let command_end = stat.rfind(") ")?;
    let command = stat[command_start..command_end]
        .chars()
        .filter(|character| character.is_ascii_graphic() || character.is_ascii_whitespace())
        .collect::<String>()
        .trim()
        .to_owned();
    let fields = stat[(command_end + 2)..]
        .split_whitespace()
        .collect::<Vec<_>>();
    let utime = fields.get(11)?.parse::<u64>().ok()?;
    let stime = fields.get(12)?.parse::<u64>().ok()?;

    Some((command, utime + stime))
}
