//! TTY watchdog: restarts Quickshell when returning to the Wayland VT.
//! wlroots destroys layer-shell surfaces on VT switch, so the panel is lost
//! until we restart the quickshell process.

use std::process::Command;
use std::thread;
use std::time::Duration;

fn main() {
    let code = run();
    std::process::exit(code);
}

fn run() -> i32 {
    let wayland_vt = match read_active_vt() {
        Some(vt) => vt,
        None => return 1,
    };
    let mut last_vt = wayland_vt.clone();

    loop {
        thread::sleep(Duration::from_millis(500));
        let current_vt = match read_active_vt() {
            Some(v) => v,
            None => continue,
        };
        // Switched back from another TTY to the Wayland TTY
        if last_vt != wayland_vt && current_vt == wayland_vt {
            thread::sleep(Duration::from_millis(500));
            let _ = Command::new("pkill").args(["-x", "quickshell"]).status();
        }
        last_vt = current_vt;
    }
}

fn read_active_vt() -> Option<String> {
    let s = std::fs::read_to_string("/sys/class/tty/tty0/active").ok()?;
    Some(s.trim().to_string())
}
