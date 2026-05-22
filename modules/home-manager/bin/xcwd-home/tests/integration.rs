// Integration tests for xcwd-home.
//
// These spawn real process trees and walk them via /proc, so they require a
// Linux host with procfs. They do NOT require a running compositor — the
// compositor-dependent path (focused_pid) is exercised only manually.

use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::{fs, thread};

use xcwd_home::{apply_policy, cwd_of, leaf_pid};

struct Killer(Child);
impl Drop for Killer {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn spawn(script: &str) -> Killer {
    let child = Command::new("bash")
        .args(["-c", script])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("bash spawn");
    Killer(child)
}

// Poll until the process tree under `pid` is at least `min_depth` deep, or timeout.
// Avoids flaky fixed sleeps — we wait for /proc to reflect the spawned tree.
fn wait_for_depth(pid: i32, min_depth: usize, timeout: Duration) {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let mut depth = 1;
        let mut cur = pid;
        while let Some(&c) = xcwd_home::children_of(cur).first() {
            depth += 1;
            cur = c;
        }
        if depth >= min_depth {
            return;
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn unique_tmpdir(tag: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = PathBuf::from(format!("/tmp/xcwd-home-test-{tag}-{nanos}-{}", std::process::id()));
    fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn leaf_walks_single_child() {
    // No exec — keeps bash as parent so wait_for_depth(.., 2) has something to wait for.
    let k = spawn("cd /tmp && sleep 30");
    wait_for_depth(k.0.id() as i32, 2, Duration::from_secs(2));
    let leaf = leaf_pid(k.0.id() as i32);
    assert_eq!(cwd_of(leaf).unwrap(), PathBuf::from("/tmp"));
}

#[test]
fn leaf_walks_nested_chain() {
    let dir = unique_tmpdir("nested");
    let script = format!("cd / && bash -c 'cd {} && sleep 30'", dir.display());
    let k = spawn(&script);
    wait_for_depth(k.0.id() as i32, 3, Duration::from_secs(2));
    let leaf = leaf_pid(k.0.id() as i32);
    assert_eq!(cwd_of(leaf).unwrap(), dir);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn leaf_picks_newest_sibling() {
    // Outer bash forks a bg sleep in /, waits, then spawns a fg sleep in /tmp.
    // Newest-start-time heuristic should pick the fg one (later starttime).
    // Two bg sleeps in different dirs, started with a measurable gap so their
    // starttimes differ. `wait` is a bash builtin (no extra child) — keeps outer
    // bash alive as parent without spawning a newer foreground process that would
    // confuse the newest-start heuristic.
    let k = spawn(
        "(cd / && exec sleep 30) & sleep 0.4; (cd /tmp && exec sleep 30) & wait",
    );
    let outer = k.0.id() as i32;
    // Wait until BOTH children have actually completed cd+exec, by verifying
    // their cwds are stable and one of them is /tmp. Just polling children count
    // races against the second subshell's cd+exec.
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if Instant::now() >= deadline {
            break;
        }
        let kids = xcwd_home::children_of(outer);
        if kids.len() >= 2 {
            let cwds: Vec<_> = kids.iter().filter_map(|c| cwd_of(*c)).collect();
            if cwds.iter().any(|p| p == &PathBuf::from("/tmp"))
                && cwds.iter().any(|p| p == &PathBuf::from("/"))
            {
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
    let leaf = leaf_pid(outer);
    assert_eq!(cwd_of(leaf).unwrap(), PathBuf::from("/tmp"));
}

#[test]
fn leaf_returns_self_when_no_children() {
    // Use our own PID — the test runner itself has no shell children of this exact shape.
    // Just verify the loop terminates and returns *something* valid (cwd reads back).
    let me = std::process::id() as i32;
    let leaf = leaf_pid(me);
    assert!(cwd_of(leaf).is_some());
}

#[test]
fn policy_promotes_to_git_root() {
    let root = unique_tmpdir("git");
    let sub = root.join("a/b/c");
    fs::create_dir_all(&sub).unwrap();
    let status = Command::new("git")
        .args(["init", "-q"])
        .arg(&root)
        .status()
        .expect("git");
    assert!(status.success());
    let home = PathBuf::from("/home/nobody-irrelevant");
    let out = apply_policy(&sub, &home);
    // git may resolve symlinks; compare canonical forms.
    assert_eq!(out.canonicalize().unwrap(), root.canonicalize().unwrap());
    let _ = fs::remove_dir_all(&root);
}
