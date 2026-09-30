#!/usr/bin/env python3
from pathlib import Path
import argparse
import json
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--cwd', type=Path, default=ROOT)
parser.add_argument('--config', type=Path, default=ROOT / 'runtime/config.json')
parser.add_argument('--fresh', action='store_true', help='Create a fresh isolated state directory; does not delete old state.')
args = parser.parse_args()
args.config.parent.mkdir(parents=True, exist_ok=True)
if args.config.exists() and not args.fresh:
    config = json.loads(args.config.read_text())
    state = config['stateDir']
else:
    state = tempfile.mkdtemp(prefix='tethr-lab-', dir='/private/tmp')
helper = ROOT / 'runtime/bin/tethr-helper'
if not helper.exists():
    raise SystemExit('Build common first: python3 scripts/build-common.py')
apps = []
for role in ('a', 'b'):
    apps.append({'id': f'app.fixture-{role}', 'title': f'受信アプリ {role.upper()}',
                 'subtitle': '起動・前面化を試す', 'keywords': f'app application fixture receiver {role} アプリ 受信',
                 'bundleID': f'com.tethr.lab.receiver-{role}',
                 'path': str(ROOT / 'runtime/apps' / f'Tethr Receiver {role.upper()}.app')})
if Path('/Applications/Ghostty.app').exists():
    apps.append({'id': 'app.ghostty', 'title': 'Ghostty', 'subtitle': 'ターミナルへ戻る',
                 'keywords': 'app terminal ghostty ターミナル', 'bundleID': 'com.mitchellh.ghostty',
                 'path': '/Applications/Ghostty.app'})
config = {'protocolVersion': 1, 'helperPath': str(helper), 'stateDir': state,
          'cwd': str(args.cwd.resolve()), 'tmuxPath': shutil.which('tmux'), 'apps': apps}
if not config['tmuxPath']:
    raise SystemExit('tmux is required.')
args.config.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')
print(args.config.resolve())
