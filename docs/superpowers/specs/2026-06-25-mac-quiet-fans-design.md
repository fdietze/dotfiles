# mac-quiet-fans — design

`~/projects/dotfiles/home/bin/mac-quiet-fans`

## Problem

On this Apple Silicon Mac (8 P-cores + 4 E-cores), background compute jobs
(e.g. rust binaries under `~/.cache/...`) drive the CPU die to ~78°C+ and
eventually spin the fans up. The machine is shared with other users; loud fans
annoy them. We want to keep running heavy work **at near-full speed when
thermals allow**, but hold the fans quiet by throttling our own hot processes
when the chip approaches the temperature where fans ramp.

We can only signal our own (`felix`-owned) processes; other users' load is an
uncontrollable disturbance.

## Goal (precise)

**Keep the fans quiet**, which decomposes into two sub-goals, both about fans:

1. **Stay below the fan knee** — the die temperature at which the OS commands
   the fans off their floor. Keep *mean* temp under it.
2. **Keep temperature flat** — low variance. Fans react to *change*; an
   oscillating temperature makes fans hunt up/down (audible), which is worse
   than a steady slightly-higher temperature.

Design rule: **hold die temperature flat, just under the fan knee.** Flat beats
low. Variance matters more than mean.

Temperature is the *steering signal*, not the prize. The prize is fan RPM at its
floor. We steer on temperature because it is the fast, controllable proxy; fan
RPM is the slow ground truth used only to find the setpoint.

## Sensed signals (SMC, via `smc` crate)

| signal | SMC key | role |
|---|---|---|
| CPU die temp | CPU temp key(s) (confirmed in spike) | live control signal |
| fan target RPM | `F0Tg` / `F1Tg` | knee detection (commanded, *leads* actual) |
| fan actual RPM | `F0Ac` / `F1Ac` | verification |
| fan floor | `F0Mn` (= 2317 on this machine) | "fans asleep" reference |

Current readings establish baseline: at ~78°C both fans sit at floor (~2300
RPM), so the knee is **above 78°C** — there is thermal headroom.

`F0Tg` (commanded target) leads `F0Ac` (physical RPM): the OS computes the
target from temperature quickly while the blade spins up slowly. So `F0Tg`
lifting off `F0Mn` is a **crisp early-warning** that the knee was crossed.

## Control design

### Plant model

Thermal system ≈ first-order lag + deadtime, two stacked time constants:
- silicon die: fast, τ ≈ ~1 s
- heatsink/chassis: slow, τ ≈ tens of s
- deadtime L: power → heat → sensor propagation + sensor lag

Input `u` = duty cycle (fraction of time managed processes are allowed to run,
0..1). Output `y` = die temperature.

### Why not bang-bang

A relay (SIGSTOP above target / SIGCONT below) **always limit-cycles** — it
never settles, it oscillates around the target. Amplitude grows with deadtime +
hysteresis band. Oscillating temperature → fan hunting → exactly the audible
problem we are fighting. **Rejected.** Smoothness is the objective; relay
control is structurally incapable of it.

### Controller: conservative integral-led PI

- Continuous proportional + integral on the temperature error
  `e = setpoint − temp`.
- **No derivative** — the temp sensor is 0.1°C-quantized and noisy; D amplifies
  noise.
- **No relay auto-tune, no controllability probe** (rejected as brittle: a
  probe can misfire, and the relay injects the oscillation we hate). Instead:
  fixed conservative gains chosen for stability margin, not speed.
  **Slow-but-smooth is exactly what fan-quietness wants.**
- The **integral term self-adapts** to whatever baseline heat exists (our jobs,
  other users, ambient) — it quietly offsets the disturbance regardless of
  gains. The gains only need to be in the stable ballpark; the integrator does
  the real disturbance rejection.
- `τ` for setting `Ti ≈ τ` is eyeballed from data we already collect during knee
  observation (a step response) — no separate test (DRY). A crude `τ` estimate
  plus a large gain-margin factor is stable because the loop is intentionally
  slow.

### Setpoint

`setpoint = knee − margin` (margin default **3°C**).

The **knee is a constant** — the temp→fan-RPM map is a fixed firmware table.
Learn it **once** by **passive observation**: log the die temp at the moment
`F0Tg` first lifts off `F0Mn` during normal use (our jobs already heat the
chip — no disruptive forced ramp). Store the number in config; reuse forever
(until hardware/OS change).

### Actuator: PWM via SIGSTOP/SIGCONT

The PI output is a duty cycle `d ∈ [0,1]`. We realise it as PWM: within a fixed
window `W ≈ 200 ms`, let managed processes run `d·W`, pause the rest. Because
`W ≪ die τ`, the die sees a smooth *average* power — a binary actuator made
effectively analog. The duty change is **slew-limited** for smoothness.

### Duty clamp `[0.15, 1.0]` + anti-windup

