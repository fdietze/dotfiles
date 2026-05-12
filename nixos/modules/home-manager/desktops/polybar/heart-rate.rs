//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! btleplug = "0.11"
//! futures-util = "0.3"
//! tokio = { version = "1", features = ["macros", "rt-multi-thread", "signal", "time"] }
//! uuid = "1"
//! ```
//! Print standard Bluetooth LE Heart Rate Service measurements from a device.

use std::{env, time::Duration};

use anyhow::{anyhow, bail, Context, Result};
use btleplug::{
    api::{Central, CharPropFlags, Manager as _, Peripheral as _, ScanFilter, ValueNotification},
    platform::{Adapter, Manager, Peripheral},
};
use futures_util::StreamExt;
use tokio::time;
use uuid::Uuid;

const HEART_RATE_MEASUREMENT_UUID: Uuid = Uuid::from_u128(0x00002a37_0000_1000_8000_00805f9b34fb);

#[tokio::main]
async fn main() -> Result<()> {
    let address = env::args()
        .nth(1)
        .ok_or_else(|| anyhow!("usage: heart-rate.rs <bluetooth-address>"))?;

    let adapter = first_adapter().await?;
    let peripheral = find_peripheral_by_address(&adapter, &address).await?;

    eprintln!("connecting to {address}");
    if !peripheral.is_connected().await? {
        peripheral.connect().await.context("failed to connect")?;
    }

    peripheral
        .discover_services()
        .await
        .context("failed to discover GATT services")?;

    let heart_rate_char = peripheral
        .characteristics()
        .into_iter()
        .find(|characteristic| {
            characteristic.uuid == HEART_RATE_MEASUREMENT_UUID
                && characteristic.properties.contains(CharPropFlags::NOTIFY)
        })
        .ok_or_else(|| {
            anyhow!("device does not expose the standard Heart Rate Measurement notify characteristic")
        })?;

    let mut notifications = peripheral
        .notifications()
        .await
        .context("failed to open notification stream")?;

    peripheral
        .subscribe(&heart_rate_char)
        .await
        .context("failed to subscribe to heart-rate notifications")?;

    eprintln!("subscribed to standard BLE heart-rate notifications");
    let mut last_bpm = None;
    while let Some(notification) = notifications.next().await {
        if let Some(bpm) = decode_heart_rate(&notification) {
            if last_bpm != Some(bpm) {
                println!("{bpm}");
                last_bpm = Some(bpm);
            }
        }
    }

    Ok(())
}

async fn first_adapter() -> Result<Adapter> {
    let manager = Manager::new().await.context("failed to create BLE manager")?;
    manager
        .adapters()
        .await
        .context("failed to list BLE adapters")?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("no Bluetooth adapter found"))
}

async fn find_peripheral_by_address(adapter: &Adapter, address: &str) -> Result<Peripheral> {
    let wanted = normalize_address(address);

    eprintln!("scanning for {address}");
    adapter
        .start_scan(ScanFilter::default())
        .await
        .context("failed to start BLE scan")?;

    let mut elapsed = Duration::ZERO;
    while elapsed < Duration::from_secs(15) {
        for peripheral in adapter
            .peripherals()
            .await
            .context("failed to list BLE peripherals")?
            .into_iter()
        {
            if let Some(properties) = peripheral.properties().await? {
                if normalize_address(&properties.address.to_string()) == wanted {
                    let _ = adapter.stop_scan().await;
                    return Ok(peripheral);
                }
            }
        }

        time::sleep(Duration::from_millis(500)).await;
        elapsed += Duration::from_millis(500);
    }

    let _ = adapter.stop_scan().await;
    bail!("could not find BLE device with address {address}");
}

fn normalize_address(address: &str) -> String {
    address
        .chars()
        .filter(|character| character.is_ascii_hexdigit())
        .flat_map(|character| character.to_uppercase())
        .collect()
}

fn decode_heart_rate(notification: &ValueNotification) -> Option<u16> {
    if notification.uuid != HEART_RATE_MEASUREMENT_UUID || notification.value.len() < 2 {
        return None;
    }

    let flags = notification.value[0];
    if flags & 0x01 == 0 {
        Some(notification.value[1] as u16)
    } else if notification.value.len() >= 3 {
        Some(u16::from_le_bytes([
            notification.value[1],
            notification.value[2],
        ]))
    } else {
        None
    }
}
