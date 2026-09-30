//! Headless diagnostic for the SAME Rust subprocess adapter; this bypasses the Web UI.
#[path = "../src/protocol.rs"]
mod protocol;

fn main() {
    let action = std::env::args().nth(1).unwrap_or_else(|| "catalog".into());
    let request = format!(
        "tauri-probe-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let dispatch = if action == "catalog" {
        None
    } else {
        Some((action.as_str(), request.as_str()))
    };
    match tauri::async_runtime::block_on(protocol::run_helper(dispatch)) {
        Ok(reply) => {
            println!("{}", reply);
            if reply["status"] != "ok" {
                std::process::exit(1);
            }
        }
        Err(message) => {
            println!(
                "{}",
                serde_json::json!({"probeStatus":"transport-error","message":message})
            );
            std::process::exit(1);
        }
    }
}
