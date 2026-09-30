#!/usr/bin/env python3
"""Build the real macOS helper, independent observer, and receipt fixture apps."""
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
runtime = ROOT / 'runtime'
binary_dir = runtime / 'bin'
module_cache = runtime / 'swift-module-cache'
binary_dir.mkdir(parents=True, exist_ok=True)
module_cache.mkdir(parents=True, exist_ok=True)

def compile_swift(source, output, flags=()):
    subprocess.run(['swiftc', '-swift-version', '5', '-O', '-module-cache-path', str(module_cache),
                    *flags, str(ROOT / source), '-o', str(output)], check=True)

compile_swift('common/Helper.swift', binary_dir / 'tethr-helper')
compile_swift('common/Helper.swift', binary_dir / 'tethr-helper-faults', ['-D', 'LAB_FAULTS'])
compile_swift('common/Observer.swift', binary_dir / 'tethr-observer')
compile_swift('fixture/Receiver.swift', binary_dir / 'tethr-receiver')
for role in ('a', 'b'):
    name = f'Tethr Receiver {role.upper()}'
    contents = runtime / 'apps' / f'{name}.app' / 'Contents'
    macos = contents / 'MacOS'
    macos.mkdir(parents=True, exist_ok=True)
    target = macos / 'receiver'
    target.write_bytes((binary_dir / 'tethr-receiver').read_bytes())
    target.chmod(0o755)
    info = {'CFBundleIdentifier': f'com.tethr.lab.receiver-{role}', 'CFBundleName': name,
            'CFBundleDisplayName': name, 'CFBundleExecutable': 'receiver', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1',
            'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication'}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(contents.parent)], check=True)
print('Built helper, independent observer, and Receiver A/B.')
