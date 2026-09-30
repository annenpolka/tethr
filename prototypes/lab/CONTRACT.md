# tethr prototype comparison — frozen first slice

This is an exploratory implementation authorized by the user on 2026-09-12, following the testing strategy. Three real UIs share the same helper to isolate UI differences: OpenTUI/Bun, native AppKit/Swift, Tauri/Web/Rust. This does not compare three independent backend implementations.

## Common behavior

- Load a catalog from the helper, filter title + subtitle + keywords by lowercase whitespace-separated tokens (all tokens must match), preserving catalog order.
- Search field, selectable results, explicit execution, readable result/error. Up/down navigate; Enter executes only when not composing and not already busy. Empty results do not execute. Escape hides/closes the view without killing the shared tmux shell. A new launch/reopen can return to the UI.
- Do not install global shortcuts or change user settings in this slice. Launch via the supplied launcher commands. Global-hotkey behavior and physical IME acceptance remain separate from component input tests.
- terminal.step executes in an isolated persistent lab-owned tmux shell and returns its nonce/counter/PID/cwd; successive invocations from any UI share this state. command.git-status starts a NEW read-only git process in configured cwd; do not call that existing-shell continuity.
- app.* launches or raises a configured Mac application. After the user executes an app action, avoid refocusing the UI when the response arrives. Hide UI before dispatching app actions; report an error on reopen when needed.
- Actual framework libraries and AppKit calls; no mock UI presented as a working prototype. Tests using substitutes are labelled.

## Files and ownership

Parent: common/, scripts/, tests/, fixture/, runtime/, root docs.
OpenTUI agent: opentui/ only. Native agent: native/ only. Tauri agent: tauri/ only. Do not alter another owner's files.

## Config and helper protocol (v1)

All UIs accept a config file path from TETHR_LAB_CONFIG; native also accepts --config PATH, Tauri reads the env in its Rust process. Config JSON:

    {"protocolVersion":1,"helperPath":"/absolute/path/to/tethr-helper","stateDir":"/absolute/lab/state","cwd":"/absolute/repo","tmuxPath":"/opt/homebrew/bin/tmux","apps":[{"id":"app.fixture-b","title":"受信アプリ B","subtitle":"run-or-raise","keywords":"application app fixture アプリ","bundleID":"com.tethr.lab.receiver-b","path":"/absolute/Receiver B.app"}]}

Invoke executable helperPath directly with argument array, no shell interpolation:

    helperPath --config CONFIG catalog
    helperPath --config CONFIG dispatch ACTION_ID --request-id UNIQUE_ID

Helper emits exactly one JSON object on stdout and exits. Logs/errors must not pollute stdout. stderr is diagnostic. Runtime timeout can report failure/unknown; do not automatically retry a dispatch.

Catalog response:

    {"protocolVersion":1,"status":"ok","items":[{"id":"terminal.step","title":"同じシェルで続ける","subtitle":"試験用 tmux の状態を確認・更新","keywords":"terminal shell tmux ターミナル 続き","kind":"terminal"},{"id":"command.git-status","title":"変更状況を見る","subtitle":"設定したリポジトリの git status","keywords":"git status changes 変更 リポジトリ","kind":"command"},{"id":"app.fixture-b","title":"受信アプリ B","subtitle":"run-or-raise","keywords":"app","kind":"application"}]}

Dispatch success:

    {"protocolVersion":1,"status":"ok","requestID":"...","actionID":"terminal.step","title":"同じシェルで続ける","message":"...human-readable...","data":{"counter":1,"shellPID":123,"shellNonce":"...","cwd":"..."}}

Application data: {bundleID,pid,wasRunning,frontmostObserved}. Command data: {stdout,stderr,exitCode,cwd}. On failure:

    {"protocolVersion":1,"status":"error","requestID":"...","actionID":"...","message":"...human-readable...","errorCode":"..."}

Helper availability is not required to build UI or run isolated UI tests. Parent supplies real helper/config later. Match this protocol exactly and fail visibly on invalid JSON/status or process failure.

## Test and completion contract

Build each actual runtime. Test filtering, empty selection, busy/duplicate dispatch, and output/error presentation at the smallest meaningful boundary. Native/OS interaction remains separately verified. Tests must not weaken expected outcomes to match a faulty implementation. Parent acceptance will use the REAL helper for terminal state/command results, no-op activation negative control, external frontmost observation, and receiver fixtures where the environment supports it. Preserve unknown/not-run outcomes.

Native UI input must respect AppKit marked text; Web UI must respect composition events; OpenTUI tests of committed text do not prove macOS IME. No UI success claims from headless tests alone. No automatic retries or focus-repair clicks in the focus acceptance interval.

Human residue: physical IME conversion, candidate-window comfort, launcher/hotkey experience, multi-Space/window preference, performance preference. This slice does not claim these accepted.

Descent check: even if tests pass, native IME and global keyboard focus could still fail. They stay explicit separate checks. User's request authorizes implementing these exploratory variants; no further approval is required to create/build/test the owned prototypes.
