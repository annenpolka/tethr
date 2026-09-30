# tethr — 3種類の比較試作

> **片付け済み（2026-09-12）:** 試作アプリと試験用tmuxは停止し、paneru設定は変更前へ復元しました。以下は実装・検証時の記録です。再開時は `python3 scripts/lab.py prepare --fresh`、必要に応じて `python3 scripts/paneru-config.py apply` を実行してください。

2026-09-12。実装場所は `/Users/annenpolka/ghq/github.com/annenpolka/tethr/prototypes/lab`。起動用ビルドも配置済みです。採用スタックはまだ決めていません。

## 今回できたこと

| 試作 | 実際の実装 | 確認できた入口 |
| --- | --- | --- |
| Native | Swift / AppKit、NSPanel | 実際の `.app` の検索欄とEnter |
| Tauri | Tauri 2 / TypeScript / Rust / WKWebView | 実際の `.app` のWeb UI → Rust IPC |
| OpenTUI | Bun 1.4.0 / OpenTUI Core 0.5.11 | ビルド済みコードを実PTYで起動し、文字入力とEnter |

3種類が**共通のSwift helper**を呼びます。UI方式を比較する試作で、3種類の独立したバックエンドの比較ではありません。

共通の操作は「同じ試験用シェルで続ける」「リポジトリの変更状況を見る」「指定アプリを起動・前面化する」です。検索、上下選択、Enter、結果表示、重複送信抑制、Escを実装しました。アプリ操作はUIを隠してから送り、完了時にUIを再表示しない構成です。

## すぐ試す

```sh
cd /Users/annenpolka/ghq/github.com/annenpolka/tethr/prototypes/lab
python3 scripts/lab.py run native
python3 scripts/lab.py run tauri

# OpenTUIは、利用者が用意した専用の端末窓で実行
python3 scripts/lab.py run opentui
```

検索欄に `terminal` と入力してEnterを押すと、同じ試験用シェルのカウンターが進みます。`git` なら変更一覧、`fixture` なら試験用受信アプリA/Bです。通常のtmux作業とは別の専用socketを使います。

Escで閉じたNative/Tauriは、同じrunコマンドで再表示できます。設定を変更した場合は、その試作を終了してから起動してください。`open`で再表示するだけでは実行中プロセスの設定は変わりません。

再ビルド・テスト・設定再生成の説明は、リポジトリの `prototypes/lab/README.md` にあります。

## paneruへの対応

`~/.paneru.toml` に、既存設定を残して3つの限定ルールを追加しました。バックアップと変更前後のSHA-256を保存し、paneruは再起動していません。

- Native: `com.tethr.lab.native`
- Tauri: `com.tethr.lab.tauri`
- OpenTUI: Ghosttyのbundle ID **かつ** 窓タイトルが正確に `tethr · OpenTUI`

通常のGhostty窓全体は対象にしていません。

| 対象 | 今回の実測 |
| --- | --- |
| Tauri | 実窓が `paneru query state` で `floating: true` |
| Native | NSPanelは実画面・AXで確認。paneru queryには現れず、設定ルールに一致したかは未確認 |
| OpenTUI | 正確なタイトルのOSC出力は実PTYで確認。Ghostty実窓のfloatingは未確認 |

floatingはタイル配置から外す設定です。paneruのフォーカス追従など、すべての挙動を無効にする意味ではありません。OpenTUIの起動後にタイトルを変えるだけで既存窓が再分類される保証はないため、専用窓の作成時タイトルも考慮する必要があります。詳細と手動の起動候補は `opentui/GHOSTTY.md` に残しました。

復元する場合は、LABディレクトリで次を実行します。適用後に別の設定変更があれば上書きせず停止します。

```sh
python3 scripts/paneru-config.py restore
```

## 実行して確かめたこと

**同じシェルが3つのUIをまたいで続きました。** Native実画面 → Tauri実画面 → OpenTUI実PTYの順でカウンターが `1 → 2 → 3`。shell PID `56584`、nonce、cwdが一致し、シェルから起動された子プロセスの受信記録でも確認しました。OpenTUIをEscで終了した後も、そのシェルが残りました。

**run-or-raiseは外部のOS観測でも確認しました。** 新しいhelperで試験用Bが未起動であることを事前確認し、次を実行しました。

| ケース | 結果 |
| --- | --- |
| 未起動Bの起動 | PASS。応答の `wasRunning=false` も検証 |
| 起動済みBの前面化 | PASS。同じPID |
| すでに前面のBを再指定 | PASS。同じPID |
| 前面化しないのに成功だけ返す故障版 | 期待どおりFAIL。外部観測で偽成功を検出 |

各ケース約5秒・172サンプルを採取し、観測の正常終了、件数、時間幅、要求IDと応答ID、末尾の安定した前面状態を確認しました。さらにNativeのUIからA、TauriのUIからBへの切替も実行し、各6秒のOS観測の末尾で対象アプリが前面に残ることを確認しました。UI自動入力はアプリを指定する方式なので、これを宛先未指定のキーボード配送の証拠にはしていません。

自動テストはbackend 7件、Native非UI 3件、OpenTUI 7件、Tauri Web 11件・Rust 3件が成功しています。OpenTUIの試験には実際のnative rendererを含みます。これらは各層の試験で、31件のデスクトップE2E試験という意味ではありません。

実画面の確認でNativeのUI更新がメインスレッド外に出る不具合を見つけ、MainActorへ統一して修正しました。設定ファイルの読込もUIスレッドから外しました。独立Astraレビューから、共有helperの起動completionの競合、tmuxの位置による送信先再解決、cold起動試験と観測品質の判定も修正しています。Documents内の設定読込で待ちが発生したケースは、ghq配置からの起動では再現しませんでした。OS権限が原因だとは断定していません。

## まだ証明していないこと

- Ghostty実画面のOpenTUI。この環境のComputer UseツールがGhostty操作を禁止しているため **NOT_RUN**。別のUI自動化への迂回はしていません。
- 実際の日本語IMEの変換中・候補選択・確定Enter。コード上のガードや入力イベント試験と、実IMEの受け入れは別です。
- グローバルホットキーからの呼出し、宛先未指定のキーが狙った入力欄に届くこと、全Spaces・複数画面での挙動。
- 利用者の任意の既存tmux paneへの安全なコマンド投入。今回の継続は試験用の所有シェルに限定しています。
- 本物のエージェントへの出力転送・指示送信、hide中の長時間ジョブ、起動速度やLLMによる修正効率の比較。

この結果だけでスタックを採用するところまでは進めていません。まず同じ小さな用事を3種類で試せる状態になりました。

## 実画面

Nativeで1回目を実行した画面。

![Native試作](../../prototypes/lab/runtime/evidence/screenshots/tethr-native-prototype.png)

Tauriで同じシェルの2回目を実行した画面。

![Tauri試作](../../prototypes/lab/runtime/evidence/screenshots/tethr-tauri-prototype.png)

## 証拠の場所

リポジトリ内の `prototypes/lab/runtime/evidence/` に、最終helperの `activation/result.json`、各observer JSONL、`final-shared-shell.json`、実GUIのAX記録、paneru設定のバックアップ・ハッシュ、ビルド物のハッシュを保存しています。`runtime/`、依存、ビルド物はgit管理対象から外しています。コード・手順・本レポートはソースとして残しています。
