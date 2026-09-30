# tethr 技術選定の再調査

> 履歴文書：端末中心の前提に基づく2026-09-12時点の調査・推薦です。現在の方向性は[設計方針](../design.md)、新しい先例比較は[2026-09-30調査](ai-terminal-precedents-2026-09-30.md)を参照してください。以下の未検証事項や推薦を、現在の実装状態・採用決定として扱わないでください。

2026-09-12。ターミナル優先と、一般のMacアプリのrun-or-raise追加を前提に再評価した。公式資料、独立したAstraによるMacネイティブ案の調査、OpenTUI案とTauri案の並行調査、手元のMacでの限定的な確認を用いた。**これは試作候補の推薦であり、正式採用や製品実装の完了ではない。**

## 推薦

**最初に試す構成は、Bun + strict TypeScript + OpenTUIを操作UIに、Ghostty / tmuxを既存の端末基盤に、小さなSwift / AppKit部品をMacアプリ操作に使う案。** Reactは暫定候補にとどめる。

端末で対象や操作を選び、既存の作業へ戻るという現在の優先順位には、この案が合うと判断する。OpenTUIには入力と描画結果をテストから観測する経路があり、失敗をLLMに返す要件にも対応しやすい。ただし、起動速度や開発速度で他案より優れているという実測はない。

**「ターミナルの機能を重視する」だけでは、画面をTUIにする結論は出ない。** 決め手は、他のアプリから呼び出し、用事を済ませ、意図した入力先へ戻る一連の操作を、Ghosttyを使って快適に実現できるかである。問題があれば、呼び出しを担うSwift部品の責任を広げる案、専用のネイティブパネル、Tauriの画面を、原因に応じて比較する。全面Swiftへの移行だけでOSのactivation制約が解消するとは限らない。

## 三つの候補

以下の適合性は、調査した機能と現在の要件を合わせた判断である。性能順位ではない。

| 候補 | 現在の用途に合うところ | 残る負担 | 選ぶ条件 |
| --- | --- | --- | --- |
| Bun + TypeScript + OpenTUI、Mac操作にSwift | 既存端末を利用できる。入力・画面・状態を細かく検証しやすい | 窓の操作はGhosttyに依存。Swiftとの境界、IME、フォーカス復帰を確認する必要がある | 端末内の対象選択・コマンド・出力受け渡しが主役で、Ghostty経由の呼び出しが快適 |
| Swift / AppKitを中心に、必要ならSwiftUI | 専用の呼び出しパネルとアプリ操作を、MacのAPIでまとめて扱える | 端末との接続は別途必要。UI試験と結果取得を最初から整える必要がある | どのアプリからでも同じ操作感で呼び出し、戻れることを最優先する |
| Tauri 2 + Web UI + Rust | Webのレイアウトやプレビューを使える。現在はMac向けの画面自動テスト経路もある | 一般アプリの操作にはMac側の接続が必要。Web・Rust・OS連携の境界が増える | Webの入力・検証経路が適する、または広い結果表示やプレビューが早期に必要 |

run-or-raiseを加えたことは、Mac固有の処理を持つ理由になる。ただし、それだけでUI全体をSwiftに決める理由にはならない。

## 以前の前提から変わったこと

### Tauriは「Macでは画面を自動テストできない」ではない

