mod protocol;

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tauri::Manager;

#[derive(Default)]
struct DispatchGate(Arc<AtomicBool>);

struct BusyGuard(Arc<AtomicBool>);
impl Drop for BusyGuard {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

#[tauri::command]
async fn load_catalog() -> Result<serde_json::Value, String> {
    protocol::run_helper(None).await
}

#[tauri::command]
async fn dispatch_action(
    action_id: String,
    request_id: String,
    gate: tauri::State<'_, DispatchGate>,
) -> Result<serde_json::Value, String> {
    if gate
        .0
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return Err("別の操作を実行中です。自動再送はしません。".into());
    }
    let _guard = BusyGuard(gate.0.clone());
    protocol::run_helper(Some((&action_id, &request_id))).await
}

fn main() {
    tauri::Builder::default()
        .manage(DispatchGate::default())
        .invoke_handler(tauri::generate_handler![load_catalog, dispatch_action])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                if let Err(error) = window.hide() {
                    eprintln!("window hide failed: {error}");
                }
            }
        })
        .build(tauri::generate_context!())
        .expect("could not build Tethr Tauri Lab")
        .run(|app, event| {
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { .. } = event {
                if let Some(window) = app.get_webview_window("main") {
                    // Only an explicit user reopen brings the UI back, never a helper completion.
                    let _ = window.unminimize();
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        });
}
