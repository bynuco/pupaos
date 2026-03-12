//! Sends a single Wayfire IPC command (e.g. expo/toggle).
//! Usage: wayfire-ipc [method]

use quickshell_wayfire::find_socket;
use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

fn main() {
    let code = run();
    std::process::exit(code);
}

fn run() -> i32 {
    let method = match env::args().nth(1) {
        Some(m) => m,
        None => {
            eprintln!("Usage: wayfire-ipc <method>");
            eprintln!("Example: wayfire-ipc expo/toggle");
            return 1;
        }
    };
    let sock_path = match find_socket(None) {
        Some(p) => p,
        None => {
            eprintln!("Error: IPC socket not found (WAYFIRE_SOCKET unset or socket missing)");
            return 1;
        }
    };

    let payload = serde_json::json!({ "method": method, "data": {} });
    let msg = match serde_json::to_vec(&payload) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("Error: {}", e);
            return 1;
        }
    };

    let mut client = match UnixStream::connect(&sock_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error connecting to Wayfire IPC: {}", e);
            return 1;
        }
    };

    let len: u32 = match msg.len().try_into() {
        Ok(l) => l,
        Err(_) => { eprintln!("Error: IPC payload too large"); return 1; }
    };
    if client.write_all(&len.to_le_bytes()).is_err() || client.write_all(&msg).is_err() {
        eprintln!("Error writing to Wayfire IPC");
        return 1;
    }
    if client.flush().is_err() {
        eprintln!("Error flushing Wayfire IPC connection");
        return 1;
    }

    // Read response so the command is acknowledged
    const MAX_RESPONSE: usize = 16 * 1024 * 1024; // 16 MB
    let mut len_buf = [0u8; 4];
    if client.read_exact(&mut len_buf).is_ok() {
        let n = u32::from_le_bytes(len_buf) as usize;
        if n <= MAX_RESPONSE {
            let mut buf = vec![0u8; n];
            let _ = client.read_exact(&mut buf);
        }
    }
    0
}
