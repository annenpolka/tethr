# Tethr Tauri Lab

Actual Tauri 2 + Rust + vanilla TypeScript/Vite prototype implementing `../CONTRACT.md`. Rust reads `TETHR_LAB_CONFIG`, executes its external `helperPath` directly with argument arrays, and checks protocol version, response status, action ID and request ID. There is no shell interpolation and no automatic dispatch retry.

## Commands

Run from this directory. Bun, Rust/Cargo and Apple's command-line developer tools are build dependencies; the compiled app uses the system WKWebView and does not require Bun at runtime. The shared Swift helper and lab config are supplied separately by the parent comparison harness.

```sh
bun install
bun test tests                 # Web logic / UI event tests with substitutes
bun run build:web              # TypeScript check + frontend bundle
bun run test:rust              # Rust protocol unit tests; no Mac UI launched
bun run build                  # Real release native binary + ad-hoc signed .app
TETHR_LAB_CONFIG=/absolute/lab/config.json bun run dev:native
```

In a restricted environment, put dependency caches and temp files inside this owned directory:

```sh
mkdir -p .tmp .bun-cache .cargo-home
TMPDIR="$PWD/.tmp" BUN_INSTALL_CACHE_DIR="$PWD/.bun-cache" bun install
TMPDIR="$PWD/.tmp" CARGO_HOME="$PWD/.cargo-home" bun run build
```

Launch the bundled binary directly for a fresh process with an explicit config:

```sh
TETHR_LAB_CONFIG=/absolute/lab/config.json \
  './src-tauri/target/release/bundle/macos/Tethr Tauri Lab.app/Contents/MacOS/tethr-lab-tauri'
```

Escape and the close button hide the existing window. They do not quit the app or cancel the persistent tmux job. To reopen that running instance, use:

```sh
open './src-tauri/target/release/bundle/macos/Tethr Tauri Lab.app'
```

The explicit macOS reopen event shows/focuses the existing window. Do not run the binary again to reopen an existing instance: that can create a second process. Quit the app before changing the config environment. A first launch via Finder/`open` generally does not inherit a shell-local `TETHR_LAB_CONFIG`; use the direct-binary launch above first. Missing/invalid config produces a readable error, not a substitute catalog.

Application actions hide this UI before sending to the helper. A completion or failure only updates the stored result; it never shows or focuses the app. Reopen displays that result. Search can change during an action, but the response stays labelled with the original action and request. Dispatch is gated in both TypeScript and Rust. The 30-second helper timeout reports unknown delivery and never retries; killing a timed-out helper does not mean external work was cancelled.

The app is an ad-hoc signed local comparison artifact, not a notarized public release. No shortcuts, login items, user settings, app permissions or system preferences are installed by this prototype.

## Evidence boundaries

- `bun test` covers all-token filtering, navigation/empty state, duplicate suppression, hide-before-dispatch, original response attribution, failures, stale catalog results and composition guards. Bridge responses and the DOM are substitutes. These do not prove actual Mac focus or real IME conversion.
- `bun run test:rust` runs release-profile Rust protocol tests, including an actual child process using a substitute helper with spaces in its path/arguments, malformed JSON and nonzero exit. This validates the subprocess boundary, not the shared Swift helper. A native build proves the real framework compiles and bundles; it does not prove helper delivery or interactive behavior.
- Parent acceptance separately uses the real helper/config and receiver apps. GUI launch, OS focus, physical IME, multi-Space behavior, native re-open and comfort are not claimed accepted by this directory's headless tests.

The composition guard blocks Enter while composing, `isComposing`, legacy Safari keyCode 229, and composition end through the following key release. OS IME sequences, especially candidate clicks and unusual input methods, still require physical acceptance.

## Real helper diagnostic without launching a UI

This uses the same Rust subprocess/protocol module as the app, but bypasses Web UI input and Tauri IPC. It proves only the Rust-to-helper boundary. `terminal.step` advances the shared lab shell counter; it does not touch an arbitrary user shell.

```sh
TETHR_LAB_CONFIG=/absolute/lab/runtime/config.json \
  CARGO_HOME="$PWD/.cargo-home" TMPDIR="$PWD/.tmp" \
  cargo run --release --manifest-path src-tauri/Cargo.toml --example helper_probe -- catalog
# Repeat with terminal.step or command.git-status in place of catalog.

# After compiling helper_probe, save all raw replies and assert shared shell
# continuity / configured git cwd. This advances the lab shell counter twice.
TETHR_LAB_CONFIG=/absolute/lab/runtime/config.json python3 scripts/validate-helper.py
```

Window geometry is resizable (minimum 420×360). The initial size/centering is a preference, not a focus or usability assertion; parent acceptance retains the user's running paneru window management.

## Validation recorded on 2026-09-12

- Actual dependency install: Tauri CLI 2.11.4, JavaScript API 2.11.1, Rust Tauri 2.11.5; resolved versions are preserved in `bun.lock` and `src-tauri/Cargo.lock`.
- Web/component tests: **11 passed, 42 assertions**; TypeScript check and Vite production build passed.
- Rust release tests: **3 passed**, including an actual substitute child process. No GUI was launched by these tests.
- Native release build produced `Tethr Tauri Lab.app`; `codesign --verify --deep --strict` passed. This is ad-hoc signing, not notarization.
- The real helper diagnostic passed catalog, two `terminal.step` calls and `command.git-status`. Its raw responses, scope and probe/app SHA256 hashes are in `evidence/real-helper.json`. At this recorded run, shell PID 36821 and nonce B34529C1-9351-485D-BF8A-2013EAA44717 were stable, counters advanced 4 → 5, and git exited 0 in the configured cwd. These are run-specific observations, not fixed expected IDs.
- Earlier setup failures were corrected: Bun's default temp directory was unavailable in the sandbox; local caches/temp fixed installation. The initial frontend check found an overly narrow UUID-generator type; it was corrected. The first native compile found the required icon missing; the checked-in SVG/PNG/ICNS now supply it. Final checks above passed after those corrections.
- This agent did not launch any GUI or alter paneru. Parent-managed interactive acceptance, physical IME and focus behavior remain separate and unverified by this record.
