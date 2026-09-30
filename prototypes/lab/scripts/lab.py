#!/usr/bin/env python3
"""Relocatable orchestration for the three tethr prototype UIs.

This wrapper does not install paneru rules, alter permissions, or operate a GUI
unless the user explicitly invokes `run native` or `run tauri`.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

LAB = Path(__file__).resolve().parents[1]
VARIANTS = ("native", "tauri", "opentui")
TITLE = "tethr · OpenTUI"


class LabError(Exception):
    pass


def selected(target: str) -> tuple[str, ...]:
    return VARIANTS if target == "all" else (target,)


def run_step(argv: list[str | Path], *, cwd: Path = LAB, env: dict[str, str] | None = None, dry: bool = False) -> None:
    command = [str(arg) for arg in argv]
    print(f"[{cwd.relative_to(LAB) if cwd.is_relative_to(LAB) else cwd}] {shlex.join(command)}", flush=True)
    if not dry:
        subprocess.run(command, cwd=cwd, env=env, check=True)


def runtime_env(variant: str | None, *, dry: bool) -> dict[str, str]:
    env = os.environ.copy()
    if variant == "tauri":
        base = LAB / "tauri"
        directories = {"TMPDIR": base / ".tmp", "CARGO_HOME": base / ".cargo-home", "BUN_INSTALL_CACHE_DIR": base / ".bun-cache"}
    elif variant == "opentui":
        base = LAB / "opentui/.runtime"
        directories = {"TMPDIR": base / "tmp", "BUN_INSTALL_CACHE_DIR": base / "bun-cache"}
    else:
        directories = {"TMPDIR": LAB / "runtime/tmp"}
    for name, path in directories.items():
        env[name] = str(path)
        if not dry:
            path.mkdir(parents=True, exist_ok=True)
    return env


def common_ready() -> bool:
    artifacts = [LAB / "runtime/bin" / name for name in ("tethr-helper", "tethr-helper-faults", "tethr-observer", "tethr-receiver")]
    artifacts += [LAB / f"runtime/apps/Tethr Receiver {role}.app/Contents/MacOS/receiver" for role in ("A", "B")]
    return all(path.is_file() for path in artifacts)


def build_common(*, dry: bool, force: bool = False) -> None:
    if force or not common_ready():
        run_step([sys.executable, LAB / "scripts/build-common.py"], env=runtime_env(None, dry=dry), dry=dry)


def bun_install(variant: str, *, dry: bool, force: bool = False) -> None:
    base = LAB / variant
    if force or not (base / "node_modules").is_dir():
        run_step(["bun", "install", "--frozen-lockfile"], cwd=base, env=runtime_env(variant, dry=dry), dry=dry)


def config_path(args: argparse.Namespace) -> Path:
    return Path(args.config or os.environ.get("TETHR_LAB_CONFIG") or LAB / "runtime/config.json").expanduser().resolve()


def read_config(path: Path, *, require_local_paths: bool = False) -> dict:
    try:
        config = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise LabError(f"Cannot read config {path}: {error}. Run `prepare` first.") from error
    if not isinstance(config, dict) or config.get("protocolVersion") != 1:
        raise LabError("Config must use protocolVersion 1.")
    for field in ("helperPath", "stateDir", "cwd", "tmuxPath"):
        value = config.get(field)
        if not isinstance(value, str) or not Path(value).is_absolute():
            raise LabError(f"Config {field} must be an absolute path.")
    if require_local_paths and Path(config["helperPath"]).resolve() != (LAB / "runtime/bin/tethr-helper").resolve():
        raise LabError("The default config still points at another lab location. Run `prepare --fresh --cwd PATH` after moving the lab.")
    for field in ("helperPath", "tmuxPath"):
        if not os.access(config[field], os.X_OK):
            raise LabError(f"Config {field} is not executable: {config[field]}")
    if not Path(config["cwd"]).is_dir():
        raise LabError(f"Configured cwd is missing: {config['cwd']}")
    if require_local_paths:
        apps = config.get("apps", [])
        if not isinstance(apps, list) or any(not isinstance(item, dict) for item in apps):
            raise LabError("Config apps must be an array of objects.")
        for item in apps:
            for role in ("a", "b"):
                if item.get("id") == f"app.fixture-{role}":
                    expected = LAB / f"runtime/apps/Tethr Receiver {role.upper()}.app"
                    app_value = item.get("path")
                    if not isinstance(app_value, str) or Path(app_value).resolve() != expected.resolve():
                        raise LabError("Receiver paths still refer to another lab. Run `prepare` after moving it.")
    return config


def prepare(args: argparse.Namespace) -> None:
    path = config_path(args)
    build_common(dry=args.dry_run)
    if args.cwd:
        cwd = Path(args.cwd).expanduser().resolve()
    elif path.exists():
        try:
            cwd = Path(json.loads(path.read_text())["cwd"]).resolve()
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise LabError("Existing config is invalid; supply --cwd and repair/remove that config before preparing.") from error
    else:
        # A relocated lab inside a checkout defaults to that checkout, without hard-coded user paths.
        cwd = next((parent for parent in (LAB, *LAB.parents) if (parent / ".git").exists()), LAB)
    if not cwd.is_dir():
        raise LabError(f"Working directory does not exist: {cwd}")
    command: list[str | Path] = [sys.executable, LAB / "scripts/prepare.py", "--config", path, "--cwd", cwd]
    if args.fresh:
        command.append("--fresh")
    run_step(command, env=runtime_env(None, dry=args.dry_run), dry=args.dry_run)
    if "opentui" in selected(args.target):
        bun_install("opentui", dry=args.dry_run, force=True)
    print(f"Config: {path}")
    print("Before GUI use, apply only the scoped prototype rules in scripts/paneru-rules.toml. This command never applies them.")


def build(args: argparse.Namespace) -> None:
    if args.target == "common":
        build_common(dry=args.dry_run, force=True)
        return
    build_common(dry=args.dry_run, force=args.target == "all")
    for variant in selected(args.target):
        env = runtime_env(variant, dry=args.dry_run)
        if variant == "native":
            run_step(["/bin/sh", LAB / "native/build-app.sh"], cwd=LAB / variant, env=env, dry=args.dry_run)
        else:
            bun_install(variant, dry=args.dry_run, force=True)
            run_step(["bun", "run", "build"], cwd=LAB / variant, env=env, dry=args.dry_run)


def test(args: argparse.Namespace) -> None:
    # Tests that share the lab shell are intentionally run in sequence, never in parallel.
    if args.target in ("all", "common"):
        build_common(dry=args.dry_run, force=True)
        run_step([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_backend.py", "-v"], env=runtime_env(None, dry=args.dry_run), dry=args.dry_run)
    if args.target == "common":
        return
    path = config_path(args)
    if args.live and not args.dry_run:
        read_config(path, require_local_paths=path == LAB / "runtime/config.json")
    for variant in selected(args.target):
        env = runtime_env(variant, dry=args.dry_run)
        # A shell's opt-in environment must not accidentally turn a component run into a live run.
        env.pop("TETHR_NATIVE_LIVE_CONFIG", None)
        env.pop("TETHR_LAB_CONFIG", None)
        if args.live:
            env["TETHR_LAB_CONFIG"] = str(path)
            env["TETHR_NATIVE_LIVE_CONFIG"] = str(path)
        if variant == "native":
            run_step(["/bin/sh", LAB / "native/test.sh"], cwd=LAB / variant, env=env, dry=args.dry_run)
        else:
            bun_install(variant, dry=args.dry_run)
            if variant == "opentui":
                run_step(["bun", "run", "typecheck"], cwd=LAB / variant, env=env, dry=args.dry_run)
                run_step(["bun", "test", "--timeout", "15000"], cwd=LAB / variant, env=env, dry=args.dry_run)
                if args.live:
                    run_step(["bun", "tests/real-helper.ts"], cwd=LAB / variant, env=env, dry=args.dry_run)
            else:
                run_step(["bun", "test", "tests"], cwd=LAB / variant, env=env, dry=args.dry_run)
                # generate_context! needs frontendDist even for Rust tests in a fresh checkout.
                run_step(["bun", "run", "build:web"], cwd=LAB / variant, env=env, dry=args.dry_run)
                run_step(["bun", "run", "test:rust"], cwd=LAB / variant, env=env, dry=args.dry_run)
                if args.live:
                    run_step(["cargo", "build", "--release", "--manifest-path", "src-tauri/Cargo.toml", "--example", "helper_probe"], cwd=LAB / variant, env=env, dry=args.dry_run)
                    run_step([sys.executable, "scripts/validate-helper.py"], cwd=LAB / variant, env=env, dry=args.dry_run)


def app_path(variant: str) -> Path:
    candidates = {
        "native": [LAB / "native/dist/Tethr Native.app"],
        "tauri": [LAB / "tauri/src-tauri/target/release/bundle/macos/Tethr Tauri Lab.app", LAB / "tauri/dist/Tethr Tauri Lab.app"],
    }[variant]
    for path in candidates:
        if (path / "Contents/Info.plist").is_file():
            return path
    raise LabError(f"No built {variant} app. Run `build {variant}` first. Searched: " + ", ".join(map(str, candidates)))


def run(args: argparse.Namespace) -> None:
    path = config_path(args)
    if not args.dry_run:
        read_config(path, require_local_paths=path == LAB / "runtime/config.json")
    if args.target in ("native", "tauri"):
        app = app_path(args.target)
        command: list[str | Path] = ["/usr/bin/open", "--env", f"TETHR_LAB_CONFIG={path}", app]
        if args.target == "native":
            command += ["--args", "--config", path]
        print("Reopens an existing app without forcing a second instance. A running process keeps its original config; quit it first to change configs.")
        run_step(command, dry=args.dry_run)
        print("Open request planned (dry-run)." if args.dry_run else "Open requested; this is not a focus/keyboard-delivery acceptance result.")
        return
    base = LAB / "opentui"
    bundle = base / "dist/main.js"
    if not bundle.is_file():
        raise LabError("OpenTUI bundle is missing. Run `build opentui` first.")
    if not (base / "node_modules/@opentui/core").is_dir():
        raise LabError("OpenTUI native runtime dependency is missing. Run `prepare opentui` first.")
    if args.dry_run:
        print(f"Current terminal: push/set title to {TITLE!r}, run Bun, then restore title on exit.")
        run_step(["bun", bundle], cwd=base, dry=True)
        return
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise LabError("OpenTUI needs an interactive terminal. Run this command in a dedicated Ghostty window, outside tmux for the title-scoped paneru rule.")
    env = os.environ.copy()
    env["TETHR_LAB_CONFIG"] = str(path)
    # Xterm-compatible title stack. No paneru config or other Ghostty window is modified.
    sys.stdout.write(f"\x1b[22;0t\x1b]0;{TITLE}\x07")
    sys.stdout.flush()
    try:
        run_step(["bun", bundle], cwd=base, env=env)
    finally:
        sys.stdout.write("\x1b[23;0t")
        sys.stdout.flush()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    for name in ("prepare", "build", "test", "run"):
        sub = commands.add_parser(name)
        choices = VARIANTS if name == "run" else ("all", *VARIANTS, *(("common",) if name in ("build", "test") else ()))
        sub.add_argument("target", choices=choices, **({} if name == "run" else {"nargs": "?", "default": "all"}))
        sub.add_argument("--dry-run", action="store_true", help="Print planned commands without executing, creating caches, or opening a GUI.")
        if name in ("prepare", "test", "run"):
            sub.add_argument("--config", help="Config path; overrides TETHR_LAB_CONFIG and runtime/config.json.")
        if name == "prepare":
            sub.add_argument("--cwd", help="Working repository/directory for lab commands.")
            sub.add_argument("--fresh", action="store_true", help="Create new isolated lab state; preserve old state and processes.")
        if name == "test":
            sub.add_argument("--live", action="store_true", help="Also exercise each selected UI adapter against the real shared helper. Advances the lab shell counter; no app actions.")
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if sys.platform != "darwin" and not args.dry_run:
            raise LabError("The shared helper and these comparison apps require macOS.")
        {"prepare": prepare, "build": build, "test": test, "run": run}[args.command](args)
        return 0
    except LabError as error:
        print(f"lab: {error}", file=sys.stderr)
        return 2
    except FileNotFoundError as error:
        print(f"lab: Required tool/file is missing: {error}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as error:
        print(f"lab: Command failed with exit {error.returncode}; no automatic retry.", file=sys.stderr)
        return error.returncode if error.returncode > 0 else 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
