# mac-quiet-fans Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-contained rust-script tool that throttles the user's hot processes (PWM via SIGSTOP/SIGCONT under a conservative PI controller) to hold the CPU die temperature flat, just under the fan spin-up knee, keeping fans quiet while running heavy work near full speed.

**Architecture:** Single rust-script file (nix-shell shebang, `smc` crate for sensing). Functional core / imperative shell: a **pure** PI controller function (unit-tested via `--selftest`), a sensor unit (temp + fan RPM with plausibility gate + EMA), and an imperative actuator/selector that scans the user's processes each tick and applies one aggregate duty cycle. Setpoint = a constant fan knee learned once by passive observation. Safety: signal handler + panic guard SIGCONT every managed process on exit.

**Tech Stack:** rust-script (nixpkgs 0.35), rustc 1.83 (nixpkgs), crates `smc = "0.2"` + `four-char-code = "=0.0.5"` (SMC reads via raw `read_key`), `libc = "0.2"` (kill/signals), `signal-hook = "0.3"` (clean shutdown). Process scan via `ps`.

**Task 0 result (verified on this M-machine):** The `smc` crate's convenience
methods are Intel-only and FAIL here — `cpus_temperature()` → `Sysctl(2)`,
`fans()` → `KeyNotFound("F0ID")`, `all_temperature_sensors()` → `NotPrivileged`.
But raw `read_key::<f32>(FourCharCode)` works for explicit keys. Confirmed
readings: `TCMb`=74.6°C, `TCMz`=87.7°C, `TCDX`=70.9°C (CPU); `F0Ac`/`F1Ac`
(fan RPM), `F0Tg` (target), `F0Mn`=2317 (floor). So: supply our own keys, never
use the convenience methods. No smctemp fallback needed.

**Working nix-shell + rust-script shebang** (the two-line `#!nix-shell` form
breaks rust-script's parser; hide the directive in a block comment that still
starts with `#!` at column 0 — nix scans for it, Rust ignores it):
```
#!/usr/bin/env nix-shell
//! ```cargo
//! [dependencies]
//! ...
//! ```
/*
#! nix-shell -i rust-script -p rust-script cargo rustc
*/
```
The `//!` cargo manifest MUST be the first thing after the shebang (a leading
block comment displaces it and deps go unresolved).

**Spec:** `docs/superpowers/specs/2026-06-25-mac-quiet-fans-design.md`

**Target file:** `~/projects/dotfiles/home/bin/mac-quiet-fans`

---

## File Structure

One executable file: `home/bin/mac-quiet-fans`. rust-script compiles+caches it. Conceptual units within the file:

- **config** — parse env vars / args into a `Config` struct (tuning without recompiling)
- **controller** (pure) — `PiController::update(temp, dt) -> duty`; no I/O; unit-tested
- **sensor** — `read_temp(&smc)`, `fans_max_rpm(&smc)`, `fans_at_floor(&smc)`; plausibility gate; EMA lives in the loop
- **selector** — `scan_managed(cfg, self_pid, &mut debounce) -> Vec<i32>`
- **actuator** — `apply_duty(&managed, duty, window)` PWM via SIGSTOP/SIGCONT
- **safety** — `Guard` holding the managed set; signal-hook + panic hook → SIGCONT all
- **modes** — `--selftest`, `--probe`, `--observe`, `--list-managed`, default = run loop

