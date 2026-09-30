# Native startup deadlock repair — 2026-09-12

Evidence: parent's `runtime/evidence/native-sample.txt`, PID 44020. During all 892 samples main thread was in NSScrollView/NSTextLayoutManager layout waiting on a lock, while a cooperative executor thread was in Delegate.load() → NSTextView replaceCharacters → NSTextLayoutManager and also waiting on a lock. The code's unisolated async load/display path allowed AppKit mutation off-main. This is direct evidence of an application threading bug; it does not implicate paneru.

Repair:

- Explicit @MainActor on Delegate, ActionPanel and the @main entry point. UI Tasks explicitly inherit @MainActor; Helper process work remains detached.
- Main queue preconditions in display and refresh prevent a silent off-main regression.
- NSPanel hidesOnDeactivate=false, isFloatingPanel=false. Delayed/denied activation will not automatically hide it. No assertion about paneru's management decision.
- Renamed executable entry file from main.swift to App.swift for the explicit @main entry point.

Core tests and release packaging are rerun. Parent must stop the previous stuck instance and launch the updated app to validate actual AX responsiveness/visibility. This agent did not manipulate the running GUI process.
