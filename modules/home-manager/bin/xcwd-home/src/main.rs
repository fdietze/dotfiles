use std::path::PathBuf;
use xcwd_home::{apply_policy, cwd_of, focused_pid, leaf_pid};

fn main() {
    let home = PathBuf::from(std::env::var("HOME").expect("HOME unset"));
    let fallback = || println!("{}", home.display());

    let Some(pid) = focused_pid() else { return fallback() };
    let leaf = leaf_pid(pid);
    let Some(cwd) = cwd_of(leaf) else { return fallback() };
    println!("{}", apply_policy(&cwd, &home).display());
}
