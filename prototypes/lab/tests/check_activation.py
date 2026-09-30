#!/usr/bin/env python3
"""Host-only Receiver A/B frontmost check; never run alongside other GUI trials.

OS frontmost only: no untargeted keyboard/IME or prototype hide-return claim.
Cold Receiver B is a checked precondition, never automatically terminated.
"""
from pathlib import Path
import argparse
import json
import os
import select
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--config', type=Path, default=ROOT / 'runtime/config.json')
args = parser.parse_args()
config = json.loads(args.config.read_text())
observer = ROOT / 'runtime/bin/tethr-observer'
evidence = ROOT / 'runtime/evidence/activation'
evidence.mkdir(parents=True, exist_ok=True)
fault = dict(config, helperPath=str(ROOT / 'runtime/bin/tethr-helper-faults'))
fault_path = evidence / 'fault-config.json'
fault_path.write_text(json.dumps(fault))


def require_cold_owned_b():
    """Read NSRunningApplication, not process-name matching. No termination API."""
    entry = next(x for x in config['apps'] if x['id'] == 'app.fixture-b')
    expected_path = ROOT / 'runtime/apps/Tethr Receiver B.app'
    assert entry['bundleID'] == 'com.tethr.lab.receiver-b', 'Unexpected fixture identity'
    assert Path(entry['path']).resolve() == expected_path.resolve(), 'Unexpected fixture path'
    script = """ObjC.import('AppKit');
var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('com.tethr.lab.receiver-b');
var rows = [];
for (var i = 0; i < apps.count; i++) {
    var app = apps.objectAtIndex(i);
    rows.push({pid: Number(app.processIdentifier), path: ObjC.unwrap(app.bundleURL.path)});
}
JSON.stringify(rows);"""
    p = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', '-e', script],
                       capture_output=True, text=True, check=True, timeout=15)
    running = json.loads(p.stdout)
    assert isinstance(running, list), 'Cannot establish cold fixture precondition'
    assert not running, ('PRECONDITION: Receiver B is already running. Parent must close the exact '
                         'owned fixture before retrying. No process was terminated.', running)


def dispatch(action, cfg=args.config, injected=False):
    current = json.loads(cfg.read_text())
    env = dict(os.environ)
    if injected:
        env['TETHR_LAB_FAULT'] = 'noop-activation'
    request = uuid.uuid4().hex
    p = subprocess.run([current['helperPath'], '--config', str(cfg), 'dispatch', action,
                        '--request-id', request], capture_output=True, text=True, env=env, timeout=20)
    response = json.loads(p.stdout)
    valid = (response.get('protocolVersion') == 1 and response.get('requestID') == request
             and response.get('actionID') == action and response.get('status') in ('ok', 'error'))
    return {'exitCode': p.returncode, 'response': response, 'stderr': p.stderr,
            'expectedRequestID': request, 'expectedActionID': action, 'protocolValid': valid}


def snapshot():
    p = subprocess.run([str(observer)], capture_output=True, text=True, check=True, timeout=10)
    return json.loads(p.stdout)


rows = []


