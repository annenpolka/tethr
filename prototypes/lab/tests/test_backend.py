import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'runtime/bin/tethr-helper'

class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tethr-check-', dir='/private/tmp')
        self.root = Path(self.temp.name)
        self.cwd = self.root / "日本語 repo 'quoted'"
        self.cwd.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.cwd)], check=True)
        (self.cwd / 'changed.txt').write_text('receipt fixture\n')
        self.state = self.root / 'state'
        self.config = self.root / 'config.json'
        self.config.write_text(json.dumps({'protocolVersion': 1, 'helperPath': str(HELPER),
            'stateDir': str(self.state), 'cwd': str(self.cwd), 'tmuxPath': shutil.which('tmux'), 'apps': []}))

    def tearDown(self):
        # Only touch this test's exact socket, never the user's tmux server.
        subprocess.run(['tmux', '-S', str(self.state / 'tmux.sock'), 'kill-server'], capture_output=True)
        stopped = subprocess.run(['tmux', '-S', str(self.state / 'tmux.sock'), 'list-sessions'], capture_output=True)
        self.assertNotEqual(stopped.returncode, 0)
        self.temp.cleanup()

    def call(self, action=None, request=None):
        args = [str(HELPER), '--config', str(self.config)]
        args += ['dispatch', action, '--request-id', request or uuid.uuid4().hex] if action else ['catalog']
        p = subprocess.run(args, capture_output=True, text=True, timeout=25)
        return p.returncode, json.loads(p.stdout)

    def test_catalog_and_real_git_result(self):
        code, catalog = self.call()
        self.assertEqual(code, 0)
        self.assertEqual([x['id'] for x in catalog['items']], ['terminal.step', 'command.git-status'])
        code, result = self.call('command.git-status')
        self.assertEqual(code, 0, result)
        self.assertEqual(result['data']['stdout'], '?? changed.txt\n')
        self.assertEqual(result['data']['cwd'], str(self.cwd))

    def test_original_shell_state_survives_helper_exit(self):
        _, first = self.call('terminal.step')
        code, second = self.call('terminal.step')
        self.assertEqual(code, 0, second)
        a, b = first['data'], second['data']
        self.assertEqual((a['counter'], b['counter']), (1, 2))
        self.assertEqual(a['shellNonce'], b['shellNonce'])
        self.assertEqual(a['shellPID'], b['shellPID'])
        self.assertEqual(b['shellPID'], b['parentPID'])
        self.assertEqual(b['cwd'], str(self.cwd))
        # This is the child-created receipt, not the helper's reported success.
        receipt = json.loads((self.state / 'receipts' / (second['requestID'] + '.json')).read_text())
        self.assertEqual(receipt, b)

    def test_concurrent_requests_serialize_in_same_shell(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.call('terminal.step'), range(2)))
        self.assertTrue(all(code == 0 for code, _ in results), results)
        data = [record['data'] for _, record in results]
        self.assertEqual(sorted(x['counter'] for x in data), [1, 2])
        self.assertEqual(len({x['shellNonce'] for x in data}), 1)

    def test_duplicate_request_does_not_execute_again(self):
        request = uuid.uuid4().hex
        self.assertEqual(self.call('terminal.step', request)[0], 0)
        code, result = self.call('terminal.step', request)
        self.assertNotEqual(code, 0)
        self.assertEqual(result['errorCode'], 'duplicate-request')
        self.assertEqual(self.call('terminal.step')[1]['data']['counter'], 2)

    def test_respawn_same_pane_is_not_original_shell(self):
        self.assertEqual(self.call('terminal.step')[0], 0)
        subprocess.run(['tmux', '-S', str(self.state / 'tmux.sock'), 'respawn-pane', '-k',
                        '-t', 'tethr-lab:0.0', '/bin/sh'], check=True)
        code, result = self.call('terminal.step')
        self.assertNotEqual(code, 0)
        self.assertEqual(result['errorCode'], 'stale-shell')

    def test_original_pane_id_survives_position_swap(self):
        code, first = self.call('terminal.step')
        self.assertEqual(code, 0, first)
        tmux = ['tmux', '-S', str(self.state / 'tmux.sock')]
        original = json.loads((self.state / 'shell.json').read_text())['identity'][0]
        other = subprocess.run(tmux + ['new-window', '-d', '-P', '-F', '#{pane_id}',
                               '-t', 'tethr-lab', '/bin/sh'], capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(tmux + ['swap-pane', '-s', original, '-t', other], check=True)
        at_old_position = subprocess.run(tmux + ['display-message', '-p', '-t', 'tethr-lab:0.0',
                                                '#{pane_id}'], capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(at_old_position, other)
        code, second = self.call('terminal.step')
        self.assertEqual(code, 0, second)
        self.assertEqual(second['data']['counter'], 2)
        self.assertEqual(second['data']['shellPID'], first['data']['shellPID'])
        self.assertEqual(second['data']['shellNonce'], first['data']['shellNonce'])

    def test_unknown_action_and_invalid_request_have_no_receipt(self):
        self.assertEqual(self.call('missing')[1]['errorCode'], 'unknown-action')
        self.assertEqual(self.call('terminal.step', '../escape')[1]['errorCode'], 'invalid-request')
        self.assertFalse((self.state / 'shell.json').exists())
        self.assertEqual(list((self.state / 'receipts').iterdir()), [])

if __name__ == '__main__':
    unittest.main(verbosity=2)
