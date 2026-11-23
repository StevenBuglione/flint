"""flint watch, flint run --debug and flint generate debug (Milestone 9, ADR-027)."""
import json
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from test_flint_cli import DMD_BIN, FLINT, ROOT, codes, environment, flint_json, setUpModule  # noqa: F401


def wait_for(predicate, timeout=60):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    return None


class WatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-watch-')
        status, document = flint_json('new', 'w', cwd=cls.temporary.name)
        assert status == 0, document
        cls.project = Path(cls.temporary.name) / 'w'

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_watch_rebuilds_restarts_and_survives_errors(self):
        greeting = self.project / 'src/w/greeting.d'
        original = greeting.read_text()
        process = subprocess.Popen([str(FLINT), 'watch', '--json'], cwd=self.project, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, env=environment())
        events = []

        def next_event():
            line = process.stdout.readline()
            if line:
                events.append(json.loads(line))
            return line
        try:
            self.assertTrue(wait_for(next_event))
            self.assertEqual((events[0]['cycle'], events[0]['action'], events[0]['ok']), (1, 'build', True))
            self.assertTrue(events[0]['restarted'])
            greeting.write_text(original.replace('"world"', '"planet"'))
            self.assertTrue(wait_for(next_event))
            self.assertEqual(events[1]['changed'], ['src/w/greeting.d'])
            self.assertTrue(events[1]['ok'])
            greeting.write_text(original + '\nint broken(\n')
            self.assertTrue(wait_for(next_event))
            self.assertFalse(events[2]['ok'])
            self.assertFalse(events[2]['restarted'])
            greeting.write_text(original)
            self.assertTrue(wait_for(next_event))
            self.assertTrue(events[3]['ok'])
        finally:
            process.send_signal(signal.SIGINT)
            self.assertEqual(process.wait(timeout=30), 0)
            process.stdout.close()
            process.stderr.close()
            greeting.write_text(original)
        self.assertEqual([e['cycle'] for e in events], [1, 2, 3, 4])

    def test_libraries_are_retested(self):
        with tempfile.TemporaryDirectory() as directory:
            flint_json('new', 'lib', '--type', 'library', cwd=directory)
            process = subprocess.Popen([str(FLINT), 'watch', '--json'], cwd=Path(directory) / 'lib',
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment())
            try:
                event = json.loads(wait_for(process.stdout.readline))
                self.assertEqual((event['action'], event['ok'], event['restarted']), ('test', True, False))
            finally:
                process.send_signal(signal.SIGINT)
                process.wait(timeout=30)
                process.stdout.close()
                process.stderr.close()


@unittest.skipUnless(shutil.which('gdb'), 'gdb is not installed')
class DebugTests(unittest.TestCase):
    def test_generated_launch_configurations_source_the_printers(self):
        with tempfile.TemporaryDirectory() as directory:
            flint_json('new', 'd', cwd=directory)
            project = Path(directory) / 'd'
            status, document = flint_json('generate', 'debug', cwd=project)
            self.assertEqual(status, 0, document['diagnostics'])
            launch = json.loads((project / '.vscode/launch.json').read_text())
            gdb = launch['configurations'][0]
            self.assertEqual(gdb['program'], '${workspaceFolder}/.flint/build/dev/d')
            self.assertIn('source ' + str(ROOT / 'tools/debug/flint_gdb.py'), gdb['setupCommands'][1]['text'])
            tasks = json.loads((project / '.vscode/tasks.json').read_text())
            self.assertEqual(tasks['tasks'][0]['command'], 'flint build')

    def test_the_gdb_printers_show_flint_values(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'probe.d'
            source.write_text('''import flint.arena : Error, RequestArena, Result, Status, Text;

void inspect(ref Result!int good, ref Result!int bad, ref Error error, ref RequestArena arena, ref Text text)
{
    pragma(inline, false);
}

void main()
{
    auto good = Result!int(42);
    auto bad = Result!int(0, Error(Status.notFound, "no such user"));
    auto error = Error(Status.conflict, "duplicate key", 7);
    ubyte[256] memory;
    auto arena = RequestArena(memory[]);
    auto text = Text(arena.copyIn(cast(const(ubyte)[]) "hello").value);
    inspect(good, bad, error, arena, text);
}
''')
            dmd = DMD_BIN / 'dmd' if (DMD_BIN / 'dmd').is_file() else DMD_BIN / 'ldmd2'
            subprocess.run([str(dmd), '-g', '-i', '-preview=dip1000', '-I' + str(ROOT / 'packages/arena/source'),
                            str(source), '-of=' + str(Path(directory) / 'probe')], check=True, cwd=directory)
            result = subprocess.run(['gdb', '-q', '-batch', '-ex', 'set debuginfod enabled off', '-x',
                                     str(ROOT / 'tools/debug/flint_gdb.py'), '-ex', 'break probe.inspect', '-ex', 'run',
                                     '-ex', 'print good', '-ex', 'print bad', '-ex', 'print error', '-ex', 'print arena',
                                     '-ex', 'print text', str(Path(directory) / 'probe')],
                                    capture_output=True, text=True, timeout=120)
            printed = [line.split('= ', 1)[1] for line in result.stdout.splitlines() if line.startswith('$')]
            self.assertEqual(printed[0], 'ok: 42')
            self.assertEqual(printed[1], "error: notFound 'no such user'")
            self.assertTrue(printed[2].endswith("conflict 'duplicate key' at byte 7"))
            self.assertIn('RequestArena(5 of 256 bytes used', printed[3])
            self.assertIn('Text(5 bytes at 0', printed[4])

    def test_run_debug_starts_gdb_with_the_printers(self):
        with tempfile.TemporaryDirectory() as directory:
            flint_json('new', 'r', cwd=directory)
            project = Path(directory) / 'r'
            result = subprocess.run([str(FLINT), 'run', '--debug', '--', '--name', 'gdb'], cwd=project,
                                    input='set debuginfod enabled off\nrun\nquit\n', capture_output=True, text=True,
                                    timeout=180, env=environment())
            self.assertIn('Hello, gdb!', result.stdout)
            status, document = flint_json('run', '--debug', cwd=project)
            self.assertEqual(codes(document), ['FLINT-E0004'])


if __name__ == '__main__':
    unittest.main()