def trial(name, setup_action, target, negative=False, expected_was_running=None):
    setup = dispatch(setup_action)
    assert setup['exitCode'] == 0 and setup['protocolValid'] and setup['response']['status'] == 'ok', setup
    before = snapshot()
    expected_origin = next(x for x in config['apps'] if x['id'] == setup_action)['bundleID']
    assert before['bundleID'] == expected_origin, before
    path = evidence / f'{name}-observer.jsonl'
    watcher = subprocess.Popen([str(observer), '5'], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, bufsize=0)
    payload = b''
    observer_error = ''
    action = None
    try:
        # Wait for actual observer evidence before triggering any product action.
        if not select.select([watcher.stdout], [], [], 3)[0]:
            raise RuntimeError('Observer did not become ready')
        first = watcher.stdout.readline()
        baseline = json.loads(first)
        if baseline['bundleID'] != expected_origin or baseline['pid'] != before['pid']:
            raise RuntimeError('Origin changed before dispatch')
        payload = first
        action = dispatch(target, fault_path if negative else args.config, negative)
        tail, stderr = watcher.communicate(timeout=12)
        payload += tail
        observer_error = stderr.decode(errors='replace')
    except Exception as exc:
        observer_error = str(exc)
        watcher.terminate()
        tail, stderr = watcher.communicate(timeout=5)
        payload += tail
        observer_error += '\n' + stderr.decode(errors='replace')
    path.write_bytes(payload)
    observations = []
    health_error = None
    try:
        observations = [json.loads(line) for line in payload.splitlines()]
        starts = [int(x['sampleStart']) for x in observations]
        ends = [int(x['sampleEnd']) for x in observations]
        assert watcher.returncode == 0, 'observer exit not zero'
        assert action is not None, 'no completed dispatch'
        assert len(observations) >= 8, 'fewer than eight samples'
        assert all(a <= b for a, b in zip(starts, ends)), 'reversed sample interval'
        assert all(a < b for a, b in zip(starts, starts[1:])), 'nonmonotonic samples'
        assert ends[-1] - starts[0] >= 4_000_000_000, 'insufficient observation duration'
        assert ends[-1] - starts[-8] >= 100_000_000, 'insufficient final stability interval'
    except Exception as exc:
        health_error = str(exc)
    expected = next(x for x in config['apps'] if x['id'] == target)['bundleID']
    response = action['response'] if action else {}
    success_response = bool(action and action['exitCode'] == 0 and action['protocolValid']
                            and response.get('status') == 'ok')
    identity_valid = (expected_was_running is None or
                      response.get('data', {}).get('wasRunning') is expected_was_running)
    final_matches = (len(observations) >= 8 and all(x.get('bundleID') == expected
                     and x.get('pid') == response.get('data', {}).get('pid') for x in observations[-8:]))
    frontmost_pass = health_error is None and success_response and identity_valid and final_matches
    row = {'name': name, 'before': before, 'dispatch': action,
           'observerExit': watcher.returncode, 'observerStderr': observer_error,
           'observerHealthy': health_error is None, 'healthError': health_error,
           'samples': len(observations), 'final': observations[-1] if observations else None,
           'frontmostContract': 'INCONCLUSIVE' if health_error else 'PASS' if frontmost_pass else 'FAIL',
           'expectedWasRunning': expected_was_running, 'negativeControl': negative,
           'untargetedKeyboardReceipt': 'NOT_RUN', 'physicalIME': 'NOT_RUN'}
    if negative:
        # Healthy unchanged origin + deliberate false success, not any generic failure.
        row['negativeControlDetected'] = (health_error is None and success_response
            and response.get('data', {}).get('faultInjected') == 'noop-activation'
            and not frontmost_pass and all(x.get('bundleID') == expected_origin
                                         and x.get('pid') == before['pid'] for x in observations))
    rows.append(row)
    (evidence / 'result.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(row, ensure_ascii=False), flush=True)
    assert health_error is None, 'Observer/precondition inconclusive, not a product verdict: ' + str(health_error)
    assert row.get('negativeControlDetected', frontmost_pass), row


# Fail safely if a previous owned fixture is present; parent closes it explicitly.
require_cold_owned_b()
trial('no-op-must-fail', 'app.fixture-a', 'app.fixture-b', negative=True)
require_cold_owned_b()
trial('launch-b', 'app.fixture-a', 'app.fixture-b', expected_was_running=False)
first_pid = rows[-1]['dispatch']['response']['data']['pid']
trial('raise-existing-b', 'app.fixture-a', 'app.fixture-b', expected_was_running=True)
assert rows[-1]['dispatch']['response']['data']['pid'] == first_pid
trial('already-front-b', 'app.fixture-b', 'app.fixture-b', expected_was_running=True)
assert rows[-1]['dispatch']['response']['data']['pid'] == first_pid
print('Frontmost-state integration passed; keyboard focus and IME remain separate checks.')