Because sensing is an isolated unit, the Task 0 spike de-risks the only external unknown (does `smc` read this machine's Apple Silicon keys) before any loop code is written.

---

## Task 0: Verification spike — does the `smc` crate read this machine?

**Files:**
- Create (throwaway): `/tmp/smc-spike`

- [ ] **Step 1: Write the spike**

```bash
cat > /tmp/smc-spike <<'EOF'
#!/usr/bin/env nix-shell
//! ```cargo
//! [dependencies]
//! smc = "0.2"
//! four-char-code = "=0.0.5"
//! ```
/*
#! nix-shell -i rust-script -p rust-script cargo rustc
*/
use four_char_code::FourCharCode;
fn key(s: &[u8; 4]) -> FourCharCode { FourCharCode(u32::from_be_bytes(*s)) }
fn main() {
    let smc = smc::SMC::new().expect("open SMC");
    for k in [b"TCMb", b"TCMz", b"TCDX", b"F0Ac", b"F1Ac", b"F0Tg", b"F0Mn"] {
        let v: Result<f32, _> = smc.read_key(key(k));
        println!("{} = {:?}", std::str::from_utf8(k).unwrap(), v);
    }
}
EOF
chmod +x /tmp/smc-spike
```

- [ ] **Step 2: Run it**

Run: `/tmp/smc-spike`
Expected (first run compiles, then prints): `TCMb`/`TCMz`/`TCDX` as plausible CPU
temps (~60–90°C, not 0.0), `F0Ac`/`F1Ac` as real fan RPM, `F0Mn`=2317.

- [ ] **Step 3: Decision gate — DONE (proceed)**

Raw `read_key` returned plausible temps + fan RPM → use the `smc` crate via raw
`read_key`. (Fallback to packaging smctemp would only have triggered if raw reads
also failed; they did not.)

- [ ] **Step 4: Clean up**

Run: `rm -f /tmp/smc-spike`
(No commit — throwaway.)

---

## Task 1: Scaffold the executable (shebang, config, `--help`, compiles)

**Files:**
- Create: `home/bin/mac-quiet-fans`

- [ ] **Step 1: Write the scaffold**

```rust
#!/usr/bin/env nix-shell
#! nix-shell -i rust-script -p rust-script cargo rustc
//! ```cargo
//! [dependencies]
//! smc = "0.2"
//! four-char-code = "=0.0.5"
//! libc = "0.2"
//! signal-hook = "0.3"
//! ```
/*
#! nix-shell -i rust-script -p rust-script cargo rustc
*/
// mac-quiet-fans — throttle the user's hot processes (PWM SIGSTOP/SIGCONT under a
// conservative PI controller) to hold CPU die temp flat just under the fan knee,
// keeping fans quiet. Sensing via the `smc` crate raw read_key (its convenience
// methods are Intel-only). See
// docs/superpowers/specs/2026-06-25-mac-quiet-fans-design.md
use std::env;
use four_char_code::FourCharCode;

#[derive(Clone, Debug)]
struct Config {
    knee_c: f64,        // measured fan-knee die temperature (constant for this machine)
    margin_c: f64,      // setpoint = knee_c - margin_c
    kp: f64,            // PI proportional gain (duty per degree)
    ti_s: f64,          // PI integral time (seconds) ~ thermal tau
    cpu_threshold: f64, // %CPU to consider a process "hot"
    debounce_ticks: u32,// consecutive scans above/below threshold before add/drop
    window_ms: u64,     // PWM window
    d_min: f64,         // duty floor (always make some progress)
    d_max: f64,         // duty ceiling (full speed when cool)
    tick_ms: u64,       // control loop period (also rescan cadence)
}

impl Config {
    fn from_env() -> Config {
        fn f(k: &str, d: f64) -> f64 { env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d) }
        fn u(k: &str, d: u64) -> u64 { env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d) }
        Config {
            knee_c:        f("QF_KNEE_C", 85.0),
            margin_c:      f("QF_MARGIN_C", 3.0),
            kp:            f("QF_KP", 0.05),
            ti_s:          f("QF_TI_S", 30.0),
            cpu_threshold: f("QF_CPU_THRESHOLD", 50.0),
            debounce_ticks:u("QF_DEBOUNCE_TICKS", 3) as u32,
            window_ms:     u("QF_WINDOW_MS", 200),
            d_min:         f("QF_D_MIN", 0.15),
            d_max:         f("QF_D_MAX", 1.0),
            tick_ms:       u("QF_TICK_MS", 1000),
        }
    }
    fn setpoint(&self) -> f64 { self.knee_c - self.margin_c }
}

const HELP: &str = "\
mac-quiet-fans — keep the fans quiet by throttling your hot processes.

USAGE:
  mac-quiet-fans            run the thermal governor (default)
  mac-quiet-fans --probe    print current temp + fan RPM once and exit
  mac-quiet-fans --observe  watch for the fan knee (logs temp when fans leave floor)
  mac-quiet-fans --list-managed  print which of your processes would be throttled
  mac-quiet-fans --selftest run the pure-controller unit tests
  mac-quiet-fans --help