現在の公式資料では、WebdriverIOのTauriサービスとアプリ内のWebDriverサーバーを使い、macOSを含めて操作できる。従来の外部`tauri-driver`を直接使う場合の制限と区別する必要がある。ブラウザだけでフロントエンドを試し、バックエンド呼び出しを模擬する経路もある。ただし、これだけで他アプリの前面化や日本語IMEまで検証できるとは言えない。[TauriのWebDriver資料](https://v2.tauri.app/develop/tests/webdriver/)

TauriのグローバルショートカットはmacOS対応で、自分のウィンドウの表示・非表示・フォーカスも操作できる。一般のMacアプリのrun-or-raiseは、それらとは別にOS側の処理を組み合わせる。[Global Shortcut](https://v2.tauri.app/plugin/global-shortcut/)、[Tauri Window API](https://docs.rs/tauri/latest/tauri/window/struct.Window.html)

macOSではWKWebViewを使う構成であり、Webエンジンを同梱しないことから、起動時間やメモリ使用量の順位までは推定しない。[Tauriのプロセス構成](https://v2.tauri.app/concept/process-model/)

### OpenTUIはBun専用という前提も更新が必要

公式資料にはNode.jsで動かす経路もある。一方、現在のBun側のCoreテスト対象にはmacOS arm64が含まれ、Node側のネイティブ・配布成果物の受入試験はLinux x64に限られる。この対応範囲から、今回のMac向け試作ではBunを推す。ネイティブ依存を省いたインストールでは、import後の最初のネイティブ操作で失敗する場合がある。[OpenTUIのランタイム対応](https://opentui.com/docs/getting-started/runtime-support/)

調査時点の固定候補はOpenTUI 0.5.11。バージョンを固定し、必要な動作の確認を通して更新する。ReactとSolidには双方ともテスト用の描画入口があり、ユーザーの経験や速度差を仮定してReactを確定しない。[リリース](https://github.com/anomalyco/opentui/releases/tag/v0.5.11)、[React](https://opentui.com/docs/bindings/react/)、[Solid](https://opentui.com/docs/bindings/solid/)

### Ghosttyを外から操作する正式な入口がある

GhosttyはAppleScriptでウィンドウ・タブ・端末を扱い、端末へのフォーカス、入力、作成、作業ディレクトリの参照などができる。手元に入っているGhosttyの辞書にも対応する定義を確認した。実際のApple Events送信とAutomation権限の動作確認は今回行っていない。[Ghostty AppleScript](https://ghostty.org/docs/features/applescript)

quick terminalは呼び出しを隠しても状態を保つ一方、一つのみで、macOSではタブを持てず、Ghostty再起動後の状態復元もない。この制約が、tethr用の操作面と普段のquick terminalを共存させるときの論点になる。[quick terminalの仕様](https://ghostty.org/docs/config/keybind/reference#toggle_quick_terminal)

## Mac操作の設計に効く点

Appleの現在のactivationは、OSへ前面化を求める仕組みであり、呼び出しだけで結果を保証しない。アクティブなアプリが相手に操作を譲る仕組みもあるが、Ghostty内から起動したCLI補助プロセスが、Ghostty自身の代わりに譲れると仮定してはいけない。**Swift部品からの要求と、実際に前面へ来たアプリを別々に記録して確認する。** 小さな補助プロセスだけで必要な動作を満たすかは、まだ未検証である。[Appleのcooperative activation](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation)

専用パネルにする場合も、見えていることと文字入力を受け取れることは異なる。非アクティブ型パネルや入力欄の振る舞いを具体的に設定する必要があり、「Swiftだから日本語入力も完成する」とは扱わない。[NSPanel](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)、[NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)

Swiftのロジック試験、XCTestによるUI試験、結果・ログ・添付物の抽出経路があるため、ネイティブ案もLLMから検証できる候補として残る。OpenTUIだけが観測可能な選択肢という比較にはしない。[Swift Testing](https://developer.apple.com/xcode/swift-testing/)、[Xcodeのテスト](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)、[テスト結果取得機能](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes)

## 第一候補での役割分担案

| 部分 | 担当すること |
| --- | --- |
| TypeScriptのロジック | 対象の選択、検索、操作の決定、結果と失敗の表現 |
| OpenTUI | 入力、候補一覧、結果の表示、次の操作の選択 |
| Ghostty | 端末の表示面。必要に応じて既存端末への移動 |
| tmux | tmuxで管理する作業の保持、paneの識別、必要な出力取得 |
| Swift / AppKit | 一般アプリの探索、起動・前面化の要求と結果観測 |
| エージェント接続部 | 選んだエージェントへ依頼や出力を渡す。具体的な接続方式は保留 |

tmuxのCLIとcontrol modeには、操作結果や通知を受け取る入口がある。初期試作では必要なCLI操作だけに絞り、継続的な通知が必要になってからcontrol modeを検討する。tmuxのpopupは対象クライアントに属するため、デスクトップ全体から呼び出す窓そのものにはならない。[tmuxマニュアル](https://man.openbsd.org/tmux.1)

既存シェルへの入力、新しいプロセスの起動、エージェントへの依頼は別の操作として持つ。同じディレクトリで新規実行できても、既存シェルの続きが扱えたとは判定しない。画面を隠す操作と作業プロセスの終了も分ける。これらはライブラリ選択では解決しない、tethr側の設計事項である。

## 手元で確認した範囲

環境はmacOS 26.6.2 / arm64、Ghostty 1.3.1、tmux 3.6b、Bun 1.4.0、Apple Swift 6.3。普段のアプリの起動・前面化、既存tmuxセッションの操作は行っていない。

| 確認 | 結果 | この結果では言えないこと |
| --- | --- | --- |
| AppKitの起動・activation関連APIを参照するSwiftコードのコンパイル | 成功 | 実際に起動・前面化すること |
| アプリ登録と実行中アプリの読み取り | 通常ホスト側ではGhosttyを解決でき、該当プロセスを取得できた。Codexの制限された実行環境内では取得できなかった | アプリ一覧・復帰動作が製品として完成したこと |
| インストール済みGhosttyのAppleScript辞書 | 対応する操作とプロパティの定義を確認 | 権限を含む実際の操作成功 |
| 独立したtmuxサーバーで、日本語と空白を含む作業ディレクトリを使用 | 成功 | 既存の対話シェル状態の引き継ぎ |
| 同サーバーで固定コマンドの出力取得 | 成功 | 任意コマンドの終了検出や対話操作 |
| 消えたpaneへの操作 | エラーを取得できた | 消滅・再生成など全競合の処理 |

tmux試験の直後の終了確認は判定できなかったが、後続のプロセス確認では試験用サーバーが残っていないことを確認した。最初の記録はそのまま保存した。

OpenTUIのインストール・実描画、SwiftまたはTauriアプリの実UI、ホットキー、日本語IME、前面化、Space移動、起動時間、メモリ使用量は未測定。DeepSeek Harnessの具体的なAPI互換性も今回の調査では検証していない。

## 正式採用の前に試す一往復

最初は、エディタなどから呼び出し、短い日本語で対象や操作を探し、既存のtmux作業へ移動し、別のアプリをrun-or-raiseしてから作業へ戻る一往復を試す。未起動アプリの場合も別途確認する。最小化、別Space、ウィンドウなしの場合は、基本経路を確認した後に試す。

見るのは、呼び出しの待ち時間、日本語変換の確定、実際の入力先、戻った作業の同一性、連続呼び出し時の余分な窓やプロセス、失敗時に取得できる証拠である。性能数値は測ってから比較する。

OpenTUIの試験では、キー入力・貼り付け・リサイズに対する文字フレームや装飾情報を取得できる。ただし、これはOSのIMEや他アプリへのフォーカス移動を再現するものではない。ロジック、描画、Macでの実操作をそれぞれ確認する。[OpenTUI Testing](https://opentui.com/docs/core-concepts/testing/)

この一往復が快適なら、第一候補の採用を判断してコマンド検索と出力の受け渡しを広げる。不十分なら、次のように問題のある部分から比較する。

| 試作で分かった問題 | 次に比較するもの |
| --- | --- |
| 呼び出しやプロセス寿命の管理 | Swift側に呼び出し・常駐の責任を広げる中間案。TUIまで変更する必要があるかは別に判断 |
| 日本語入力、画面の制約、入力先の把握 | Swift / AppKitパネルとTauriの入力体験。ネイティブ化だけで解決すると仮定しない |
| LLMが失敗を再現・観測しにくい | テスト出力を改善する案と、Swift / Tauriそれぞれの検証経路 |
| 広いプレビューや視覚的比較が必要 | TauriのWeb UI |

独立したAstraの最終確認でも、接続部の確認を「快適さ・開発速度・観測性で勝った」という証拠に広げないこと、Swiftへ段階的に責任を移す余地、プレビュー以外の理由でTauriを再評価する余地が指摘された。このため、推薦は最初に検証する構成という強さに留める。

ここまでの調査では、常駐デーモン、新しい端末エミュレーター、独自のエージェントループを最初から前提にする理由は得られていない。必要になった常駐機能は、実際に解決する問題を確認して加える。
