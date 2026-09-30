# paneru floating rules

Session application and observed limits: see ../../lab/README.md and runtime/evidence/cleanup-2026-09-12/paneru-config.json. The fragment itself is not an installer.

`paneru-rules.toml` contains three scoped rules for the prototype launchers. Merge the named `[windows.*]` tables into the actual configuration, preserving unrelated settings. Do not replace the whole configuration with this fragment. Existing table names or overlapping rules must be checked before merging. The running paneru is not stopped by this procedure; v0.4.4 documents automatic config reload on save. Existing-window reclassification is not assumed: validate the actual state, and if necessary relaunch only the prototypes after configuration is applied.

The installed executable reports 0.4.4. The [v0.4.4 guide](https://github.com/karinushka/paneru/blob/v0.4.4/CONFIGURATION.md#6-window-rules-windows) specifies `title`, `bundle_id`, and `floating`. The [same-tag matcher](https://github.com/karinushka/paneru/blob/v0.4.4/src/config.rs#L426-L453) compares bundle ID exactly and ANDs it with the title regex. `[windows.<name>]` names are arbitrary rule identifiers, not app names. `app`/`app_name` are not the matching keys here. `manage=true` opts non-standard windows into management; `manage=false` is not the documented floating opt-out, so neither is added.

Native/Tauri match only their dedicated bundle IDs. OpenTUI requires Ghostty AND the exact title `tethr · OpenTUI`; other Ghostty windows remain eligible for tiling. The launcher must establish and preserve this title: shell/tmux title updates that replace it defeat the match.

After applying and opening the target window, `paneru query state` is a read-only observation. Match observed `bundle_id` + `title`, then inspect `floating` on that window. Query output `app_name` is descriptive and is not a replacement for config matching. If a window is absent from state, that does not prove the rule matched: it may be undiscovered, hidden, or excluded before rules. Check OS/AX visibility independently. Native's NSPanel class alone does not guarantee exclusion.

Floating here means exclusion from tiling, not complete invisibility to paneru: focus-following or other window behavior may still affect the experiment. v0.4.4 also documents saved startup state taking precedence over static floating rules during restore; do not restart paneru just to validate this fragment. Actual GUI behavior remains untested by this preparation.
