# Native helper integration — 2026-09-12

Actual `TETHR_NATIVE_LIVE_CONFIG=../runtime/config.json ./test.sh` run: 4 XCTest tests passed (3 core, 1 live integration), zero failures. No GUI launched and no app actions dispatched.

- terminal.step request A11E771E-E043-4C37-BE24-AC29C9D785EA: status ok, counter 1, shellPID 36821, shellNonce B34529C1-9351-485D-BF8A-2013EAA44717, cwd /Users/annenpolka/ghq/github.com/annenpolka/tethr.
- command.git-status request C44A3DA7-E5B8-4282-BB61-26E8AD57AFFA: status ok, exitCode 0, stderr empty; stdout listed untracked .gitignore, README.md, docs/.

These results prove one round trip through NativeCore.Helper for both action types. They do not by themselves establish successive shell continuity, GUI focus, menu interaction, or physical IME behavior.
