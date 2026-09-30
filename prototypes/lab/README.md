# tethr prototype lab

> **片付け済み（2026-09-12）:** 試作アプリと試験用tmuxは停止し、paneru設定は変更前へ復元しました。以下は実装・検証時の記録です。再開時は `python3 scripts/lab.py prepare --fresh`、必要に応じて `python3 scripts/paneru-config.py apply` を実行してください。

実際に動く三つのUIを比べるための試作です。**OpenTUI/Bun、AppKit/Swift、Tauri/Web/Rustが、一つのSwift helperを共有します。** 三つの独立したバックエンド実装の性能比較ではありません。共通の動作とJSON契約は [CONTRACT.md](CONTRACT.md) にあります。

| UI | 実装と実行物 | 詳細 |
| --- | --- | --- |
| Native | AppKitのNSPanel・NSTextField・NSTableView。`native/dist/Tethr Native.app` | [native/README.md](native/README.md) |
| Tauri | WKWebView + TypeScript、Rustからhelperを実行。標準出力先は`tauri/src-tauri/target/release/bundle/macos/Tethr Tauri Lab.app` | [tauri/README.md](tauri/README.md) |
| OpenTUI | 本物のOpenTUI Core。`opentui/dist/main.js`をBunで実行。`node_modules`内のnative libraryも必要 | [opentui/README.md](opentui/README.md) |

## 最初に

macOSとPython 3が必要です（paneru設定用スクリプトはPython 3.11以降）。共通helperの動作にはtmux、gitを使います。ソースからのビルドにはAppleのSwift/開発ツール、OpenTUIにはBun、TauriにはBunとRust/Cargoが必要です。NativeはmacOS 13以降を対象としています。配布済みのNative/Tauri `.app`を動かすだけなら、そのUIのコンパイラやBunは不要です。

このセッションの希望に合わせ、**paneruは動かしたまま、試作の窓だけをfloatingにする限定ルールを事前に用意します。** [scripts/paneru-rules.toml](scripts/paneru-rules.toml) と [適用・検証メモ](scripts/paneru-rules.README.md) を参照してください。Native/Tauriは専用bundle ID、OpenTUIはGhosttyのbundle IDと正確なタイトル `tethr · OpenTUI` の組み合わせです。他のGhostty窓をまとめて対象にしません。

`lab.py`はこのルールの適用やpaneruの停止・再起動を行いません。今回の親による適用では、`~/.paneru.toml`へ三つの限定ルールを追加し、バックアップと変更前後のハッシュを保存しました。paneruは再起動していません。別環境での確認・適用・復元には専用スクリプトを使います。

```sh
python3 scripts/paneru-config.py check    # 読み取りで適用内容・既存ルールを確認
python3 scripts/paneru-config.py apply    # 限定ルールを追加し、backup/hashを保存
python3 scripts/paneru-config.py restore  # 適用後に設定が変わっていない場合だけ復元
```

既存の競合ルールや、適用後の変更があるとスクリプトは停止します。設定全体をfragmentで置き換えません。ルールの記述・適用記録と、表示中の窓への実適用は別です。今回の実画面ではTauriの`floating=true`を観測しました。NativeのNSPanelはAXで可視でしたがpaneru queryには現れず、ルール一致を確認したとは言えません。

## 共通コマンド

このREADMEがあるディレクトリで実行します。スクリプトは自身の位置からLABを求めるので、別の作業ディレクトリから絶対パスで呼んでも動きます。

```sh
# 共通helper/受信fixtureがなければビルドし、configの絶対パスを生成。
# OpenTUIの実行依存もlockfileに従って導入する。
python3 scripts/lab.py prepare --cwd /absolute/path/to/repository

# 各UIを実際にビルド。allを省略しても同じ。
python3 scripts/lab.py build all
# 単体: build native / build tauri / build opentui / build common

# backendと各UIの非GUI試験。実アプリ操作は含まない。
python3 scripts/lab.py test all
# 単体: test native / test tauri / test opentui / test common

# 本物の共有helperへの接続も試す。lab shellのcounterが進む。
python3 scripts/lab.py test all --live

# 実行前にコマンドだけ確認。GUI・ファイル生成・ビルドを行わない。
python3 scripts/lab.py build all --dry-run
python3 scripts/lab.py run tauri --dry-run
```

`prepare native` / `prepare tauri` はOpenTUI依存の導入を省き、共通configを準備します。Tauriの開発用依存は`build tauri`が導入します。`prepare`は既存configのcwdとstateDirを引き継ぎ、helper/受信アプリのパスを現在のLABに更新します。cwdを変えるときやラボを移動・コピーした後は、古いシェルを再利用しないよう次を使います。

```sh
python3 scripts/lab.py prepare --fresh --cwd /absolute/path/to/repository
```

`--fresh`は新しい専用stateDirを作ります。古いstateDirやプロセスを削除しません。stateDirはUnix socketのパス長を抑えるため専用の`/private/tmp/tethr-lab-*`です。すでに起動しているNative/Tauriは一度終了してから、新しいconfigで起動してください。

`--config PATH`が最優先、次に`TETHR_LAB_CONFIG`、どちらもなければ`runtime/config.json`を使います。移動後のデフォルトconfigが別のLABのhelper/fixtureを指したままなら、`run`はそのまま操作せず再prepareを案内します。外部configを明示する場合は、その内容と対象を利用者が選びます。

## 各UIを開く

```sh
python3 scripts/lab.py run native
python3 scripts/lab.py run tauri
# 専用のGhostty窓で実行。タイトルを固定しやすいようtmuxの外で使う。
python3 scripts/lab.py run opentui
```

