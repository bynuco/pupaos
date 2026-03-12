//! Lists windows on the focused output's current workspace via Wayfire IPC.
//! Output: WAYFIRE_WORKSPACE_OK then lines of app_id<TAB>title.
//! Called by Quickshell bottom panel to filter task bar by workspace.
//!
//! Current workspace detection (most-to-least reliable):
//!   1. get-focused-view geometry / output size  → most reliable
//!   2. get-focused-output workspace {x,y} field → fallback
//! View workspace: derived from geometry / output size (same virtual-desktop math).

use quickshell_wayfire::{find_socket, ipc_send, output_id_of, parse_int, ws_coords_opt};
use serde_json::{Map, Value};
use std::env;
use std::os::unix::net::UnixStream;

const WAYFIRE_WORKSPACE_OK: &str = "WAYFIRE_WORKSPACE_OK";

fn main() {
    std::process::exit(run());
}

fn run() -> i32 {
    let arg = env::args().nth(1);
    let sock_path = match find_socket(arg.as_deref()) {
        Some(p) => p,
        None => { eprintln!("WAYFIRE_SOCKET bulunamadı."); return 1; }
    };
    let mut client = match UnixStream::connect(&sock_path) {
        Ok(c) => c,
        Err(e) => { eprintln!("socket: {}", e); return 1; }
    };
    if let Err(e) = run_workspace_windows(&mut client) {
        eprintln!("{}", e);
        return 1;
    }
    0
}

/// Returns which workspace (x, y) a view is on, given its geometry and output size.
/// Wayfire tiles workspaces as a grid: workspace (wx, wy) occupies the rectangle
/// [wx*W .. (wx+1)*W) × [wy*H .. (wy+1)*H) in the virtual desktop.
fn geometry_workspace(geom: &Map<String, Value>, out_w: i64, out_h: i64) -> Option<(i64, i64)> {
    if out_w <= 0 || out_h <= 0 { return None; }
    let x = parse_int(geom.get("x"))?;
    let y = parse_int(geom.get("y"))?;
    Some((x.div_euclid(out_w), y.div_euclid(out_h)))
}

fn run_workspace_windows(client: &mut UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    // List all views
    let views_value = ipc_send(client, "window-rules/list-views", None)
        .or_else(|_| ipc_send(client, "ipc-rules/list-views", None))?;
    let views = extract_views_array(&views_value)?;
    if views.is_empty() {
        println!("{}", WAYFIRE_WORKSPACE_OK);
        return Ok(());
    }

    // Output geometry (width, height) — needed to compute workspace from view geometry.
    // This field in get-focused-output is reliable even if the workspace {x,y} field isn't.
    let out_resp = ipc_send(client, "window-rules/get-focused-output", None)
        .or_else(|_| ipc_send(client, "ipc-rules/get-focused-output", None)).ok();

    let mut cur_out: Option<i64> = None;
    let mut out_w: i64 = 0;
    let mut out_h: i64 = 0;
    let mut out_ws_field: Option<(i64, i64)> = None;  // workspace {x,y} from output (fallback)

    if let Some(ref resp) = out_resp {
        let info = resp.get("info").and_then(|v| v.as_object()).or_else(|| resp.as_object());
        if let Some(obj) = info {
            cur_out = parse_int(obj.get("id")).or_else(|| output_id_of(obj));
            out_ws_field = ws_coords_opt(obj);
            if let Some(geom) = obj.get("geometry").and_then(|g| g.as_object()) {
                out_w = parse_int(geom.get("width")).unwrap_or(0);
                out_h = parse_int(geom.get("height")).unwrap_or(0);
            }
        }
    }

    // Method 1: focused view's geometry → current workspace (most reliable)
    // The focused view is always on the current workspace, so its geometry tells us
    // exactly which workspace is active — even if get-focused-output's workspace field lags.
    let mut cur_ws: Option<(i64, i64)> = None;

    let focused_resp = ipc_send(client, "window-rules/get-focused-view", None).ok();
    if let Some(ref resp) = focused_resp {
        let info = resp.get("info").and_then(|v| v.as_object()).or_else(|| resp.as_object());
        if let Some(obj) = info {
            if let Some(geom) = obj.get("geometry").and_then(|g| g.as_object()) {
                cur_ws = geometry_workspace(geom, out_w, out_h);
            }
            if cur_out.is_none() { cur_out = output_id_of(obj); }
        }
    }

    // Method 2: last activated view in list-views
    if cur_ws.is_none() {
        for v in views.iter().filter_map(|v| v.as_object()) {
            let activated = v.get("activated").and_then(|a| a.as_bool()).unwrap_or(false)
                || v.get("state").and_then(|s| s.as_object())
                    .and_then(|s| s.get("activated")).and_then(|a| a.as_bool()).unwrap_or(false);
            if activated {
                if let Some(geom) = v.get("geometry").and_then(|g| g.as_object()) {
                    cur_ws = geometry_workspace(geom, out_w, out_h);
                    if cur_out.is_none() { cur_out = output_id_of(v); }
                    break;
                }
            }
        }
    }

    // Method 3: get-focused-output's workspace {x,y} field (may lag after ws switch)
    if cur_ws.is_none() {
        cur_ws = out_ws_field;
    }

    let Some(cur_ws) = cur_ws else {
        println!("{}", WAYFIRE_WORKSPACE_OK);
        return Ok(());
    };

    // Filter views: same output (multi-monitor) + same workspace (computed from geometry)
    let mut matching: Vec<(String, String)> = Vec::new();
    for v in &views {
        let v = match v.as_object() { Some(o) => o, None => continue };

        if v.get("role").and_then(|r| r.as_str()) != Some("toplevel") { continue; }
        if v.get("type").and_then(|t| t.as_str())
            .map(|t| t == "background" || t == "overlay").unwrap_or(false) { continue; }

        // Output filter (multi-monitor)
        let v_out = output_id_of(v);
        if let (Some(co), Some(vo)) = (cur_out, v_out) {
            if co != vo { continue; }
        }

        // Workspace filter via geometry
        let v_ws = v.get("geometry")
            .and_then(|g| g.as_object())
            .and_then(|g| geometry_workspace(g, out_w, out_h));
        match v_ws {
            Some(ws) if ws == cur_ws => {}
            _ => continue,
        }

        let app_id = v.get("app-id").or_else(|| v.get("app_id"))
            .and_then(|a| a.as_str()).unwrap_or("").trim().to_lowercase();
        if app_id.is_empty() { continue; }

        let title = v.get("title").and_then(|t| t.as_str()).unwrap_or("").trim().replace('\t', " ").replace('\n', " ");
        matching.push((app_id, title));
    }

    println!("{}", WAYFIRE_WORKSPACE_OK);
    for (app_id, title) in matching {
        println!("{}\t{}", app_id, title);
    }
    Ok(())
}

fn extract_views_array(value: &Value) -> Result<Vec<Value>, Box<dyn std::error::Error>> {
    if let Some(arr) = value.as_array() { return Ok(arr.clone()); }
    if let Some(obj) = value.as_object() {
        if let Some(arr) = obj.get("views").and_then(|v| v.as_array()) { return Ok(arr.clone()); }
        if let Some(arr) = obj.get("info").and_then(|v| v.as_array()) { return Ok(arr.clone()); }
    }
    Ok(Vec::new())
}