TUNING (env vars, no recompile):
  QF_KNEE_C QF_MARGIN_C QF_KP QF_TI_S QF_CPU_THRESHOLD
  QF_DEBOUNCE_TICKS QF_WINDOW_MS QF_D_MIN QF_D_MAX QF_TICK_MS
";

fn main() {
    let arg = env::args().nth(1).unwrap_or_default();
    let cfg = Config::from_env();
    match arg.as_str() {
        "--help" | "-h" => print!("{HELP}"),
        "--selftest"    => { println!("no tests yet"); }
        "--probe"       => { println!("probe: not implemented yet"); }
        "--observe"     => { println!("observe: not implemented yet"); }
        "--list-managed"=> { println!("list-managed: not implemented yet"); }
        "" => { println!("run: not implemented yet; setpoint={:.1}", cfg.setpoint()); }
        other => { eprintln!("unknown arg: {other}\n{HELP}"); std::process::exit(2); }
    }
}
```

- [ ] **Step 2: Make executable and compile-run**

Run: `chmod +x home/bin/mac-quiet-fans && home/bin/mac-quiet-fans --help`
Expected: first run compiles (downloads crates once), then prints the help text. No errors.

- [ ] **Step 3: Verify config parses**

Run: `QF_KNEE_C=80 home/bin/mac-quiet-fans ""`
Expected: prints `run: not implemented yet; setpoint=77.0`

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): scaffold rust-script with config + modes"
```

---

## Task 2: Pure PI controller + `--selftest` (TDD)

**Files:**
- Modify: `home/bin/mac-quiet-fans`

The controller is the only fully unit-testable unit (no I/O). Position-form PI with
conditional-integration anti-windup. `update` is pure given `&mut self` state.

- [ ] **Step 1: Write the controller and its tests (failing — `selftest` returns no tests yet)**

Add above `fn main`:

```rust
// Pure PI controller. error e = setpoint - temp (e<0 when too hot -> lower duty).
// Steady-state duty comes entirely from the integral term (no feedforward).
// Anti-windup: conditional integration — don't accumulate further into a saturated bound.
struct PiController {
    kp: f64,
    ki: f64,      // kp / ti
    integral: f64,
    d_min: f64,
    d_max: f64,
    setpoint: f64,
}

impl PiController {
    fn new(cfg: &Config) -> PiController {
        PiController {
            kp: cfg.kp,
            ki: cfg.kp / cfg.ti_s,
            integral: 0.0,
            d_min: cfg.d_min,
            d_max: cfg.d_max,
            setpoint: cfg.setpoint(),
        }
    }

    // dt in seconds. Returns duty in [d_min, d_max].
    fn update(&mut self, temp: f64, dt: f64) -> f64 {
        let e = self.setpoint - temp;
        let candidate = self.integral + e * dt;
        let raw = self.kp * e + self.ki * candidate;
        // Conditional integration anti-windup.
        if raw > self.d_max {
            if e <= 0.0 { self.integral = candidate; } // only block growth that pushes deeper into saturation
            self.d_max
        } else if raw < self.d_min {
            if e >= 0.0 { self.integral = candidate; }
            self.d_min
        } else {
            self.integral = candidate;
            raw
        }
    }
}

fn run_selftest() -> i32 {
    let cfg = Config { kp: 0.1, ti_s: 20.0, d_min: 0.15, d_max: 1.0,
        knee_c: 80.0, margin_c: 0.0, // setpoint = 80
        cpu_threshold: 50.0, debounce_ticks: 3, window_ms: 200, tick_ms: 1000 };
    let mut failures = 0;
    macro_rules! check { ($name:expr, $cond:expr) => {
        if $cond { println!("ok   - {}", $name); } else { println!("FAIL - {}", $name); failures += 1; }
    }; }

    // 1. Too hot -> duty parks at floor.
    {
        let mut c = PiController::new(&cfg);
        let mut d = 1.0;
        for _ in 0..50 { d = c.update(95.0, 1.0); } // 15C over setpoint
        check!("too hot parks at d_min", (d - cfg.d_min).abs() < 1e-9);
    }
    // 2. Too cold -> duty climbs to ceiling.
    {
        let mut c = PiController::new(&cfg);
        let mut d = 0.0;
        for _ in 0..50 { d = c.update(60.0, 1.0); } // 20C under setpoint
        check!("too cold reaches d_max", (d - cfg.d_max).abs() < 1e-9);
    }
    // 3. Anti-windup: integral stays bounded while saturated hot, and duty
    //    recovers within a few ticks once temp returns to setpoint.
    {
        let mut c = PiController::new(&cfg);
        for _ in 0..1000 { c.update(95.0, 1.0); }      // long time saturated hot
        let int_after_hot = c.integral;
        check!("integral bounded under saturation", int_after_hot.abs() < 1000.0);
        // Now hold exactly at setpoint; duty should leave the floor quickly (no long stuck-low).
        let mut d = cfg.d_min;
        let mut ticks = 0;
        for _ in 0..200 { d = c.update(80.0, 1.0); ticks += 1; if d > cfg.d_min + 0.01 { break; } }
        check!("recovers off floor without huge overshoot delay", ticks < 200 && d > cfg.d_min);
    }
    // 4. At setpoint with built-up integral, output equals ki*integral (steady hold).
    {
        let mut c = PiController::new(&cfg);
        c.integral = 5.0; // pretend established
        let d = c.update(80.0, 1.0); // e=0 -> raw = ki*integral
        check!("steady duty from integral at setpoint", (d - (cfg.kp/cfg.ti_s)*5.0).abs() < 1e-9);
    }

    if failures == 0 { println!("PASS"); 0 } else { println!("{failures} FAILED"); 1 }
}
```