Native/Tauriは`open --env TETHR_LAB_CONFIG=...`を使います。Nativeには`--args --config ...`も渡します。`open -n`は付けず、実行中なら既存の窓を再openします。**再openによって実行中プロセスの環境やconfigは変わりません。** configを変えた場合は、その試作だけを終了してから起動します。`open`の終了コード0は起動要求を受け付けた結果であり、入力フォーカスの試験合格ではありません。

Tauriでは標準のCargo bundleを優先し、それがなければ配布用の`tauri/dist/Tethr Tauri Lab.app`を使います。Native/Tauriの`.app`はローカル試作用です。公開配布用の公証を済ませた製品とはしていません。

OpenTUIは現在の端末を使います。ラッパーが端末タイトルを一時的に`tethr · OpenTUI`へ設定し、終了時にタイトルスタックを復元します。Ghostty側でそのタイトルが観測できるかを確認してください。tmuxやshell integrationが別のタイトルで上書きする環境では限定ルールの一致を仮定しません。OpenTUI起動のために他の端末窓を操作したり、端末アプリ全体をfloatingにしたりはしません。

検索はtitle/subtitle/keywordsに対する、空白で分けた語のAND一致です。上下で選択、Enterで実行します。空候補と実行中の重複送信を抑えます。EscはNative/Tauriを非表示にし、OpenTUIではUIを閉じます。アプリを開く操作はUIを隠してからhelperへ送り、応答だけで勝手にUIへ戻しません。失敗は再open時にも確認できるよう保持します。

## 何を共有しているか

- **`terminal.step`**：lab専用のsocketで管理するtmux shellのnonce・counter・PID・cwdを確認・更新します。三つのUIから同じ専用shellを継続します。利用者の通常のtmux serverや任意の既存paneへの復帰を実装済みとはしていません。
- **`command.git-status`**：configのcwdで、新しいread-only gitプロセスを起動します。同じシェルの継続とは別の動作です。
- **`app.*`**：configで指定したMacアプリの起動・前面化を共通Swift helperへ依頼します。helperの成功ログと、実際のOS状態を分けて確認します。

`test common`は試験ごとの専用socketを用意し、終了時はそのsocketだけを停止します。ユーザーの通常のtmux server全体を止めるコマンドはありません。`test --live`は比較用の共有shellを更新するので、同時に別UIから`terminal.step`を操作しないでください。wrapper内では順番に実行します。

出力やエラーは各UIへ表示します。実coding agentへの出力転送・回答品質は、この最初の共通スライスでは実装・受け入れ済みとしていません。

## 検証済みの範囲と残っている確認

作成した実UIのビルドと、各UIの検索・選択・状態・エラーの試験、共有helperでの専用shell継続とgit結果を確認しています。個々の記録は [Native](native/README.md)、[Tauri](tauri/README.md)、[OpenTUI](opentui/README.md) のREADMEと対応するevidenceにあります。過去の記録が、移動後・再ビルド後の成果物を自動で保証するわけではありません。

| 証拠 | 示している範囲 | 示していない範囲 |
| --- | --- | --- |
| 各UIのロジック・描画試験 | 検索、選択、入力イベント、結果/エラーなど。OpenTUIでは本物のrenderer/native libraryも使用 | 物理IME、OSを跨ぐ入力先、全体の快適さ |
| 本物helperへの接続試験 | lab shellの状態保持と、設定cwdでのgit結果。Tauriのheadless probe単体はRust→helper境界 | この接続試験だけでのGUI全経路・フォーカス保証 |
| 親がrepoへコピー後に行ったNative/Tauriの実GUIとOpenTUIの疑似端末確認 | Native/Tauriの実際の`.app`、続いてOpenTUIのPTY入力から、共有shellのcounterが1→2→3へ進み、同じPID 56584・nonceを保った観測 | OpenTUIのGhostty GUI、宛先未指定のキー入力の配送保証、物理IME、すべての再open/Space条件 |
| `runtime/evidence/activation/result.json` | 親が実施したhelper→受信アプリの外部前面観測。no-op前面化が成功ログを出しても検出できた記録 | 各UIを入口にした同じ試験、宛先未指定のキー入力が届いた証明 |
| scoped paneruルール | 三つの限定ルールを適用済み。Tauri実窓のfloating=trueを観測 | Nativeのルール一致、OpenTUIのGhostty実窓、すべてのSpaces・入力操作の自動合格 |

**グローバルホットキー、実IMEの未確定文字・候補窓・Enter確定、宛先未指定のキー入力と受信欄の照合は未受け入れです。** windowの見た目、サイズ、操作感、paneruとの相互作用も実画面で確認します。AppKitのAPI戻り値、`open`の成功、Webテストの緑だけで合格にしません。

OpenTUIでは本物のrenderer・疑似端末の試験を行っていますが、Ghostty GUIを使う自動試験はツールの安全審査で拒否され、**NOT_RUN**です。AppleScriptなどの代替自動操作は行っていません。`run opentui`は利用者が開いた通常の端末内で実行するコマンドであり、Ghosttyを自動操作・新規起動する処理を持ちません。疑似端末の成功をGhostty GUIの合格とは報告しません。

`scripts/lab.py test`はGUIを操作する`tests/check_activation.py`を自動実行しません。画面を使う検証は親が一つずつ行い、故障を直すactivate/click/retryを試験の途中に混ぜません。観測不足や未実行はそのまま残します。

コードと操作契約は探索段階です。三つのUIを触り、同じ用事を終えるまでの操作数・訂正・所要時間と、次も使いたい方を比べるための成果物です。
