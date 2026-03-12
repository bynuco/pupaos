//! Shared Wayfire IPC client logic for Quickshell panel helpers.
//!
//! Protocol: 4-byte little-endian length + JSON payload.

use serde_json::{Map, Value};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;

/// Finds the Wayfire IPC socket path using the same resolution order as the Python scripts.
pub fn find_socket(arg_from_qml: Option<&str>) -> Option<std::path::PathBuf> {
    // 1) Argument (panel QML passes this for the correct session)
    if let Some(p) = arg_from_qml {
        let p = p.trim();
        if !p.is_empty() && Path::new(p).exists() {
            return Some(p.into());
        }
    }

    // 2) /tmp/wayfire-socket.$UID file (written by wayfire.ini autostart)
    // SAFETY: getuid() is always safe to call on POSIX systems — it has no preconditions.
    let uid = unsafe { libc::getuid() };
    let sock_file = format!("/tmp/wayfire-socket.{}", uid);
    if let Ok(content) = std::fs::read_to_string(&sock_file) {
        let path = content.trim();
        if !path.is_empty() && Path::new(path).exists() {
            return Some(path.into());
        }
    }

    // 3) WAYFIRE_SOCKET env
    if let Ok(path) = std::env::var("WAYFIRE_SOCKET") {
        let path = path.trim();
        if !path.is_empty() && Path::new(path).exists() {
            return Some(path.into());
        }
    }

    // 4) Glob wayfire-wayland-*.socket in /run/user/$UID and /tmp
    let run_user = format!("/run/user/{}", uid as u32);
    for dir in [run_user.as_str(), "/tmp"] {
        let Ok(entries) = std::fs::read_dir(dir) else { continue };
        let mut names: Vec<_> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.file_name())
            .collect();
        names.sort();
        for name in names {
            let name = name.to_string_lossy();
            if name.starts_with("wayfire-wayland-") && name.ends_with(".socket") {
                let p = Path::new(dir).join(name.as_ref());
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }

    None
}

/// Maximum IPC response size accepted from the compositor (protects against malformed frames).
const MAX_IPC_RESPONSE: usize = 16 * 1024 * 1024; // 16 MB

/// Sends an IPC method and reads the JSON response. Uses 4-byte LE length prefix.
pub fn ipc_send(sock: &mut UnixStream, method: &str, data: Option<&Map<String, Value>>) -> std::io::Result<Value> {
    let payload = serde_json::json!({ "method": method, "data": data.unwrap_or(&Map::new()) });
    let msg = serde_json::to_vec(&payload).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    let len: u32 = msg.len().try_into().map_err(|_| {
        std::io::Error::new(std::io::ErrorKind::InvalidInput, "IPC payload too large")
    })?;
    sock.write_all(&len.to_le_bytes())?;
    sock.write_all(&msg)?;
    sock.flush()?;

    let mut len_buf = [0u8; 4];
    sock.read_exact(&mut len_buf)?;
    let n = u32::from_le_bytes(len_buf) as usize;
    if n > MAX_IPC_RESPONSE {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("IPC response too large: {} bytes", n),
        ));
    }
    let mut buf = vec![0u8; n];
    sock.read_exact(&mut buf)?;
    let response: Value = serde_json::from_slice(&buf).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    Ok(response)
}

/// Parse optional int from JSON value (handles number or string).
pub fn parse_int(val: Option<&Value>) -> Option<i64> {
    let v = val?;
    match v {
        Value::Number(n) => n.as_i64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

/// Extract workspace (x, y) or single index from view/output info.
pub fn wset_index_of(obj: &Map<String, Value>) -> Option<i64> {
    let idx = obj.get("wset-index").or_else(|| obj.get("wset_index"));
    let n = parse_int(idx)?;
    if n >= 0 { Some(n) } else { None }
}

pub fn output_id_of(obj: &Map<String, Value>) -> Option<i64> {
    let vid = obj.get("output-id").or_else(|| obj.get("output_id")).or_else(|| obj.get("output"));
    match vid? {
        Value::Object(m) => parse_int(m.get("id")),
        v => parse_int(Some(v)),
    }
}

/// Workspace coords from legacy API (workspace: {x,y} or workspace-x, workspace_y).
pub fn ws_coords(obj: &Map<String, Value>) -> (i64, i64) {
    if let Some(ws) = obj.get("workspace") {
        if let Some(m) = ws.as_object() {
            let x = m.get("x").and_then(|v| v.as_i64()).unwrap_or(0);
            let y = m.get("y").and_then(|v| v.as_i64()).unwrap_or(0);
            return (x, y);
        }
        if let Some(n) = ws.as_i64() {
            return (n, 0);
        }
    }
    let x = obj.get("workspace-x").or_else(|| obj.get("workspace_x")).and_then(|v| v.as_i64()).unwrap_or(0);
    let y = obj.get("workspace-y").or_else(|| obj.get("workspace_y")).and_then(|v| v.as_i64()).unwrap_or(0);
    (x, y)
}

/// Returns Some((x, y)) if workspace field exists, None if absent.
/// Unlike ws_coords, does not default to (0, 0) when field is missing.
pub fn ws_coords_opt(obj: &Map<String, Value>) -> Option<(i64, i64)> {
    if let Some(ws) = obj.get("workspace") {
        if let Some(m) = ws.as_object() {
            let x = m.get("x").and_then(|v| v.as_i64()).unwrap_or(0);
            let y = m.get("y").and_then(|v| v.as_i64()).unwrap_or(0);
            return Some((x, y));
        }
        if let Some(n) = ws.as_i64() {
            return Some((n, 0));
        }
    }
    let wx = obj.get("workspace-x").or_else(|| obj.get("workspace_x"));
    let wy = obj.get("workspace-y").or_else(|| obj.get("workspace_y"));
    if wx.is_some() || wy.is_some() {
        let x = wx.and_then(|v| v.as_i64()).unwrap_or(0);
        let y = wy.and_then(|v| v.as_i64()).unwrap_or(0);
        return Some((x, y));
    }
    None
}

pub fn is_activated(view: &Map<String, Value>) -> bool {
    let state = view.get("state").and_then(|v| v.as_object());
    let from_state = state.map(|s| {
        s.get("activated").and_then(|v| v.as_bool()).unwrap_or(false)
            || s.get("focused").and_then(|v| v.as_bool()).unwrap_or(false)
    }).unwrap_or(false);
    let from_view = view.get("activated").and_then(|v| v.as_bool()).unwrap_or(false)
        || view.get("focused").and_then(|v| v.as_bool()).unwrap_or(false)
        || view.get("is-focused").and_then(|v| v.as_bool()).unwrap_or(false);
    from_state || from_view
}