Wire it: change the `"--selftest"` arm in `main` to:

```rust
        "--selftest"    => { std::process::exit(run_selftest()); }
```

- [ ] **Step 2: Run selftest to verify it passes**

Run: `home/bin/mac-quiet-fans --selftest`
Expected: four `ok -` lines and `PASS`, exit 0.

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): pure PI controller with anti-windup + selftest"
```

---

## Task 3: Sensor unit + `--probe`

**Files:**
- Modify: `home/bin/mac-quiet-fans`

- [ ] **Step 1: Add sensor functions**

Add above `fn main`:

```rust
// Raw SMC read of a 4-char key as f32 (temps + fan RPM are all `flt` here).
// The smc crate's convenience methods (fans/cpus_temperature) are Intel-only and
// fail on this machine; raw read_key with explicit keys works.
fn smc_key(s: &[u8; 4]) -> FourCharCode { FourCharCode(u32::from_be_bytes(*s)) }
fn read_f32(smc: &smc::SMC, k: &[u8; 4]) -> Option<f64> {
    smc.read_key::<f32>(smc_key(k)).ok().map(|v| v as f64)
}

// CPU temp keys verified present on this machine (Task 0). Hotspot = max of them.
// The knee is calibrated against THIS same metric (--observe), so the absolute
// definition doesn't matter as long as it stays identical here and in control.
const CPU_KEYS: [&[u8; 4]; 3] = [b"TCMb", b"TCMz", b"TCDX"];
// (actual-rpm, target-rpm, floor-rpm) per fan; this machine has 2 fans.
const FAN_KEYS: [(&[u8; 4], &[u8; 4], &[u8; 4]); 2] =
    [(b"F0Ac", b"F0Tg", b"F0Mn"), (b"F1Ac", b"F1Tg", b"F1Mn")];

// Plausibility gate: reject failure modes (0.0 C from a bad key; absurd highs).
// Returns None to mean "hold last good value".
fn plausible_temp(t: f64) -> Option<f64> {
    if (1.0..=110.0).contains(&t) { Some(t) } else { None }
}

fn read_temp(smc: &smc::SMC) -> Option<f64> {
    let hot = CPU_KEYS.iter().filter_map(|k| read_f32(smc, k)).fold(f64::MIN, f64::max);
    if hot == f64::MIN { return None; }
    plausible_temp(hot)
}

