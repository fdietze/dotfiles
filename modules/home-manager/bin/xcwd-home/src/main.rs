use std::path::PathBuf;
use xcwd_home::{apply_policy, cwd_of, focused_pid, is_kitty, kitty_cwd, leaf_pid};

fn main() {
    let home = PathBuf::from(std::env::var("HOME").expect("HOME unset"));
    let fallback = || println!("{}", home.display());

    let Some(pid) = focused_pid() else { return fallback() };

    // kitty (niri or X11): ask its remote-control socket directly. Skips /proc
    // traversal, which is doubly broken here — kitten __atexit__ helper
    // outranks the user shell in leaf_pid, and yama ptrace_scope=1 blocks
    // /proc/<pid>/cwd readlink for non-ancestor callers anyway.
    if is_kitty(pid) {
        if let Some(cwd) = kitty_cwd(pid) {
            println!("{}", apply_policy(&cwd, &home).display());
            return;
        }
    }

    let leaf = leaf_pid(pid);
    let Some(cwd) = cwd_of(leaf) else { return fallback() };
    println!("{}", apply_policy(&cwd, &home).display());
}
