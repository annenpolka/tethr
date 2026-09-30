use serde::Deserialize;
use serde_json::Value;
use std::{path::Path, process::Stdio, time::Duration};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    protocol_version: u64,
    helper_path: String,
}

fn validate(value: Value, dispatch: Option<(&str, &str)>) -> Result<Value, String> {
    if value["protocolVersion"].as_u64() != Some(1) {
        return Err("helper の protocolVersion が 1 ではありません".into());
    }
    let status = value["status"]
        .as_str()
        .ok_or("helper の status がありません")?;
    if !matches!(status, "ok" | "error") {
        return Err("helper の status が不正です".into());
    }
    if let Some((action, request)) = dispatch {
        if value["actionID"].as_str() != Some(action)
            || value["requestID"].as_str() != Some(request)
        {
            return Err(
                "helper 応答の宛先または requestID が一致しません。到達状態は不明です。".into(),
            );
        }
        if value["message"].as_str().is_none() {
            return Err("helper 応答の message が不正です".into());
        }
    } else if status == "ok" {
        let items = value["items"]
            .as_array()
            .ok_or("helper の items が配列ではありません")?;
        let mut ids = std::collections::HashSet::new();
        for item in items {
            for field in ["id", "title", "subtitle", "keywords", "kind"] {
                if item[field].as_str().is_none() {
                    return Err(format!("catalog の {field} が不正です"));
                }
            }
            if !ids.insert(item["id"].as_str().unwrap()) {
                return Err("catalog に重複した ID があります".into());
            }
            if !matches!(
                item["kind"].as_str(),
                Some("terminal" | "command" | "application")
            ) {
                return Err("catalog の kind が不正です".into());
            }
        }
    }
    if status == "error" && value["message"].as_str().is_none() {
        return Err("helper エラーの message が不正です".into());
    }
    Ok(value)
}

pub async fn run_helper(dispatch: Option<(&str, &str)>) -> Result<Value, String> {
    let config_path = std::env::var("TETHR_LAB_CONFIG").map_err(|_| {
        "TETHR_LAB_CONFIG がありません。設定ファイルを指定してアプリを起動してください。"
    })?;
    run_helper_at(&config_path, dispatch).await
}

async fn run_helper_at(config_path: &str, dispatch: Option<(&str, &str)>) -> Result<Value, String> {
    if !Path::new(&config_path).is_absolute() {
        return Err("TETHR_LAB_CONFIG は絶対パスで指定してください".into());
    }
    let config: Config = serde_json::from_slice(
        &std::fs::read(&config_path).map_err(|e| format!("設定ファイルを読めません: {e}"))?,
    )
    .map_err(|e| format!("設定ファイルの JSON が不正です: {e}"))?;
    if config.protocol_version != 1 || !Path::new(&config.helper_path).is_absolute() {
        return Err("設定の protocolVersion または helperPath が不正です".into());
    }
    let mut command = tokio::process::Command::new(&config.helper_path);
    command
        .arg("--config")
        .arg(&config_path)
        .stdin(Stdio::null())
        .kill_on_drop(true);
    match dispatch {
        Some((action, request)) => {
            if action.is_empty() || request.is_empty() {
                return Err("操作 ID と request ID は必須です".into());
            }
            command
                .arg("dispatch")
                .arg(action)
                .arg("--request-id")
                .arg(request);
        }
        None => {
            command.arg("catalog");
        }
    }
    let output = tokio::time::timeout(Duration::from_secs(30), command.output())
        .await
        .map_err(|_| {
            "helper が 30 秒以内に応答しませんでした。到達状態は不明です。自動再送はしません。"
                .to_string()
        })?
        .map_err(|e| format!("helper を実行できません: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "helper の終了状態: {}\n{}\n{}",
            output.status,
            String::from_utf8_lossy(&output.stderr),
            String::from_utf8_lossy(&output.stdout)
        ));
    }
    let value: Value = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("helper の JSON が不正です: {e}"))?;
    validate(value, dispatch)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn rejects_misrouted_or_invalid_responses() {
        assert!(validate(json!({"protocolVersion":1,"status":"ok","actionID":"wrong","requestID":"r","message":"done"}), Some(("a","r"))).is_err());
        assert!(validate(
            json!({"protocolVersion":1,"status":"maybe","items":[]}),
            None
        )
        .is_err());
        assert!(validate(
            json!({"protocolVersion":1,"status":"ok","items":[{"id":"a"}]}),
            None
        )
        .is_err());
    }
    #[test]
    fn preserves_a_correlated_failure_without_marking_success() {
        let value = json!({"protocolVersion":1,"status":"error","actionID":"a","requestID":"r","message":"unavailable","errorCode":"unavailable"});
        assert_eq!(validate(value.clone(), Some(("a", "r"))).unwrap(), value);
    }

    #[cfg(unix)]
    #[test]
    fn actual_child_process_preserves_arguments_and_rejects_bad_output() {
        use std::os::unix::fs::PermissionsExt;
        let root = std::env::temp_dir().join(format!(
            "tethr-rust-fixture-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        struct Cleanup(std::path::PathBuf);
        impl Drop for Cleanup {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let _cleanup = Cleanup(root.clone());
        let helper = root.join("helper with spaces");
        let config = root.join("config with spaces.json");
        std::fs::write(
            &config,
            json!({"protocolVersion":1,"helperPath":helper}).to_string(),
        )
        .unwrap();
        std::fs::write(&helper, r##"#!/bin/sh
if [ "$3" = catalog ]; then
  printf '{"protocolVersion":1,"status":"ok","items":[]}'
else
  [ "$#" = 6 ] || exit 9
  [ "$1" = --config ] || exit 10
  [ "$5" = --request-id ] || exit 11
  printf '{"protocolVersion":1,"status":"ok","actionID":"%s","requestID":"%s","message":"fixture received"}' "$4" "$6"
fi
"##).unwrap();
        std::fs::set_permissions(&helper, std::fs::Permissions::from_mode(0o700)).unwrap();
        tauri::async_runtime::block_on(async {
            assert_eq!(
                run_helper_at(config.to_str().unwrap(), None).await.unwrap()["items"],
                json!([])
            );
            let reply = run_helper_at(
                config.to_str().unwrap(),
                Some(("action with spaces; literal", "request with spaces")),
            )
            .await
            .unwrap();
            assert_eq!(reply["actionID"], "action with spaces; literal");
            std::fs::write(&helper, "#!/bin/sh\nprintf 'invalid json'\n").unwrap();
            assert!(run_helper_at(config.to_str().unwrap(), None)
                .await
                .unwrap_err()
                .contains("JSON"));
            std::fs::write(&helper, "#!/bin/sh\nprintf 'fixture refused' >&2\nexit 7\n").unwrap();
            assert!(run_helper_at(config.to_str().unwrap(), None)
                .await
                .unwrap_err()
                .contains("fixture refused"));
        });
    }
}
