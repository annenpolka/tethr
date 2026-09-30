# Native AppKit comparison prototype

Real NSPanel + NSTextField + NSTableView. No external packages. Requires macOS 13+ and a Swift toolchain.

```sh
cd native
./test.sh
./build-app.sh
open 'dist/Tethr Native.app' --args --config /absolute/path/to/config.json
```

For initial foreground terminal launch, `TETHR_LAB_CONFIG=/absolute/config.json swift run TethrNative` also works. Reopen the packaged app with `open 'dist/Tethr Native.app'`; it shows the existing panel. Config is loaded once at launch, so quit and relaunch to change it. `--config PATH` takes precedence over the environment.

Search matches all lowercase whitespace-separated tokens against title/subtitle/keywords, retaining catalog order. Up/down selects and Enter runs. A button is also available. AppKit marked text prevents navigation/Enter interception while composing; this is implementation intent, not physical IME acceptance. Esc hides the panel; closing the window preserves the process. App actions hide before asynchronous helper dispatch and never reactivate on completion; errors remain visible when reopened.

Helper execution uses Process argument arrays, a 30-second timeout, and temporary output files to avoid pipe deadlocks. Dispatch is never retried. Timeout outcome is explicitly unknown. The shared helper is supplied by the parent; no fixture/helper is implemented here.

`./test.sh` (SwiftPM XCTest) covers matching/order, empty result, navigation bounds, busy duplicate prevention, composition gating, and protocol/result/error validation. These are non-UI logic tests; they do not prove macOS input focus, actual IME conversion, or native app activation. GUI acceptance is deliberately reserved for the parent running the actual helper and observer serially.

Standard app/edit menus provide Quit (Cmd-Q), Hide (Cmd-H), Select All, Cut, Copy, Paste and Undo/Redo through the responder chain.

Opt-in real helper integration (no GUI/application actions):

```sh
TETHR_NATIVE_LIVE_CONFIG=/absolute/runtime/config.json ./test.sh
```

This executes one real `terminal.step` and one read-only `command.git-status`, checks protocol IDs/results and prints receipts. Without the variable, that test is explicitly skipped.

The UI delegate and async UI continuations are explicitly `@MainActor`; helper process work remains detached. Runtime main-queue preconditions guard display/refresh. The panel explicitly disables hidesOnDeactivate and floating level so a delayed activation does not silently hide it; actual paneru management remains an observed property, not a class assumption.