// True iff every readable fan is essentially at its floor (knee not yet crossed).
// Tolerance absorbs idle wobble (e.g. actual 2282 vs min 2317).
fn fans_at_floor(smc: &smc::SMC) -> bool {
    for (ac, _tg, mn) in FAN_KEYS {
        if let (Some(a), Some(m)) = (read_f32(smc, ac), read_f32(smc, mn)) {
            if a > m + 150.0 { return false; }
        }
    }
    true
}

fn read_fans_max_rpm(smc: &smc::SMC) -> f64 {
    FAN_KEYS.iter().filter_map(|(ac, _, _)| read_f32(smc, ac)).fold(0.0, f64::max)
}
```

- [ ] **Step 2: Implement `--probe`**

Replace the `"--probe"` arm body with:

```rust
        "--probe" => {
            let smc = smc::SMC::new().expect("open SMC");
            let t = read_temp(&smc);
            println!("cpu temp:  {}", t.map(|v| format!("{v:.1} C")).unwrap_or("(implausible)".into()));
            println!("fan max:   {:.0} rpm", read_fans_max_rpm(&smc));
            println!("at floor:  {}", fans_at_floor(&smc));
        }
```

- [ ] **Step 3: Run probe and sanity-check against smctemp**

Run: `home/bin/mac-quiet-fans --probe`
Expected: `cpu temp` within a couple degrees of `/tmp/smctemp/smctemp -c` (if still present) or the Task 0 spike value; `fan max` ~2300 and `at floor: true` when idle.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): SMC sensor unit (temp gate, fan floor) + --probe"
```

---

## Task 4: Knee observation mode `--observe`

**Files:**
- Modify: `home/bin/mac-quiet-fans`

Passively learn the constant knee: poll until fans leave the floor, report the temp.
No forced load — the user's own jobs heat the chip.

- [ ] **Step 1: Implement `--observe`**

Replace the `"--observe"` arm body with:

```rust
        "--observe" => {
            let smc = smc::SMC::new().expect("open SMC");
            println!("watching for fan knee (Ctrl-C to stop)... run your heavy job now.");
            let mut hottest_at_floor = 0.0_f64;
            loop {
                if let Some(t) = read_temp(&smc) {
                    if fans_at_floor(&smc) {
                        if t > hottest_at_floor {
                            hottest_at_floor = t;
                            println!("floor: {t:.1} C (fans still asleep; knee is above this)");
                        }
                    } else {
                        println!("KNEE CROSSED at {t:.1} C  (fan max {:.0} rpm)", read_fans_max_rpm(&smc));
                        println!("=> set QF_KNEE_C around {:.0}. hottest-still-quiet was {:.1} C.",
                                 t.floor(), hottest_at_floor);
                    }
                }
                std::thread::sleep(std::time::Duration::from_millis(2000));
            }
        }
```

- [ ] **Step 2: Smoke-test (brief)**

Run: `timeout 6 home/bin/mac-quiet-fans --observe || true`
Expected: prints `watching...` and, while idle, `floor: NN C` lines. (Catching an actual crossing requires real load; that happens during acceptance, Task 8.)

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): --observe to learn the constant fan knee"
```

---

## Task 5: Process selection `--list-managed`

**Files:**
- Modify: `home/bin/mac-quiet-fans`

Scan the user's hot processes via `ps`. Exclude self + own children (correctness).
Debounce so brief spikes don't churn the set.

- [ ] **Step 1: Add selector**

Add above `fn main`:

```rust
use std::collections::HashMap;

// One process line we care about.
struct Proc { pid: i32, ppid: i32, cpu: f64 }

// Read current user's processes with pid, ppid, %cpu.
fn ps_snapshot() -> Vec<Proc> {
    let me = unsafe { libc::getuid() };
    let user = env::var("USER").unwrap_or_default();
    let out = std::process::Command::new("ps")
        .args(["-Ao", "pid=,ppid=,uid=,%cpu="])
        .output();
    let mut v = Vec::new();
    if let Ok(out) = out {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.len() != 4 { continue; }
            let (pid, ppid, uid, cpu) = (
                f[0].parse::<i32>().ok(), f[1].parse::<i32>().ok(),
                f[2].parse::<u32>().ok(), f[3].parse::<f64>().ok());
            if let (Some(pid), Some(ppid), Some(uid), Some(cpu)) = (pid, ppid, uid, cpu) {
                if uid == me { let _ = &user; v.push(Proc { pid, ppid, cpu }); }
            }
        }
    }
    v
}

