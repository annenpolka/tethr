# Ghostty専用ウィンドウとpaneru

`src/main.ts`はrenderer作成直後に`renderer.setTerminalTitle("tethr · OpenTUI")`を呼ぶ。Core 0.5.11の実装はnative libraryへ渡すAPIである。コンパイル済みbundleを実PTYで起動し、正確な`OSC 0 ; tethr · OpenTUI BEL`とEsc終了コード0を確認した。証拠は`.runtime/evidence/title-pty.json`と`title-pty.bin`。これはGhosttyの実ウィンドウタイトルやpaneruのfloating状態を確認した証拠ではない。

## 起動後のタイトル変更だけでは足りない

paneru公式commit `627e2aacca9fae9f3a9223057423159c193f28c3`では、[タイトル変更イベント処理](https://github.com/karinushka/paneru/blob/627e2aacca9fae9f3a9223057423159c193f28c3/src/ecs/triggers.rs#L918-L931)はタイトルcacheの無効化だけである。[floatingルールの適用](https://github.com/karinushka/paneru/blob/627e2aacca9fae9f3a9223057423159c193f28c3/src/ecs/triggers.rs#L1146-L1195)は`Added<Window>`を対象とする。この版について「OSCでタイトルが変わればfloatingを再適用する」とは扱えない。ローカルpaneruがこのcommitと同一の実装かは別途確認が必要。

初期タイトルを既に指定したウィンドウを作る場合、事前のpaneru設定候補は次のとおり。このファイルの作成はユーザー設定を変更しない。

```toml
[windows.tethr_opentui]
bundle_id = "com.mitchellh.ghostty"
title = "^tethr · OpenTUI$"
floating = true
```

## 別プロセスで初期タイトルを渡す起動案

以下は**GUIでは未実行の手動起動候補**。インストール済みGhostty 1.3.1のCLI用である。専用GhosttyプロセスでTUIを直接起動する。既存ウィンドウの選択、paneへの入力、tmux attachは行わない。`-e`以降はargvをそのまま渡し、既存ユーザーshellの初期化を通さない。

ただし、`--window-save-state=never`は復元済みtabの重複を避ける一方、Ghostty内部でmacOS UserDefaultsの`NSQuitAlwaysKeepsWindows`を変更する。**設定無変更という条件では、この起動案を実行できない。** 設定への副作用なしで作成時からfloatingを保証する起動方法は、この調査では確立していない。ここでは起動もUserDefaultsの変更も行っていない。

```sh
tethr_opentui_dir='/Users/annenpolka/Documents/Codex/2026-09-12/new-chat/work/tethr/prototype-lab/opentui'
tethr_lab_config='/Users/annenpolka/Documents/Codex/2026-09-12/new-chat/work/tethr/prototype-lab/runtime/config.json'
cd "$tethr_opentui_dir"
bun run build
/usr/bin/open -n -a /Applications/Ghostty.app --args \
  '--title=tethr · OpenTUI' \
  --window-save-state=never \
  --wait-after-command=false \
  --quit-after-last-window-closed=true \
  "--working-directory=$tethr_opentui_dir" \
  -e /usr/bin/env "TETHR_LAB_CONFIG=$tethr_lab_config" \
  /opt/homebrew/bin/bun "$tethr_opentui_dir/dist/main.js"
```

通常Ghosttyと専用プロセスは同じbundle IDを持つ。`app.ghostty`の対象PIDが一意でなくなる場合、曖昧な対象への拒否を正しい結果として扱い、通常Ghosttyを起動・raiseできたという受入結果にしない。比較終了時は専用ウィンドウのEscでTUIを終了させる。app操作の時もUI破棄後にhelper応答と保存を待ち、その後TUIプロセスが終了するため、この待ち時間にGhosttyウィンドウだけを強制終了しない。

## 同じGhosttyプロセスに新規ウィンドウを作る別案

[公式AppleScript API](https://ghostty.org/docs/features/applescript)の`new surface configuration`には`command`、`initial working directory`、`environment variables`、`wait after command`がある。これを`new window with configuration`へ渡せば、新規ウィンドウを指定したプロセスで起動できる。既存paneへ`input text`や`send key`する必要はない。インストール済み`/Applications/Ghostty.app/Contents/Resources/Ghostty.sdef`でも確認済み。

ただし、このsurface configurationには初期titleがない。今回のpaneruソースでは、作成後のOpenTUIによるタイトル変更だけでfloatingになる保証がない。したがって、paneruの対象IDを固定した明示floating操作等を別途検証するまでは「作成時からfloating」の代用にはならない。今回はAppleScriptを実行していない。

## 一次資料と検証範囲

- [OpenTUI rendererの実API](https://github.com/anomalyco/opentui/blob/ac753b48d386707a931dcf881d0741905b64b4f9/packages/core/src/renderer.ts): `setTerminalTitle`。ローカル0.5.11の型宣言とnative呼び出しも照合した。
- [Ghostty title / command / initial-command](https://ghostty.org/docs/config/reference#title): `title`はウィンドウタイトルを強制し、プログラムのタイトル変更を無視する。同じ値をCLIとTUIで渡す設計。通常起動ではユーザーの固定title設定があれば、OpenTUIのOSC指定よりそちらが優先される。
- [Ghostty v1.3.1でのUserDefaults書き込み](https://github.com/ghostty-org/ghostty/blob/332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28/macos/Sources/App/macOS/AppDelegate.swift#L750-L762): `never`はfalseを書き込む。[release版のdefaults接続先](https://github.com/ghostty-org/ghostty/blob/332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28/macos/Sources/Helpers/Extensions/UserDefaults%2BExtension.swift)は通常の`.standard`であり、DEBUG限定のsuite環境変数で回避できるとはしない。
- [Ghostty公式リポジトリの別インスタンス復元に関する回答](https://github.com/ghostty-org/ghostty/discussions/9612): `open -na`だけでは保存状態を復元し得る。

今回変更後の`bun run typecheck`、`bun test --timeout 15000`（7件、42 assertions）、`bun run build`は成功。実PTYでタイトル制御列を確認。

Ghostty GUI操作とOpenTUIウィンドウのpaneru floating確認は**NOT_RUN**。親側のComputer UseによるGhostty状態取得が「Computer Use is not allowed to use app com.mitchellh.ghostty for safety reasons」と拒否されたため、AppleScript等へ迂回していない。物理IME、Ghostty内の実表示、ウィンドウ作成時のちらつき、設定副作用を伴うGUI起動も未検証。実renderer/PTY/共通helperの既存検証結果と、このGUI未実行を区別する。
