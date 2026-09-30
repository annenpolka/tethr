#!/usr/bin/env python3
"""Apply only the lab's scoped floating rules; restore only an unchanged result."""
import argparse
import hashlib
import json
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=['check', 'apply', 'restore'])
parser.add_argument('--config', type=Path, default=Path.home() / '.paneru.toml')
args = parser.parse_args()
path = args.config.expanduser().resolve()
receipt = ROOT / 'runtime/evidence/paneru-config.json'
backup = ROOT / 'runtime/evidence/paneru-config.before.toml'
digest = lambda data: hashlib.sha256(data).hexdigest()
raw = path.read_bytes()
fragment = (ROOT / 'scripts/paneru-rules.toml').read_bytes()
rules = tomllib.loads(fragment.decode())['windows']
config = tomllib.loads(raw.decode())
if args.action == 'restore':
    saved = json.loads(receipt.read_text())
    original = backup.read_bytes()
    if str(path) != saved['path'] or digest(raw) != saved['afterSHA256'] or digest(original) != saved['beforeSHA256']:
        raise SystemExit('Config changed after installation; merge/remove only tethr_lab_* tables manually.')
    with path.open('r+b') as stream:
        if stream.read() != raw:
            raise SystemExit('Concurrent config change; no write.')
        stream.seek(0); stream.write(original); stream.truncate()
    print('Restored original config; paneru remains running.')
else:
    existing = config.get('windows', {})
    if all(existing.get(name) == value for name, value in rules.items()):
        print('Exact lab rules already present; no change.')
        raise SystemExit(0)
    if any(name in existing for name in rules):
        raise SystemExit('Existing lab table conflicts; inspect before merging.')
    if existing:
        raise SystemExit('Other window rules exist; inspect overlap before applying.')
    merged = raw.rstrip() + b'\n\n' + fragment
    tomllib.loads(merged.decode())
    if args.action == 'check':
        print('Valid: only three new scoped window tables will be appended.')
    else:
        receipt.parent.mkdir(parents=True, exist_ok=True)
        if receipt.exists() or backup.exists():
            raise SystemExit('Prior installation evidence exists; inspect before applying again.')
        backup.write_bytes(raw)
        with path.open('r+b') as stream:
            if stream.read() != raw:
                raise SystemExit('Concurrent config change; no write.')
            stream.seek(0); stream.write(merged); stream.truncate()
        receipt.write_text(json.dumps({'path': str(path), 'beforeSHA256': digest(raw), 'afterSHA256': digest(merged), 'tables': list(rules)}, indent=2) + '\n')
        print('Applied three scoped floating rules; backup and hashes saved. paneru was not restarted.')