// Update debounce counters; return the currently-managed pid set.
// `debounce` maps pid -> consecutive ticks above threshold (negative = below).
fn scan_managed(cfg: &Config, self_pid: i32, debounce: &mut HashMap<i32, i32>) -> Vec<i32> {
    let snap = ps_snapshot();
    let hot: std::collections::HashSet<i32> = snap.iter()
        .filter(|p| p.pid != self_pid && p.ppid != self_pid && p.cpu >= cfg.cpu_threshold)
        .map(|p| p.pid).collect();
    let alive: std::collections::HashSet<i32> = snap.iter().map(|p| p.pid).collect();
    // Advance counters.
    for &pid in &hot { *debounce.entry(pid).or_insert(0) += 1; }
    let cooled: Vec<i32> = debounce.keys().cloned()
        .filter(|p| !hot.contains(p)).collect();
    for pid in cooled { *debounce.get_mut(&pid).unwrap() -= 1; }
    // Drop dead/long-cooled entries.
    debounce.retain(|pid, &mut c| alive.contains(pid) && c > -(cfg.debounce_ticks as i32));
    // Managed = counter reached the debounce threshold.
    debounce.iter()
        .filter(|(_, &c)| c >= cfg.debounce_ticks as i32)
        .map(|(&pid, _)| pid).collect()
}
```

- [ ] **Step 2: Implement `--list-managed`**

Replace the `"--list-managed"` arm body with:

```rust
        "--list-managed" => {
            let self_pid = std::process::id() as i32;
            let mut debounce = HashMap::new();
            // Need debounce_ticks scans to confirm; sample quickly.
            let mut managed = Vec::new();
            for _ in 0..cfg.debounce_ticks {
                managed = scan_managed(&cfg, self_pid, &mut debounce);
                std::thread::sleep(std::time::Duration::from_millis(300));
            }
            println!("threshold {:.0}% CPU; managed pids: {:?}", cfg.cpu_threshold, managed);
            for pid in &managed {
                let _ = std::process::Command::new("ps")
                    .args(["-o", "pid=,%cpu=,comm=", "-p", &pid.to_string()])
                    .status();
            }
        }
```

- [ ] **Step 3: Test against a synthetic hog**

Run:
```bash
yes > /dev/null & HOG=$!
QF_CPU_THRESHOLD=50 home/bin/mac-quiet-fans --list-managed
kill $HOG
```
Expected: the `yes` pid appears in `managed pids` with ~100% CPU. The `--list-managed` process itself must NOT appear (self-exclusion).

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): debounced process selector + --list-managed"
```

---

## Task 6: Actuator (PWM) + safety guard

**Files:**
- Modify: `home/bin/mac-quiet-fans`

- [ ] **Step 1: Add signal helpers, the safety Guard, and the PWM actuator**

Add above `fn main`:

```rust
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

fn kill(pid: i32, sig: i32) { unsafe { libc::kill(pid as libc::pid_t, sig); } }
fn cont_all(pids: &[i32]) { for &p in pids { kill(p, libc::SIGCONT); } }

// Holds the set we may have paused. Dropped (or signalled) -> resume everything.
// The single most important safety net (a stuck-paused process = lost work).
struct Guard { managed: Arc<Mutex<Vec<i32>>> }
impl Drop for Guard {
    fn drop(&mut self) {
        if let Ok(p) = self.managed.lock() { cont_all(&p); }
    }
}

// PWM one window: run for duty*window, pause the rest. window << die tau so the
// die sees smooth average power. d_min>0 guarantees a run phase (progress).
fn apply_duty(managed: &[i32], duty: f64, window_ms: u64) {
    let on = (duty.clamp(0.0, 1.0) * window_ms as f64) as u64;
    let off = window_ms.saturating_sub(on);
    cont_all(managed); // run phase
    if on > 0 { std::thread::sleep(std::time::Duration::from_millis(on)); }
    if off > 0 {
        for &p in managed { kill(p, libc::SIGSTOP); }
        std::thread::sleep(std::time::Duration::from_millis(off));
        cont_all(managed); // never end a window paused
    }
}
```

