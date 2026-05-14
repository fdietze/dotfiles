#[derive(Debug, Clone, Default, PartialEq)]
pub struct StatusState {
    pub hot_process: Option<String>,
    pub cpu_cores: Vec<u8>,
    pub cpu_freq: Option<String>,
    pub temperature_c: Option<i64>,
    pub memory_percent: Option<u8>,
    pub swap_percent: Option<u8>,
    pub root_free: Option<String>,
    pub disk_read_bytes_per_s: u64,
    pub disk_write_bytes_per_s: u64,
    pub ethernet: LinkState,
    pub wifi: LinkState,
    pub bluetooth: BluetoothState,
    pub battery_watts: Option<f64>,
    pub heart_rate: HeartRateState,
    pub timewarrior: Option<String>,
    pub date: String,
    pub time: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct LinkState {
    pub connected: bool,
    pub ssid: Option<String>,
    pub rx_bytes_per_s: u64,
    pub tx_bytes_per_s: u64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct BluetoothState {
    pub powered: bool,
    pub connected_devices: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum HeartRateState {
    Disabled,
    Enabled(Option<u32>),
}

impl Default for HeartRateState {
    fn default() -> Self {
        Self::Disabled
    }
}

#[derive(Debug, Clone)]
pub struct RenderConfig {
    pub foreground_alt: String,
    pub peak: String,
    pub warn: String,
    pub overskride: String,
    pub status_command: String,
}

impl RenderConfig {
    pub fn new(
        foreground_alt: String,
        peak: String,
        warn: String,
        overskride: String,
        status_command: String,
    ) -> Self {
        Self {
            foreground_alt,
            peak,
            warn,
            overskride,
            status_command,
        }
    }
}
