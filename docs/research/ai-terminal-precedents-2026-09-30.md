# tethr：AIターミナルと横断ランチャーの先例から、何を作るか

調査日：2026-09-30  
対象：Warp、Raycast、Atuin、sesh、Consult、Herdr、およびGhostty・tmuxの接続面  
状態：公式資料に基づく比較と設計提案。製品の実機比較、インストール、課金、tethrの追加実装は行っていない。

---

## 🔑 要約

---

> **tethrでまず検証すべきなのは、既存ツールを組み合わせた場合より、目的の窓・セッションへ戻って次の操作を選ぶ手間を減らせるか、である。**

- WarpにはAI補完だけでなく、履歴等の統合検索、セッション検索、任意ターミナルで動くAgent CLIがある。「専用ターミナルへの移行が必須」を差別化の前提にできない。
- Raycastは異種候補と項目別アクションを統合している。seshにはRaycast拡張もあり、「ランチャーからtmuxへ戻る」だけでも既存手段がある。
- Atuinは文脈付き履歴に加え、AI生成と外部AIへの履歴提供を扱う。履歴DBやAIハーネスを一から作る前に、統合候補として比較する価値がある。
- 暫定推薦は、ローカルの対象探索・安全な復帰を小さく試し、履歴とAIを別の供給元として接続できる設計。UI方式の採用決定とは分ける。