- [ ] **Step 2: Verify it builds (compile via --help)**

Run: `home/bin/mac-quiet-fans --help`
Expected: compiles clean (warnings about unused `apply_duty`/`Guard` are fine until Task 7), prints help.

- [ ] **Step 3: Manual actuator check against a hog**

Run:
```bash
yes > /dev/null & HOG=$!
# crude: stop it 1s, confirm 0% cpu, cont it, confirm busy again
kill -STOP $HOG; sleep 1; ps -o %cpu= -p $HOG
kill -CONT $HOG; sleep 1; ps -o %cpu= -p $HOG
kill $HOG
```
Expected: ~0.0 while stopped, high again after cont. (Confirms SIGSTOP/SIGCONT semantics the actuator relies on.)

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): PWM actuator + SIGCONT-all safety guard"
```

---

## Task 7: Wire the control loop

**Files:**
- Modify: `home/bin/mac-quiet-fans`

- [ ] **Step 1: Implement the run loop**

Replace the default `""` arm body in `main` with:

```rust
        "" => run_loop(&cfg),
```

Add above `fn main`:

```rust
fn run_loop(cfg: &Config) {
    let smc = smc::SMC::new().expect("open SMC");
    let self_pid = std::process::id() as i32;

    // Shared managed set so the signal handler / Guard can resume it.
    let managed = Arc::new(Mutex::new(Vec::<i32>::new()));
    let _guard = Guard { managed: managed.clone() };

    // Clean shutdown on SIGINT/SIGTERM/SIGHUP: resume everything, then exit.
    let term = Arc::new(AtomicBool::new(false));
    for sig in [signal_hook::consts::SIGINT, signal_hook::consts::SIGTERM, signal_hook::consts::SIGHUP] {
        signal_hook::flag::register(sig, term.clone()).expect("register signal");
    }

    let mut pi = PiController::new(cfg);
    let mut debounce: HashMap<i32, i32> = HashMap::new();
    let mut ema: Option<f64> = None;          // light temperature filter
    let alpha = 0.4;                           // EMA weight on new sample
    let dt = cfg.tick_ms as f64 / 1000.0;
    let mut last_duty = cfg.d_max;

    println!("mac-quiet-fans: setpoint {:.1} C (knee {:.1} - margin {:.1}), threshold {:.0}% CPU",
             cfg.setpoint(), cfg.knee_c, cfg.margin_c, cfg.cpu_threshold);

    while !term.load(Ordering::Relaxed) {
        // Update managed set.
        let pids = scan_managed(cfg, self_pid, &mut debounce);
        // Resume any process that just left the set (so we never leave it paused).
        {
            let mut g = managed.lock().unwrap();
            for old in g.iter() { if !pids.contains(old) { kill(*old, libc::SIGCONT); } }
            *g = pids.clone();
        }

        // Sense + filter.
        if let Some(raw) = read_temp(&smc) {
            ema = Some(match ema { Some(e) => alpha * raw + (1.0 - alpha) * e, None => raw });
        }
        let temp = ema.unwrap_or(cfg.setpoint()); // no reading yet -> neutral

        // Control.
        let duty = pi.update(temp, dt);
        last_duty = duty;

        // Actuate across the whole tick using PWM windows.
        if pids.is_empty() {
            std::thread::sleep(std::time::Duration::from_millis(cfg.tick_ms));
        } else {
            let windows = (cfg.tick_ms / cfg.window_ms).max(1);
            for _ in 0..windows {
                if term.load(Ordering::Relaxed) { break; }
                apply_duty(&pids, duty, cfg.window_ms);
            }
        }
        eprintln!("temp {temp:5.1}C  duty {:>4.0}%  managed {}", duty * 100.0, pids.len());
    }
    let _ = last_duty;
    // Guard's Drop resumes everything on the way out.
    let g = managed.lock().unwrap();
    cont_all(&g);
    println!("\nmac-quiet-fans: stopped, all processes resumed.");
}
```

- [ ] **Step 2: Dry run with a hog and a low knee to force throttling**

Run:
```bash
yes > /dev/null & HOG=$!
# Force setpoint below current temp so the loop must throttle the hog.
QF_KNEE_C=40 QF_MARGIN_C=0 QF_CPU_THRESHOLD=50 QF_TICK_MS=1000 \
  timeout 8 home/bin/mac-quiet-fans