Clamp `d` to `[d_min, d_max] = [0.15, 1.0]`:
- We have authority → PI regulates somewhere in the middle.
- Baseline (others') heat already exceeds target → PI pushes down and **parks at
  `d_min`**, never starving our work to zero. This is the "always make progress"
  floor — emergent from one clamp, **no special-case branch** detecting whose
  heat it is. (Mental model: *multiply by zero* — driving our duty to 0% when it
  can't cool the chip anyway is pure loss.)
- Cool again → PI climbs back toward 1.0 → full performance returns.

**Anti-windup:** when parked at a clamp and still in error, stop the integrator
growing, so it cannot overshoot when conditions ease (graceful give-up, free).

## Process selection — hands-off, no PID argument

The user launches/stops multiple heavy jobs in parallel; the script must manage
them **without being told which**. The managed set is one **aggregate
actuator** (temperature is the sum of all heat) — a single duty `d` is applied
to the whole set at once.

### Selection policy: pure CPU threshold (no denylist)

Every **3 s**, scan processes; the managed set =
```
user == felix  AND  %CPU ≥ threshold (default 50%)  AND  pid ∉ {self + own children}
```
- **No name denylist** — user's explicit choice. Any of the user's processes
  that sustains high CPU is managed, including a hot interactive app. Accepted:
  on this machine the heavy procs are batch compute; interactive tools stay low.
- **Self-exclusion is non-negotiable** (correctness, not policy): the controller
  must never SIGSTOP its own PID/process group, or it deadlocks. Only the user's
  processes are signalable anyway.
- **Debounce (stability, not policy):** require CPU above threshold for ~3 s
  before grabbing, and below for ~3 s before releasing, so brief spikes (quick
  git, page load) don't cause STOP/CONT churn or a flapping managed set.
- **Children** that run hot appear as their own heavy procs → caught
  automatically; no process-group logic needed.

### Set transitions

- New hot proc → add.
- Proc exits or cools (after debounce) → drop it **and `SIGCONT` it on the way
  out** — never leave a dropped/exited proc paused.

## Architecture (functional core / imperative shell)

Single rust-script file, conceptually three units:

1. **sensor** — `smc` crate reads; plausibility gate (reject 0.0°C and >110°C
   implausibles — *map ≠ territory*, cf. the prototype where `osx-cpu-temp`
   returned 0.0°C on Apple Silicon); light EMA filter on temp.
2. **controller** — **pure function** `(temp, setpoint, state) → (duty,
   state')`. PI math + anti-windup. Unit-testable with synthetic temp series,
   no I/O.
3. **actuator + selector** — imperative shell: scan processes, apply PWM duty
   via SIGSTOP/SIGCONT, slew-limit, handle set transitions.

## Safety

- **EXIT trap** (panic/SIGINT/SIGTERM/normal exit) → `SIGCONT` every managed
  process. Never leave anything paused. This is the single most important
  failure-mode guard (*multiply by zero*: one stuck-paused process = lost work).
- **Sensor plausibility gate** — ignore implausible reads; hold last good value.
- **OS thermal throttle is the backstop below us** — the firmware will throttle
  near ~100°C regardless; our loop sits comfortably below it. Defense in depth:
  our loop is a comfort governor, not a safety system, and it fails safe.

## Implementation form

- File: `~/projects/dotfiles/home/bin/mac-quiet-fans`
- rust-script single file:
  - `#!/usr/bin/env nix-shell`
  - `#!nix-shell -i rust-script -p rust-script cargo rustc`
  - inline cargo dependency: `smc = "0.2"` (edition 2018 → builds on the
    nixpkgs `rustc 1.83`; no toolchain bump, unlike `smc-lib` which needs 1.92)
- **Tuning params as env vars / CLI args** (target/knee, margin, Kp, Ti, CPU
  threshold, debounce, window W) → retune without recompiling.
- `--selftest` flag runs in-file unit tests of the pure controller function
  (synthetic temp series → assert duty), satisfying design-for-testability in a
  single executable.
- Naming: outcome-named (`mac-quiet-fans`) — it does not throttle the *fan*, it
  throttles CPU processes to keep the fan quiet; the filename states the outcome
  you run it for.

## First implementation step — verification spike (map ≠ territory)

Before building the loop, a ~15-line rust-script spike must confirm on **this**
machine that the `smc` crate:
- returns a sane CPU die temp (≈ matches the prototype `smctemp` ~78°C), and
- returns real fan RPM (`F0Tg`/`F0Ac` ≈ 2300 at floor).

If the crate chokes on Apple Silicon keys, fall back to **packaging the proven
`smctemp` C++ in the mac flake** (build flag `-Wno-format-security`) and shelling
out — the design above is otherwise unchanged (sensing is an isolated unit).

## Rejected alternatives (summary)

- **bang-bang / relay** — limit-cycles → fan hunting. The core thing to avoid.
- **`nice`/`renice`** — empirically useless here: the hot proc was already
  `nice 19` yet still ~80% CPU and hot, because nothing else contends.
- **`taskpolicy -b` (E-core demotion) as the fine actuator** — coarse (on/off),
  can't hit a target. Possible complementary coarse stage, not the controller.
- **`cpulimit` as actuator** — adds a dependency + a second process to
  supervise; PWM via STOP/CONT is self-contained.
- **relay auto-tune / controllability probe** — brittle; injects oscillation.
- **hand-rolled SMC via python ctypes** — we'd own a fragile FFI binding
  (struct layout, AS key curation); reuse the `smc` crate instead (DRY).
- **`smc-lib` crate** — nicer/fresher but needs rustc 1.92 (toolchain bump).
- **steer directly on fan RPM** — truest signal but slow/laggy → coarse control;
  use it only to find the (constant) setpoint.
</content>
</invoke>