出典：[Warp CLI](https://docs.warp.dev/agents/cli/)、[Warp Command Entry](https://docs.warp.dev/terminal/entry)、[Raycast Search Bar](https://manual.raycast.com/search-bar)、[sesh](https://github.com/joshmedeski/sesh)、[Atuin](https://docs.atuin.sh/18.19/)

**確実性**：機能の存在は下記の公式資料で確認した。利用者の環境での使い勝手、組合せ互換性、費用削減、tethrの優位性は未検証。「未確認」は「機能が存在しない」を意味しない。

---

## 🎯 目的：機能数より、作業に戻るまでの摩擦を減らす

---

tethrの現在の目的は、必要な範囲でRaycastを代替し、手で窓を選ぶ操作を、ウィンドウ・tmux・Herdr等のセッションを横断する検索へ広げること。コマンド履歴、候補提示、AI補完、日本語の用事からの探索も重視する。全機能の複製や、独自端末・独自エージェントの開発自体は目的ではない。[現在の設計方針](../design.md)

この目的に対する評価軸は次の通り。

| **軸** | **確認したいこと** |
| :--- | :--- |
| 到達 | アプリが開くだけでなく、目的の窓・pane・会話へ戻れるか |
| 継続 | 同じ作業を続けられるか。新規シェルや複製セッションを誤って作らないか |
| 想起 | コマンドを思い出さずに見つけられ、履歴とAI生成を区別できるか |
| 制御 | 検索・選択・入力欄への配置・実行の意味が分かるか |
| 費用 | 非AI操作に推論を使わず、AI費用の発生点を把握できるか |
| 維持 | 今の端末・tmux・設定・習慣をどれだけ維持できるか |
| 検証 | 誤った対象、古い候補、日本語IMEの誤実行を発見できるか |

上記は評価の提案である。操作速度や費用の優劣を、資料だけで採点していない。

---

## 🧭 各ツールが握っている操作と情報

---

### Warp：端末全体と、持ち運べるエージェント

WarpのCommand Searchは、履歴、Workflows、Notebooks、AI Command Searchをまとめて探す入口を持つ。Session NavigationはWarp内のセッションを、プロンプトや実行中・直前のコマンド、状態から探せる。[Command Entry](https://docs.warp.dev/terminal/entry)、[Session Navigation](https://docs.warp.dev/terminal/sessions/session-navigation)

Warp Agent CLIは任意のターミナルで動き、独自PTYでコマンドや対話プロセスを扱う。Warpアプリのインストールは必須ではない。CLIは会話を再開する入口も持つ。一方、CLIがWarp Driveの全種類のオブジェクトを扱えるという説明ではなく、概要は保存済みprompts以外の種類を利用不可としている。[CLI概要](https://docs.warp.dev/agents/cli/)、[Quickstart](https://docs.warp.dev/agents/cli/quickstart/)

**示唆**：Ghosttyを維持したいという理由だけでWarpを比較対象から外せない。ただし、CLIが自分のPTYを扱えることから、既存の任意tmux paneや外部Macウィンドウを列挙・復帰できると飛躍しない。tethrが必要とする「外の既存作業への戻り」を別途比較する。

### Raycast：対象の検索と、その対象へのアクション

Root Searchにはアプリ、コマンド、ファイル等が現れ、項目別のAction Panelを開ける。検索順位には一致の度合いや利用履歴が使われる。異種候補を一つの検索欄に置く構造は、すでに製品として成立している。[Search Bar](https://manual.raycast.com/search-bar)、[Quickstart](https://manual.raycast.com/quickstart)

**示唆**：見た目の「一つの入力欄」を作り直すだけでは効果が薄い。tethrが扱う候補の識別情報と、候補ごとに実行できる操作の正確さを設計の中心に置く。Raycast拡張で必要な範囲を満たす案も比較から外さない。

### Atuin：実行履歴に文脈を付ける

Atuinはコマンドにcwd、所要時間、終了結果、host、sessionなどを付けてローカルDBに保持する。同期は任意であり、履歴検索だけならローカル運用も選べる。AIによるコマンド生成には、実行する操作と入力行へ挿入する操作が用意されている。[Atuin概要](https://docs.atuin.sh/18.19/)、[Atuin AI](https://docs.atuin.sh/18.19/ai/introduction/)

MCP経由では外部AIが履歴や記録済み出力を検索できる。履歴のsession絞り込みは、Atuin対応シェルからMCPサーバーを起動した場合に限られ、出力取得にはdaemonとpty-proxyの準備が必要になる。[MCP Server](https://docs.atuin.sh/18.19/ai/mcp/)

**示唆**：履歴の再実装より、既存履歴を検索供給元にする案を先に検討する。デスクトップから起動するtethrでは、MCPの起動cwdと利用者が選んだ対象cwdが一致するとは限らない。対象を選んでも検索範囲が自動で切り替わる、と仮定しない。

### sesh：tmuxの既存作業と、まだ開いていない場所をつなぐ

seshはtmuxのセッションとzoxideのディレクトリを一覧化し、接続先がなければセッションを作れる。fzf等との組合せに加え、作者のRaycast拡張もある。作者READMEには拡張でtmuxの事前起動が必要なこと、短時間のキャッシュがあることが記載されている。[sesh README](https://github.com/joshmedeski/sesh)、[Raycast Store](https://www.raycast.com/joshmedeski/sesh)

**示唆**：run-or-raiseに近いセッション接続と、端末外からの起動には先例がある。比較相手を「何も導入していない手作業」だけにすると、自作の価値を過大評価する。キャッシュされた候補が消えるケースも評価に含める。

### Herdr：tmuxと並べて扱う、実際の接続対象

2026-09-30追補：利用者の公式URL提示により、初版の仮転写「HaaD」は[Herdr](https://herdr.dev/)と特定した。tmuxと同じ第一級の横断検索・復帰対象として扱う。これは利用者が確認した方向性であり、以下の接続方式の採用決定とは分ける。

Herdrは既存のGhosttyやiTerm内で使える独立したruntimeであり、tmuxそのものではない。sessionはserverの名前空間で、その中にworkspace、tab、paneを持つ。[公式比較](https://herdr.dev/compare/)、[Concepts](https://herdr.dev/docs/concepts/)

**示唆**：Herdrを単なるAI補完先として扱わず、既存の作業を発見して戻る供給元にする。Herdr内部のworkspaceをtethr独自の必須プロジェクト登録単位へ変換する必要はない。

### Consult：Emacsらしい統一感を、構造として参考にする

Consultは複数の静的・非同期候補源を混ぜ、候補源ごとの種類、絞り込み、注釈、操作を持たせる。これはEmacsの体験を構造として理解する例であり、利用者が特定の拡張を使っているとの推定ではない。[Consult README](https://github.com/minad/consult#multiple-sources)

**示唆**：検索方法を揃えつつ、対象の意味と操作を保持する。ウィンドウとコマンドに同じEnter動作を無条件で割り当てる必要はない。

---

## 🔍 手が止まる直接要因：検索結果から実際の操作までの段差

---

製品資料から確認できるのは機能の入口である。tethrでは、その入口を押した後の結果を分解して評価する必要がある。

| **場面** | **先例から分かること** | **tethrで確かめること** |
| :--- | :--- | :--- |
| 履歴からコマンドを探す | Atuinに文脈付き検索がある | 選んだ作業場所の履歴が出るか |
| セッションへ戻る | Warp内検索、seshのtmux接続がある | 目的の窓とpaneを同時に特定できるか |
| 日本語で用事を伝える | Warp/Atuinに自然言語入力がある | 使用モデルでの日本語品質、IMEと確定操作 |
| 定型作業を再利用する | WarpにWorkflowsとpromptsがある | 固定コマンドとAI依頼を候補で見分けられるか |
| 復元する | Warpに窓・タブ・pane・Blocksの復元がある | 画面復元と、生きたシェル／会話の継続を区別できるか |

Workflowsは引数付きコマンド、promptsは引数付き自然言語依頼として保存される。tethrでも両者を混同せず、「再利用できる候補」の出所と実行方法を分ける設計が考えられる。[Workflows](https://docs.warp.dev/knowledge-and-collaboration/warp-drive/workflows)、[Prompts](https://docs.warp.dev/knowledge-and-collaboration/warp-drive/prompts)

WarpのSession Restorationが扱う窓・タブ・pane・最近のBlocksの復元と、CLIの会話再開は別の機能である。これらの記述だけで、再起動前のOSプロセスや任意の対話シェル状態が保たれるとは判断しない。[Session Restoration](https://docs.warp.dev/terminal/sessions/session-restoration)、[CLI Quickstart](https://docs.warp.dev/agents/cli/quickstart/)

---

## 💰 背景条件：料金と、既存環境を維持する価値

---

### 費用を三つに分ける

費用比較では、アプリの利用料、AI推論料金、設定・保守に使う時間を分ける。BYOKはモデル料金の支払先を変える選択肢であり、総費用ゼロの意味ではない。

| **経路** | **公式資料で確認できた料金上の条件** | **判断への影響** |
| :--- | :--- | :--- |
| Raycast AI | FreeにはAIを含まず、現行v2のBYOK・ローカルモデル等にも有料プランが必要 | 既存AI契約を持ち込んでもアプリ側料金は残る |
| Warp個人利用 | FreeでもBYOKや追加クレジットの経路があり、通常のshell操作はクレジット対象外 | 定額プランへの全面移行以外も比較できる |
| Atuin AI | 18.19の紹介ページは現在無料と記載。自前backendも選べる | 恒久無料や無制限と解釈せず、導入時の条件を確認する |
| tethr自作 | 料金設計も推論先も未決定 | 開発・保守時間とモデル費用を含めて比較する |

出典：[Raycast Billing](https://manual.raycast.com/billing)、[Raycast Usage Limits](https://manual.raycast.com/ai/usage-limits)、[Warp Credits](https://docs.warp.dev/support-and-community/plans-and-billing/credits)、[Atuin AI](https://docs.atuin.sh/18.19/ai/introduction/)

Warpの個人向けBYOK等には利用主体に関する条件があり、Business/Enterpriseでは別のplatform課金条件もある。CLIのAutoモデルはBYOK設定済みでもWarpクレジットを使い、フォールバック設定でも課金経路が変わる。単にキーを設定しただけで、希望する支払経路になるとは扱わない。[Pricing FAQ](https://docs.warp.dev/support-and-community/plans-and-billing/pricing-faqs)、[CLI Models and Usage](https://docs.warp.dev/agents/cli/models-and-usage/)

**提案**：tethrの切り替え・履歴検索をAIなしで完結させる。AI要求の直前に対象・送信内容・利用先を把握できるようにし、失敗時に別の有料経路へ黙って切り替えない。費用低減は実測後に評価する。

### ローカルにある情報と、AIへ渡る情報を分ける

Atuinの履歴検索MCPは読み取り専用だが、受け取った履歴を外部AIへ送るかどうかは、接続するクライアント側の設計にも依存する。「ローカルDBだから外へ出ない」という保証に広げない。自前AI backendにはOpenAI互換の接続先やローカルモデルを使う経路があるが、導入・運用は別途必要になる。[Atuin MCP](https://docs.atuin.sh/18.19/ai/mcp/)、[Self Hosting](https://docs.atuin.sh/18.19/ai/self-hosting/)

**提案**：最初は選択したコマンドと必要な範囲の文脈だけをAIへ渡す。全履歴・全pane出力・全ウィンドウタイトルを収集して常時送る方式を既定にしない。履歴中の秘密値や他の作業情報も確認対象とする。

---

## 🧩 構造的な難所：対象の所有者が複数いる

---

ターミナルアプリは窓を、tmuxはsession/window/paneを、AIツールは会話を、履歴ツールは過去の実行を管理する。検索結果をまとめても、それぞれの識別・生存期間・復帰方法は統一されない。

GhosttyはAppleScriptでwindows/tabs/terminalsを列挙し、terminalのcwdやIDを取得してfocusする入口を公開している。macOSのAutomation権限が関わるため、APIの存在を実機での許可・操作成功と同一視しない。[Ghostty AppleScript](https://ghostty.org/docs/features/applescript)

tmuxには対象IDとclientを指定した切り替えがある。IDはそのtmux server内の対象の寿命中に安定する。一方、tmuxの切り替えだけではMac上の該当ウィンドウが前面になるとは限らない。[tmux manual](https://man.openbsd.org/tmux.1)

### 暫定案：薄い接続部で「探す」と「実行する」を分ける

以下は設計提案であり、実装済みAPI契約ではない。

| **責務** | **持つ情報・操作** | **失敗時の扱い** |
| :--- | :--- | :--- |
| 候補の発見 | 接続元、対象種別、対象ID、表示名、取得時刻 | 取得不能と候補ゼロを区別 |
| 候補の説明 | cwd、稼働状態、履歴／登録／AIの出所 | 不明は不明と表示 |
| 復帰 | 操作直前の存在確認、対象固有のactivate/attach/resume | 消えた対象へ別対象を推測して送らない |
| 入力・実行 | 正確な宛先、cwd、コマンド、配置か実行か | 確認後の対象変更なら再確認 |
| 結果観測 | 実際の前面状態、選択pane、入力先、処理結果 | 要求成功と実結果を分ける |

tmuxではsocket/serverとpane IDを組にするなど、名前だけに依存しない識別を検討する。Ghostty terminalとtmux clientをどう対応付けるかは未検証。Herdrも同じ第一級の対象だが、providerごとのID・状態・対応機能は保持し、tmuxと同じ接続方法を当てはめない。

AIが提案したコマンドの妥当性と、それが正しい宛先に届くことは別の問題である。良い補完モデルでも後者を解決しない。

### Herdr連携の段階案

**公式に確認できた接続面**：session一覧・attach、workspace/tab/pane/agent一覧、agent focus/attach、terminal attachがある。実binaryの契約は `herdr api schema --json` で照合できる。remote指定では転送できる操作に制限があり、対話的attachがそのまま転送されると仮定しない。[CLI Reference](https://herdr.dev/docs/cli-reference/)

**提案**：最初はCLI adapterで候補取得と復帰を分けて試す。識別子はprovider・machine・session/serverの名前空間と組にし、同名や再起動後の対象を取り違えない。キャッシュした宛先を操作直前に確認し、未対応操作は無効にする。既存のcontrollerを奪うtakeoverは通常の復帰と区別する。

継続更新が必要ならsocket APIを比較する。`herdr api snapshot`／`session.snapshot` は初期取得に使え、`events.subscribe` は継続通知を提供する。再接続や `events_lost` では再購読・snapshot取得・正規の再読込で整合させる。snapshotとeventsに共通の順序境界はなく、古いeventをsnapshotへ無条件に再適用しない。[Socket API](https://herdr.dev/docs/socket-api/)

Herdrのagent状態はworking、blocked、idle、done、unknownを保つ。unknownを完了へ丸めない。focusは「見た」状態にも影響し得るため、検索のプレビューだけでfocusを実行しない案とする。[Agent Automation](https://herdr.dev/docs/agent-automation/)

**継続と復元の区別**：detach後の再attachは稼働中プロセスへの復帰。通常のserver再起動では元のプロセスは失われ、layout復元と、対応agentのnative session再開は別経路になる。pane画面履歴は任意のshell履歴DBではなく、AI補完用のコマンド履歴と同一視しない。[Session State and Restore](https://herdr.dev/docs/session-state/)

**未検証**：Herdr内focusとmacOSのホスト窓前面化をつなぐ方法、利用端末との対応付け、実binaryのバージョン・権限・競合時の挙動。OS run-or-raise、deeplink、MCPについて公式の有無は今回確定していない。CLI/socketの存在から、それらが使えると推測しない。Native / Tauri / OpenTUIの選定にも直結させない。

---

## 🕰️ 長期的な流れ：再利用とエージェントが、複数の入口へ広がる

---

現在の公式資料からは、次の三つの方向を読み取れる。市場全体の成長率や将来の勝者を示す統計ではなく、観測した機能構成からの解釈である。

- 履歴の文字列検索に、実行場所・結果・保存済み手順が加わる。AtuinとWarpが異なる形でこの方向を持つ。
- 自然言語の支援が、専用アプリだけでなくCLIや既存ツールへの接続へ広がる。Warp CLIとAtuin MCPが例になる。
- ランチャーから対象を探す体験と、対象に対する操作の選択が接近する。RaycastとConsultが参考になる。

この流れを踏まえると、tethrがすべてを抱え込むと既存機能の追随負担が増える、と推測できる。個人用ツールの利点は、機能数ではなく、本人が頻繁に行う数個の往復に絞れることにある。

将来のモデルやツールの変更に備えても、最初から巨大な汎用プラグイン基盤を作る必要はない。まず実際に必要な少数の接続を実装し、共通化の必要が現れた境界を抽出する案が妥当である。

---

## ⚙️ システムとして採用・統合・自作を比較する

---

以下は今回の資料を踏まえた選択肢の評価であり、正式採用ではない。

| **案** | **期待する利点** | **残る負担・検証** | **選ぶ条件** |
| :--- | :--- | :--- | :--- |
| Warpアプリを使う | 端末内の検索・AI・保存手順を一体で試せる | 既存環境からの移行、外部窓の扱い | 端末内だけで主要な用事が済む |
| Ghostty等でWarp CLIを使う | 端末アプリを維持してAIを試せる | 独自PTYと既存tmux作業の関係、会話の選択導線 | 主な不足がAI支援である |
| Raycast＋sesh等を組み合わせる | デスクトップ入口とtmux接続の先例を利用できる | 対応端末、キャッシュ、複数窓の正確な復帰 | 設定や小さな拡張で必要な往復が満たせる |
| Herdrを第一級の接続先にする | 現在のagent作業をtmuxと同じ入口から探せる | 名前空間、attach能力、Mac窓との対応、状態更新 | tmuxと並ぶ対象として確定。接続方式は実機検証で選ぶ |
| Atuinを履歴・AIの供給元にする | 履歴の文脈と検索を再利用できる | 対象cwd/sessionの伝達、出力取得の準備、API境界 | コマンド想起が主要な障害 |
| tethrを薄い統合UIとして作る | 窓・session・履歴の接続を本人の操作に合わせられる | OS権限、対象の同一性、失敗処理、保守 | 既存の組合せより往復が明確に短くなる |
| 端末・履歴・AIまで全面自作 | 全層を変更できる | 最大の実装・保守範囲 | 現時点では必要性の証拠が不足 |

### 暫定推薦

1. 「戻る」最小経路を、AIなしで設計する。一般アプリ、Ghosttyの窓、tmux、Herdrを候補にし、provider別の対象と復帰方法を区別する。
2. コマンド検索では、Atuin等の既存履歴と小さな登録済み候補を比較する。
3. AI補完は明示的な別操作として試す。日本語の用事、候補の修正、宛先確認までを同じ試験に入れる。
4. Warp CLIやRaycast＋seshを実際の比較相手にし、自作する範囲を減らせるか確認する。
5. Native / Tauri / OpenTUIは、この往復を同条件で行った後に判断する。

「外部文脈を横断すること」は検証仮説であり、他製品に不可能な独自機能と主張するものではない。Herdrを含む本人の作業環境で、短く確実に使えることを評価する。

---

## 🧪 結論と展望：自作の価値を反証できる試験にする

---

### 次の試験案

以下の評価手順・合格案は提案であり、未実行。

同じ対象群で、現在の手動操作、既存ツールの組合せ、tethr試作を比べる。初回設定と普段の操作を分け、利用順を入れ替えて慣れの影響を減らす。

| **課題** | **記録するもの** | **見直しの条件** |
| :--- | :--- | :--- |
| 同名候補から目的の窓／paneへ戻る | 到達時間、操作数、誤選択、実際のID | 既存手段と同等以下なら統合UIの範囲を縮める |
| 起動済み／未起動を続けて呼ぶ | 窓・プロセスの増分、前面状態 | 不要な複製が出れば復帰仕様を修正 |
| tmux／Herdrの同名対象を切り替える | provider・machine・session・paneの対応、実際の入力先 | 違うruntimeへの誤配送は不合格 |
| 選択後に対象が消える | 送信件数、エラー表示、別対象への誤配送 | 誤配送は不合格 |
| 日本語IMEで候補を探す | 変換確定と実行のイベント | 変換Enterで実行されたら不合格 |
| 履歴から選び直して使う | 対象cwd、候補の出所、編集回数 | 文脈がずれるなら検索範囲の契約を修正 |
| AI補完で同じ用事を済ませる | 正確なコマンド、修正、待ち時間、実費 | 費用・修正負担が利点を上回れば後段へ |

速度の数値目標は、現状の基準を測ってから決める。成功ログだけでなく、受け手とOSの観測を使う既存の[試験方針](testing-strategy-2026-09-12.md)は引き続き参考になる。

### 未解決の判断

- Herdrの実環境での識別・attach・focusと、Macの該当窓への復帰
- 本人にとって頻度の高い最初の一往復
- Atuin等を導入済みか、既存履歴をどう扱うか
- ウィンドウ・tmux client・エージェント会話の対応付け
- AIの利用先、送信範囲、費用上限、失敗時の扱い
- 三つのUI試作の実IME、ホットキー、フォーカスの受入結果

短期は一往復の比較、中期は必要な接続先だけの拡張を提案する。長期の製品化やモデル選定は、現在の情報では予測しない。使う頻度と維持費が釣り合わなければ、既存ツールの設定・拡張に寄せることも合理的な結論になる。

---

## 📚 参考情報源と確認範囲

---

すべて2026-09-30に参照。Warpはページ表示の更新日が2026-09-16または09-24の資料を含む。Atuinは比較を揃えるため18.19版を中心に参照し、利用者の導入版での動作は未確認。Raycastのプラン条件は参照時点のv2資料。GitHubのREADMEと可変URLは今後変わり得る。

- Warp：[Agent CLI](https://docs.warp.dev/agents/cli/)、[Quickstart](https://docs.warp.dev/agents/cli/quickstart/)、[Models and Usage](https://docs.warp.dev/agents/cli/models-and-usage/)
- Warp：[Command Entry](https://docs.warp.dev/terminal/entry)、[Session Navigation](https://docs.warp.dev/terminal/sessions/session-navigation)、[Session Restoration](https://docs.warp.dev/terminal/sessions/session-restoration)
- Warp：[Workflows](https://docs.warp.dev/knowledge-and-collaboration/warp-drive/workflows)、[Prompts](https://docs.warp.dev/knowledge-and-collaboration/warp-drive/prompts)、[Credits](https://docs.warp.dev/support-and-community/plans-and-billing/credits)、[Pricing FAQ](https://docs.warp.dev/support-and-community/plans-and-billing/pricing-faqs)
- Raycast：[Quickstart](https://manual.raycast.com/quickstart)、[Search Bar](https://manual.raycast.com/search-bar)、[Billing](https://manual.raycast.com/billing)、[Usage Limits](https://manual.raycast.com/ai/usage-limits)
- Atuin：[概要](https://docs.atuin.sh/18.19/)、[AI](https://docs.atuin.sh/18.19/ai/introduction/)、[MCP](https://docs.atuin.sh/18.19/ai/mcp/)、[Self Hosting](https://docs.atuin.sh/18.19/ai/self-hosting/)
- Herdr：[Concepts](https://herdr.dev/docs/concepts/)、[CLI](https://herdr.dev/docs/cli-reference/)、[Socket API](https://herdr.dev/docs/socket-api/)、[Agent Automation](https://herdr.dev/docs/agent-automation/)、[Session State](https://herdr.dev/docs/session-state/)、[公式比較](https://herdr.dev/compare/)
- セッションと検索：[sesh](https://github.com/joshmedeski/sesh)、[sesh Raycast拡張](https://www.raycast.com/joshmedeski/sesh)、[Consult](https://github.com/minad/consult#multiple-sources)
- 接続面：[Ghostty AppleScript](https://ghostty.org/docs/features/applescript)、[tmux manual](https://man.openbsd.org/tmux.1)
- tethr：[設計ノート](../design-notes/unified-search-2026-09-30.md)、[比較試作の検証記録](prototypes-2026-09-12.md)

この調査は、公式に記述された機能の比較とtethrへの設計上の解釈である。未掲載の機能の不存在、全拡張の網羅、第三者による性能評価、日本語の生成品質、実際の月額費用は検証していない。