kill $HOG 2>/dev/null
ps -o stat=,%cpu= -p $HOG 2>/dev/null   # should be gone (we killed it)
```
Expected: log lines show `duty` dropping toward `15%` (d_min) because temp is way above the forced 40°C setpoint; the `yes` process gets throttled (low avg CPU during the run). After `timeout`, the tool prints "all processes resumed" and exits cleanly.

- [ ] **Step 3: Verify clean resume on Ctrl-C**

Run (interactive):
```bash
yes > /dev/null & HOG=$!
QF_KNEE_C=40 QF_MARGIN_C=0 home/bin/mac-quiet-fans   # let it run ~3s, then Ctrl-C
ps -o stat= -p $HOG    # must NOT be 'T' (stopped); should be running/sleeping
kill $HOG
```
Expected: after Ctrl-C, the hog's state is not `T` — the guard resumed it.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): wire PI control loop with EMA + clean-shutdown guard"
```

---

## Task 8: Calibrate the knee, acceptance run, and document

**Files:**
- Modify: `home/bin/mac-quiet-fans` (header usage note only)

- [ ] **Step 1: Learn the real knee**

Run: `home/bin/mac-quiet-fans --observe`
Then start a real heavy job (e.g. the rust build under `~/.cache/...`). Watch until it prints `KNEE CROSSED at NN C`. Record `NN`. Stop with Ctrl-C.

- [ ] **Step 2: Record the knee as the default**

Edit the `from_env` default for `knee_c` to the observed value (replace `85.0`):

```rust
            knee_c:        f("QF_KNEE_C", /* measured on this machine */ 85.0),
```
Set it to the number from Step 1 (keep the comment, update the value and note the date/machine).

- [ ] **Step 3: Acceptance run under real load**

Run: `home/bin/mac-quiet-fans` while a real heavy job runs (a few minutes).
Expected: log shows temperature settling near `setpoint` and holding roughly flat (small variance); `duty` modulates between ~15% and 100% rather than slamming between extremes; fans audibly stay at floor (`--probe` in another shell shows `at floor: true`). This is the real success criterion: flat temp just under the knee, quiet fans, job still progressing.

- [ ] **Step 4: Add a short usage note to the script header**

Add after the existing top comment block in the file:

```rust
// Usage: run `mac-quiet-fans --observe` once to find the fan knee, set QF_KNEE_C
// (or the from_env default), then run `mac-quiet-fans` alongside heavy jobs.
// Stop with Ctrl-C; all managed processes are always resumed on exit.
// Residual risk: SIGKILL (kill -9) of this tool cannot be caught — a managed
// process could remain stopped; resume manually with `kill -CONT <pid>`.
```

- [ ] **Step 5: Final commit**

```bash
cd ~/projects/dotfiles
git add home/bin/mac-quiet-fans
git commit -m "feat(mac-quiet-fans): calibrate knee default + usage/safety notes"
```

---

## Self-Review notes

- **Spec coverage:** goal/variance (Task 8 acceptance), knee-as-constant via passive observation (Task 4/8), PI + anti-windup (Task 2), no relay (never implemented — correct), PWM actuator (Task 6), duty clamp `[0.15,1.0]` + anti-windup (Task 2/6), aggregate duty over scanned set (Task 7), pure-CPU-threshold selection + self-exclusion + debounce (Task 5), sensor plausibility gate + EMA (Task 3/7), EXIT/signal SIGCONT-all safety (Task 6/7), `smc` crate with smctemp fallback gate (Task 0), env-var tuning + `--selftest` (Task 1/2). All present.
- **Residual hardware-dependent verification:** Tasks 3/4/7/8 use manual checks (hardware/process state) rather than unit tests — unavoidable for SMC + signals; the pure controller carries the unit tests.
- **Type consistency:** `Config` fields, `PiController::{new,update}`, `scan_managed`, `apply_duty`, `read_temp`, `fans_at_floor` names are used identically across tasks.
</content>
