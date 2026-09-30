# tethr OpenTUI prototype

共通仕様 `../CONTRACT.md` に従う、Bun + TypeScript + **実際のOpenTUI Core 0.5.11** による試作です。Input / Select / ScrollBoxを直接使います。React/Solidは追加していません。

## 起動

このディレクトリで依存を導入し、親側が用意する共通configを指定します。

```sh
bun install
TETHR_LAB_CONFIG=/absolute/path/to/config.json bun run start
```

生成済みbundleを使う場合:

```sh
bun run build
TETHR_LAB_CONFIG=/absolute/path/to/config.json bun dist/main.js
```

bundleはJavaScriptです。実行にはBunと同じディレクトリの`node_modules`（platform用native libraryを含む）が必要です。単体実行バイナリとはしていません。

端末タイトルは実際のOpenTUI APIで`tethr · OpenTUI`に固定します。専用Ghosttyウィンドウとpaneru例外の起動条件は[GHOSTTY.md](GHOSTTY.md)を参照してください。

検索文字を入力し、上下で選択、Enterで実行、PgUp/PgDnで結果をスクロールします。Esc/Ctrl+CでUIを閉じます。helperは`helperPath`をargv配列で直接起動し、shell文字列へ展開しません。catalog/dispatchとも本物の共通helperが必須で、製品起動時のfake fallbackはありません。

app操作は**UIを破棄してから**helperを呼びます。非表示後もhelperの応答待ちと保存を続け、UIを勝手に再表示・再focusしません。結果は`.runtime/`へconfigパス単位で保存し、次回起動時に表示します。helperのtimeoutは結果不明として扱い、自動再送しません。Escで閉じる場合も実行中のhelperの結果回収は続けます。共有tmux shellの作成・停止は共通helper側の責任です。

## 検証

```sh
bun run typecheck
bun test --timeout 15000
bun run build
```

実helperへの受入試験（private lab shellを2回更新し、read-only git processを実行。アプリ起動なし）:

```sh
TETHR_LAB_CONFIG=/absolute/path/to/config.json bun tests/real-helper.ts
```

この試験はOpenTUIの実Enter入力から共通helperへ接続し、shell nonce/PID/cwdの一致、counterの連続増分、git結果を検証します。counter比較中は他のUIからlab操作を実行しないでください。証拠は`.runtime/evidence/real-helper.json`、renderer単体試験のframe系列は`.runtime/evidence/renderer.json`です。

- `model.test.ts`: token AND検索、空候補、composition guard、busy時の重複抑制、対象固定、hide→dispatch順序、非表示後の応答、再表示用の結果保存。
- `renderer.test.ts`: 本物のCore/native libraryを使い、入力・選択・結果・エラー・resize・Escを検証。変更区間で`nativeFrameCount`が増え、少なくとも一つの変更frameで`cellsUpdated > 0`となることを確認します。idle後の最新frameに非zero更新を要求しません。
- `protocol.test.ts`: protocol/status、ID対応、catalogの重複等を検証。

UI試験のhelperだけは`tests/fixtures.ts`の代用品です。これは共通helperの実行・tmuxの同一shell継続・Macアプリactivationの試験ではありません。親側の実helper受入試験と分けます。

日本語試験は**確定済み文字列のbracketed paste**です。端末の入力経路からOSのmarked textを観測できる前提にはしていません。modelにはcomposition guardがありますが、Ghosttyの物理IME変換・候補表示・Enter確定と実行の関係、focus、Spaces、ホットキーの快適さは未検証です。UIが動くことからIME受入済みとはしません。

## 作業用データ

`node_modules/`, `dist/`, `.runtime/`はこのディレクトリに閉じています。sandboxでBunの既定cache/tempへ書けない場合は、この試作自身の領域を使えます。

```sh
mkdir -p .runtime/tmp .runtime/bun-cache
TMPDIR="$PWD/.runtime/tmp" BUN_INSTALL_CACHE_DIR="$PWD/.runtime/bun-cache" bun install
```
