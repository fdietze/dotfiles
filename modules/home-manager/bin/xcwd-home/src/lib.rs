use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

pub fn children_of(pid: i32) -> Vec<i32> {
    fs::read_to_string(format!("/proc/{pid}/task/{pid}/children"))
        .unwrap_or_default()
        .split_ascii_whitespace()
        .filter_map(|s| s.parse().ok())
        .collect()
}

// Field 22 of /proc/<pid>/stat is starttime. The comm field (#2) is in parens and
// can contain spaces or ')', so split after the LAST ')' to find the rest reliably.
pub fn start_time(pid: i32) -> Option<u64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let after_comm = stat.rsplit_once(')').map(|(_, r)| r)?;
    after_comm.split_ascii_whitespace().nth(19)?.parse().ok()
}

pub fn leaf_pid(mut pid: i32) -> i32 {
    loop {
        let next = children_of(pid)
            .into_iter()
            .filter_map(|c| start_time(c).map(|t| (c, t)))
            .max_by_key(|&(_, t)| t)
            .map(|(c, _)| c);
        match next {
            Some(c) => pid = c,
            None => return pid,
        }
    }
}

pub fn cwd_of(pid: i32) -> Option<PathBuf> {
    fs::read_link(format!("/proc/{pid}/cwd")).ok()
}

pub fn apply_policy(dir: &Path, home: &Path) -> PathBuf {
    if !(dir.starts_with(home) || dir.starts_with("/tmp")) {
        return home.to_path_buf();
    }
    if let Ok(out) = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_owned();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    dir.to_path_buf()
}

// Tiny JSON field extractors — niri's focused-window and kitten @ ls outputs
// are small and we only need one field. Avoids pulling in serde_json (and the
// lockfile/network churn that adds under nix).
pub fn extract_pid(json: &str) -> Option<i32> {
    let i = json.find("\"pid\"")?;
    let rest = json[i + 5..].trim_start();
    let rest = rest.strip_prefix(':')?.trim_start();
    let end = rest
        .find(|c: char| !c.is_ascii_digit() && c != '-')
        .unwrap_or(rest.len());
    rest[..end].parse().ok()
}

// kitten @ ls JSON: top-level OS windows array, each containing tabs/windows
// objects. Only the inner window has a `cwd` field, so the first match is the
// target window's cwd (we filter to one via --match state:focused).
pub fn extract_cwd(json: &str) -> Option<String> {
    let i = json.find("\"cwd\"")?;
    let rest = json[i + 5..].trim_start();
    let rest = rest.strip_prefix(':')?.trim_start();
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    Some(rest[..end].to_owned())
}

// /proc/<pid>/comm of a kitty window process is ".kitty-wrapped" (nix wrapper)
// or "kitty". comm is world-readable (unlike /proc/<pid>/cwd), so this works
// even for non-ancestor windows under yama ptrace_scope=1.
pub fn is_kitty(pid: i32) -> bool {
    fs::read_to_string(format!("/proc/{pid}/comm"))
        .map(|c| c.contains("kitty"))
        .unwrap_or(false)
}

// PID of the focused window's owning process. niri exposes it via IPC; X11
// WMs (herbstluftwm) via xdotool. The pid is the terminal's server process —
// for kitty that owns the remote-control socket queried by kitty_cwd.
pub fn focused_pid() -> Option<i32> {
    if env::var_os("NIRI_SOCKET").is_some() {
        let out = Command::new("niri")
            .args(["msg", "-j", "focused-window"])
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        return extract_pid(std::str::from_utf8(&out.stdout).ok()?);
    }
    if env::var_os("DISPLAY").is_some() {
        let out = Command::new("xdotool")
            .args(["getactivewindow", "getwindowpid"])
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        return String::from_utf8(out.stdout).ok()?.trim().parse().ok();
    }
    None
}

// Query the focused kitty window's cwd via the per-PID remote control socket.
// Bypasses /proc traversal entirely: under yama ptrace_scope=1 a non-ancestor
// caller cannot readlink /proc/<shell>/cwd, and the leaf_pid heuristic picks
// kitty's __atexit__ helper over the user's shell anyway.
// Requires `allow_remote_control` + matching `listen_on` in kitty.conf
// (configured in modules/home-manager/shared.nix).
pub fn kitty_cwd(kitty_pid: i32) -> Option<PathBuf> {
    let sock = format!("unix:@kitty-{kitty_pid}");
    let out = Command::new("kitten")
        .args(["@", "--to", &sock, "ls", "--match", "state:focused"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = std::str::from_utf8(&out.stdout).ok()?;
    extract_cwd(s).map(PathBuf::from)
}

#[cfg(test)]
mod unit {
    use super::*;

    #[test]
    fn extract_pid_basic() {
        assert_eq!(extract_pid(r#"{"pid":12345}"#), Some(12345));
        assert_eq!(extract_pid(r#"{"title":"x","pid": 42 ,"y":1}"#), Some(42));
    }

    #[test]
    fn extract_pid_null() {
        assert_eq!(extract_pid(r#"{"pid":null}"#), None);
    }

    #[test]
    fn extract_pid_missing() {
        assert_eq!(extract_pid(r#"{"title":"x"}"#), None);
    }

    #[test]
    fn extract_cwd_basic() {
        let json = r#"[{"tabs":[{"windows":[{"cwd":"/home/x/p","pid":2}]}]}]"#;
        assert_eq!(extract_cwd(json), Some("/home/x/p".to_owned()));
    }

    #[test]
    fn policy_falls_back_when_out_of_scope() {
        let home = PathBuf::from("/home/somebody");
        assert_eq!(apply_policy(Path::new("/etc"), &home), home);
    }

    #[test]
    fn policy_passes_through_tmp() {
        let home = PathBuf::from("/home/somebody");
        assert_eq!(
            apply_policy(Path::new("/tmp"), &home),
            PathBuf::from("/tmp")
        );
    }

    #[test]
    fn policy_passes_through_home_subdir() {
        let home = PathBuf::from("/home/somebody");
        let dir = home.join("projects/x");
        // Not a git repo (path doesn't exist) — should pass through unchanged.
        assert_eq!(apply_policy(&dir, &home), dir);
    }
}
