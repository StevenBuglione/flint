"""Unit tests of the measurement queue's quiet-window rules: `python3 tools/test_measure_queue.py`."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import measure_queue


class QuietWindow(unittest.TestCase):
    def test_reserved_and_busy_ports_are_refused(self):
        self.assertTrue(measure_queue.check_ports([8081]))
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            port = listener.getsockname()[1]
            self.assertEqual(measure_queue.check_ports([port]), [f'port {port} is in use'])
        self.assertEqual(measure_queue.check_ports([port]), [])

    def test_own_children_are_not_foreign_load(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(5)'])
        try:
            time.sleep(.2)
            self.assertIn(child.pid, measure_queue.own_tree())
        finally:
            child.kill()
            child.wait()

    def test_load_and_build_processes_make_the_window_busy(self):
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(0.4, 0.5, 0.6)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=[]):
            self.assertTrue(measure_queue.quiet_snapshot()['quiet'])
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(1.6, 0.5, 0.6)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=[]):
            self.assertFalse(measure_queue.quiet_snapshot()['quiet'])
            self.assertTrue(measure_queue.quiet_snapshot(own_load_ok=True)['quiet'])
        build = [{'pid': 1, 'command': 'ldc2', 'cwd': '/elsewhere'}]
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(0.1, 0.1, 0.1)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=build):
            self.assertFalse(measure_queue.quiet_snapshot()['quiet'])

    def test_sleeping_build_processes_are_idle(self):
        sleeper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(5)'])
        try:
            rows = [{'pid': sleeper.pid, 'command': 'dmd', 'cwd': '/elsewhere',
                     'ticks': measure_queue.cpu_ticks(sleeper.pid)}]
            with mock.patch.object(measure_queue, 'build_processes', return_value=rows):
                self.assertEqual(measure_queue.busy_processes(.3), [])
                self.assertEqual(measure_queue.busy_processes.idle, 1)
        finally:
            sleeper.kill()
            sleeper.wait()

    def test_processes_in_the_runs_own_checkout_are_not_foreign(self):
        import tempfile
        with tempfile.TemporaryDirectory() as own:
            worker = subprocess.Popen(['sleep', '5'], cwd=own, start_new_session=True)
            try:
                with mock.patch.object(measure_queue, 'BUSY_COMMANDS', {'sleep'}), \
                        mock.patch.object(measure_queue, 'own_tree', return_value=set()):
                    self.assertIn(worker.pid, [row['pid'] for row in measure_queue.build_processes()])
                    measure_queue.OWN_DIRECTORIES[:] = [own]
                    self.assertNotIn(worker.pid, [row['pid'] for row in measure_queue.build_processes()])
            finally:
                measure_queue.OWN_DIRECTORIES[:] = []
                worker.kill()
                worker.wait()

    def test_hold_pauses_while_the_lock_exists(self):
        import tempfile, threading
        with tempfile.TemporaryDirectory() as directory:
            lock, out = Path(directory) / 'MEASURING', Path(directory) / 'ticks'
            lock.write_text('{}')
            script = f'import time\nfor i in range(30):\n    open({str(out)!r}, "a").write("x")\n    time.sleep(0.1)\n'
            threading.Timer(2.5, lock.unlink).start()
            with mock.patch.object(measure_queue, 'LOCK', lock):
                started = time.monotonic()
                code = measure_queue.hold([sys.executable, '-c', script])
            self.assertEqual(code, 0)
            self.assertGreater(time.monotonic() - started, 4.5)  # 3 s of work plus the ~2 s it was held
            self.assertEqual(len(out.read_text()), 30)

    def test_a_claimed_window_needs_three_quiet_samples(self):
        quiet = {'quiet': True, 'problems': []}
        busy = {'quiet': False, 'problems': ['ldc2']}
        samples = iter([busy, quiet, quiet, busy, quiet, quiet, quiet])
        with mock.patch.object(measure_queue, 'quiet_snapshot', side_effect=lambda **_: next(samples)), \
                mock.patch.object(measure_queue.time, 'sleep'):
            self.assertTrue(measure_queue.claim_window(600)['quiet'])
        with mock.patch.object(measure_queue, 'quiet_snapshot', return_value=busy), \
                mock.patch.object(measure_queue.time, 'sleep'), \
                mock.patch.object(measure_queue.time, 'monotonic', side_effect=[0, 0, 100]):
            self.assertFalse(measure_queue.claim_window(90)['quiet'])

    def test_only_short_entries_claim_by_default(self):
        mode = measure_queue.window_mode
        self.assertEqual(mode({'id': 'a', 'estimate_minutes': 30}), 'claim')
        self.assertEqual(mode({'id': 'a', 'estimate_minutes': 31}), 'natural')
        self.assertEqual(mode({'id': 'a'}), 'natural')
        self.assertEqual(mode({'id': 'a', 'estimate_minutes': 45, 'window': 'claim'}), 'claim')
        with self.assertRaises(SystemExit):
            mode({'id': 'a', 'window': 'soon'})
        rows = [{'id': 'long', 'created': '1', 'estimate_minutes': 1},
                {'id': 'first', 'created': '2', 'estimate_minutes': 20, 'priority': 1}]
        self.assertEqual([r['id'] for r in sorted(rows, key=measure_queue.queue_order)], ['first', 'long'])

    def test_a_natural_run_gives_way_without_taking_the_lock(self):
        seen = {}

        def measure(entry, built, outdir, smoke):
            seen['lock'], seen['natural'] = measure_queue.LOCK.exists(), measure_queue.NATURAL.exists()
            started = time.monotonic()
            completed = subprocess.run(['sleep', '30'])
            seen['seconds'] = time.monotonic() - started
            raise SystemExit(f'step 0 exited with {completed.returncode}')

        def snapshot(own_load_ok=False, instant=False):
            busy = [{'pid': 1, 'command': 'dmd', 'cwd': '/elsewhere'}] if own_load_ok else []
            return {'time': 't', 'load_average': [0, 0, 0], 'busy_processes': busy, 'quiet': True, 'problems': []}

        entry = {'id': 'long-one', 'estimate_minutes': 80, 'measure': {'kind': 'fake'}}
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            with mock.patch.object(measure_queue, 'WORK', work), \
                    mock.patch.object(measure_queue, 'LOCK', work / 'MEASURING'), \
                    mock.patch.object(measure_queue, 'NATURAL', work / 'MEASURING-NATURAL'), \
                    mock.patch.object(measure_queue, 'ROOT', work), \
                    mock.patch.object(measure_queue, 'prepare', return_value={}), \
                    mock.patch.object(measure_queue, 'held_work', return_value=[]), \
                    mock.patch.object(measure_queue, 'quiet_snapshot', side_effect=snapshot), \
                    mock.patch.object(measure_queue.WindowSampler, 'INTERVAL', 0.2), \
                    mock.patch.dict(measure_queue.KINDS, {'fake': measure}):
                with self.assertRaisesRegex(SystemExit, 'gave way'):
                    measure_queue.run(entry)
                self.assertFalse((work / 'MEASURING-NATURAL').exists())
                attempts = (work / 'results' / 'long-one' / 'attempts.jsonl').read_text().splitlines()
        self.assertEqual(seen['lock'], False)
        self.assertEqual(seen['natural'], True)
        self.assertLess(seen['seconds'], 15)
        self.assertIn('interrupted', json.loads(attempts[-1])['outcome'])

    def test_entries_are_well_formed(self):
        for entry in measure_queue.entries():
            self.assertIn(entry['status'], ('pending', 'blocked', 'done'))
            self.assertIn(measure_queue.window_mode(entry), ('claim', 'natural'))
            self.assertIn(entry['measure']['kind'], measure_queue.KINDS)
            self.assertFalse(measure_queue.check_ports(p for p in entry['measure'].get('ports', [])
                                                       if p in measure_queue.RESERVED_PORTS))
            json.dumps(entry)



class Pins(unittest.TestCase):
    @staticmethod
    def entry(steps, builds=None, **extra):
        return dict({'id': 'x', 'builds': builds if builds is not None else
                     {'tree': {'app': 'checkout', 'commit': 'abc', 'fork': True}},
                     'measure': {'kind': 'command', 'steps': steps}}, **extra)

    def test_unpinned_builds_and_steps_are_refused(self):
        measure_queue.check_pins(self.entry([{'argv': ['tools/x.py'], 'in': 'tree'}]))
        with self.assertRaisesRegex(SystemExit, 'build tree has no commit'):
            measure_queue.check_pins(self.entry([{'argv': [], 'in': 'tree'}], {'tree': {'commit': 'TBD'}}))
        with self.assertRaisesRegex(SystemExit, 'needs the pinned harness'):
            measure_queue.check_pins(self.entry([{'argv': ['{harness}/tools/x.py'], 'in': 'tree'}]))
        with self.assertRaisesRegex(SystemExit, 'needs the pinned harness'):
            measure_queue.check_pins(self.entry([{'argv': ['tools/x.py']}]))
        with self.assertRaisesRegex(SystemExit, "'other', which is not a build"):
            measure_queue.check_pins(self.entry([{'argv': [], 'in': 'other'}]))
        measure_queue.check_pins(self.entry([{'argv': ['{harness}/tools/x.py']}], harness='abc'))
        with self.assertRaisesRegex(SystemExit, 'one commit is required'):
            measure_queue.check_pins(dict(self.entry([{'argv': ['{harness}/tools/x.py'], 'in': 'tree'}], harness='def'),
                                          id='phase1-http-gs-rest'))
        measure_queue.check_pins(dict(self.entry([{'argv': ['{harness}/tools/x.py'], 'in': 'tree'}], harness='abc'),
                                      id='phase1-http-gs-rest'))

    def test_queued_entries_pin_or_wait(self):
        # Every entry that may run (pending) pins its builds, its steps' trees and any {harness} revision.
        for entry in measure_queue.entries():
            if entry['status'] == 'pending':
                measure_queue.check_pins(entry)

    def test_baseline_entries_share_one_private_fork_tree(self):
        # Resume plan 1.5: the baseline's parts all build in the same tree flavour (flint, mold, the fork build).
        ids = ['phase1-builds-petclinic', 'phase1-http-gs-rest', 'phase1-http-petclinic', 'error-404-p99',
               'error-validation-p99', 'phase1-builds-gs-relational', 'phase1-builds-gs-rest',
               ] + [f'phase1-gc-matrix-{n}' for n in ('1', '2', '3', 'gs-rest-1', 'gs-rest-2', 'gs-rest-3')]
        # fast-path-pools-ab is an A/B inside one commit, never assembled: it moved to main with the RSS census.
        # One tree flavour and one commit for every part (B: the fork build; B2: a private copy of shared v4.1).
        commits, flavours = set(), set()
        for name in ids:
            entry = measure_queue.load_entry(name)
            tree = entry['builds']['tree']
            self.assertEqual((tree['flint'], tree['linker']), (True, 'mold'), name)
            self.assertTrue(all(step.get('in') == 'tree' for step in entry['measure']['steps']), name)
            commits.add(tree['commit'])
            flavours.add(bool(tree.get('fork')))
        self.assertEqual(len(commits), 1)
        self.assertEqual(len(flavours), 1)


class Provenance(unittest.TestCase):
    def test_measured_binaries_and_artifacts(self):
        record = {'apps': {'a': {'trials': [{'server_binary_sha256': 'f1'}, {'server_binary_sha256': 'f2'}]}},
                  'other': [{'server_binary_sha256': 'f1'}], 'trials': [{'identity': {'executable': 'x', 'sha256': 'f3'}}]}
        self.assertEqual(measure_queue.measured_binaries(record), {'f1', 'f2', 'f3'})
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'benchmarks/spring/flint/app/.flint/build/release/app'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'\x7fELF...gcopt=gc:conservative parallel:1\x00rest')
            binary.chmod(0o755)
            (binary.parent / 'app.o').write_bytes(b'')
            found = measure_queue.built_artifacts(root, time.time() - 60)
            row = found['benchmarks/spring/flint/app/.flint/build/release/app']
            self.assertEqual(row['profile'], 'release')
            self.assertEqual(row['embedded_gcopt'], ['gcopt=gc:conservative parallel:1'])
            self.assertEqual(len(found), 1)
            self.assertEqual(measure_queue.built_artifacts(root, time.time() + 60), {})

    def test_step_provenance_records_gc_options_and_aot_lines(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary)
            log = out / 'step-0.log'
            log.write_text('Generated 3 Flint AOT modules for a (1 extracted in 9 ms, 2 from the shared cache, 3 written, 12 ms)\n'
                           'Generated 3 Flint AOT modules for a (1 extracted in 7 ms, 2 from the shared cache, 3 written, 10 ms)\n')
            row = measure_queue.step_provenance(['x', '--gcopt', 'p1=gc:conservative parallel:1'], out,
                                                {'DRT_GCOPT': 'parallel:1', 'PATH': '/bin'}, log, out, time.time() - 5)
            self.assertEqual(row['gc_options']['argv'], ['p1=gc:conservative parallel:1'])
            self.assertEqual(row['gc_options']['DRT_GCOPT'], 'parallel:1')
            self.assertEqual(row['aot_summaries']['count'], 2)
            self.assertEqual(len(row['aot_summaries']['distinct']), 1)


class ServedCompiles(unittest.TestCase):
    def test_trace_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            trace = Path(temporary) / 'trace.log'
            self.assertEqual(measure_queue.server_trace(trace), {'compiled': 0, 'refused': 0})
            trace.write_text('1.000001 42 accepted\n1.000002 43 received\n1.000100 43 compiled\n'
                             '1.000200 44 refused\n1.000300 45 compiled\n1.000301 45 reported\n')
            self.assertEqual(measure_queue.server_trace(trace), {'compiled': 2, 'refused': 1})

    def test_priming_refusals_do_not_count(self):
        import os
        with tempfile.TemporaryDirectory() as temporary:
            logs = Path(temporary) / 'builds-logs'
            logs.mkdir()
            prime = logs / 'app-flint-prime-cached.log'
            prime.write_text('primed')
            mono_now = time.monotonic()
            os.utime(prime, (time.time() - 10, time.time() - 10))  # priming ended 10 s ago
            trace = Path(temporary) / 'trace.log'
            trace.write_text(f'{mono_now - 20:.6f} 1 refused\n{mono_now - 15:.6f} 2 compiled\n'
                             f'{mono_now - 5:.6f} 3 compiled\n{mono_now - 4:.6f} 4 compiled\n')
            self.assertEqual(measure_queue.scored_server_trace(trace, logs),
                             {'compiled': 2, 'refused': 0, 'after_priming': True, 'refused_in': {}})
            trial = logs / 'app-flint-cached-cold-0.log'
            trial.write_text('built')
            trace.write_text(trace.read_text() + f'{mono_now - 3:.6f} 5 refused\n')
            out = measure_queue.scored_server_trace(trace, logs)
            self.assertEqual((out['refused'], out['refused_in']), (1, {'app-flint-cached-cold-0.log': 1}))

    def test_only_this_trees_servers_stop(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.assertEqual(measure_queue.stop_tree_compile_servers(temporary), [])


class StrayProcesses(unittest.TestCase):
    def test_tracers_and_session_servers_are_foreign(self):
        self.assertEqual(measure_queue.stray_kind(os.getpid(), 'strace'), 'diagnostic')
        self.assertEqual(measure_queue.stray_kind(os.getpid(), 'callgrind-amd64-'), 'diagnostic')
        self.assertIsNone(measure_queue.stray_kind(os.getpid(), 'python3'))
        with tempfile.TemporaryDirectory() as temporary:
            exe = Path(temporary) / 'build' / 'spring' / 'server'
            exe.parent.mkdir(parents=True)
            exe.write_text('#!/bin/sh\nsleep 30\n')
            exe.chmod(0o755)
            child = subprocess.Popen([str(exe)])
            try:
                time.sleep(0.2)
                # A shell script's exe is the shell; the check reads the executable, so a script is not a server.
                self.assertIsNone(measure_queue.stray_kind(child.pid, 'server'))
            finally:
                child.kill()
                child.wait()


class DriftFallback(unittest.TestCase):
    def test_a_drifted_flint_only_step_switches_to_interleaved(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary) / 'http.json'
            out.write_text(json.dumps({'status': 'failed', 'error': 'runner drift against the baseline (not evidence)'}))
            entry = {'id': 'x', 'measure': {'steps': [{'argv': ['load_bench.py', '--baseline', 'rec', '--output', 'o']}]}}
            with mock.patch.object(measure_queue, 'save_entry') as saved:
                self.assertTrue(measure_queue.drift_fallback(entry, 0, [out]))
                saved.assert_called_once()
            self.assertEqual(entry['measure']['steps'][0]['argv'], ['load_bench.py', '--output', 'o'])
            self.assertEqual(entry['drift_fallback']['record'], 'rec')
            out.write_text(json.dumps({'status': 'failed', 'error': 'server exited'}))
            entry = {'id': 'y', 'measure': {'steps': [{'argv': ['load_bench.py', '--baseline', 'rec']}]}}
            with mock.patch.object(measure_queue, 'save_entry') as saved:
                self.assertFalse(measure_queue.drift_fallback(entry, 0, [out]))
                saved.assert_not_called()


class NativeExtractorProbe(unittest.TestCase):
    def fake(self, directory, answer):
        dmd = Path(directory) / 'dmd'
        dmd.write_text(f'#!/bin/sh\necho "{answer}" >&2\nexit 1\n')
        dmd.chmod(0o755)
        return dmd

    def test_the_switch_is_probed(self):
        with tempfile.TemporaryDirectory() as temporary:
            self.assertTrue(measure_queue.native_extractor(self.fake(temporary, 'Error: cannot read the Flint AOT request `x`')))
            self.assertFalse(measure_queue.native_extractor(self.fake(temporary, "Error: unrecognized switch '-flint-aot-extract=x'")))
            self.assertIsNone(measure_queue.native_extractor(self.fake(temporary, 'something else')))
            self.assertIsNone(measure_queue.native_extractor(Path(temporary) / 'absent'))


if __name__ == '__main__':
    unittest.main()
