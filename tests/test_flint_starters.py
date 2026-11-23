"""Milestone 10 (ADR-028): compile-time conditional registration driven by config/application.toml, starters
and `flint add`."""
import json
import signal
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.request
from pathlib import Path

from test_flint_cli import FLINT, ROOT, codes, environment, flint_json, setUpModule  # noqa: F401

CONDITIONAL_APP = '''module shop.app;

import flint.di : AppContext, AutoConfiguration, ConditionalOnConfig, Service;
import std.stdio : writeln;

@safe:

@ConditionalOnConfig("database") @Service final class Database
{
}

@ConditionalOnConfig("cache") @Service final class Cache
{
}

alias Defaults = AutoConfiguration!(Database, Cache);

int main()
{
    AppContext!(Defaults) context;
    if (context.initialize().code != 0)
        return 1;
    scope (exit)
        context.shutdown();
    writeln("database ", __traits(compiles, context.get!Database()), " cache ", __traits(compiles, context.get!Cache()));
    return 0;
}
'''


class ConditionalConfigTests(unittest.TestCase):
    def test_sections_of_application_toml_switch_beans_at_compile_time(self):
        with tempfile.TemporaryDirectory(prefix='flint-starters-') as temporary:
            status, document = flint_json('new', 'shop', cwd=temporary)
            self.assertEqual(status, 0, document)
            project = Path(temporary) / 'shop'
            manifest = project / 'flint.toml'
            manifest.write_text(manifest.read_text().replace('[dependencies]\n', '[dependencies]\n"flint:di" = {}\n'))
            for stale in (project / 'src' / 'shop').glob('*.d'):
                stale.unlink()
            (project / 'src' / 'shop' / 'app.d').write_text(CONDITIONAL_APP)
            for test in (project / 'test').rglob('*.d'):
                test.unlink()
            (project / 'config' / 'application.toml').write_text('[app]\ngreeting = "Hello"\n\n[database]\nurl = "x"\n')
            self.assertEqual(flint_json('lock', cwd=project)[0], 0)
            result = subprocess.run([str(FLINT), 'run'], cwd=project, capture_output=True, text=True,
                                    env=environment())
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('database true cache false', result.stdout)
            (project / 'config' / 'application.toml').write_text('[cache]\nsize = 1\n')
            result = subprocess.run([str(FLINT), 'run'], cwd=project, capture_output=True, text=True,
                                    env=environment())
            self.assertIn('database false cache true', result.stdout, result.stderr)



def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


class StarterWebTests(unittest.TestCase):
    def test_flint_add_wires_the_dependency_the_configuration_and_the_lock(self):
        with tempfile.TemporaryDirectory(prefix='flint-add-') as temporary:
            self.assertEqual(flint_json('new', 'shop', cwd=temporary)[0], 0)
            project = Path(temporary) / 'shop'
            status, document = flint_json('add', 'web', cwd=project)
            self.assertEqual(status, 0, document)
            self.assertEqual(document['added'], ['flint:starter-web'])
            self.assertEqual(document['sections'], ['server'])
            self.assertIn('"flint:starter-web" = {}', (project / 'flint.toml').read_text())
            self.assertIn('[server]\naddress = "127.0.0.1"', (project / 'config/application.toml').read_text())
            self.assertIn('name = "flint:starter-web"', (project / 'flint.lock').read_text())
            status, document = flint_json('add', 'starter-web', cwd=project)
            self.assertEqual((status, document['added'], document['present']), (0, [], ['flint:starter-web']))
            status, document = flint_json('add', 'webb', cwd=project)
            self.assertEqual((status, codes(document)), (4, ['FLINT-E0009']))

    def test_the_example_serves_an_ordinary_handler_with_configuration(self):
        # Built in place: the example's lock is a workspace lock.
        project = ROOT / 'starters/web/example'
        built = subprocess.run([str(FLINT), 'build', '--json'], cwd=project, capture_output=True, text=True,
                               env=environment())
        self.assertEqual(built.returncode, 0, built.stdout[-3000:])
        port = free_port()
        process = subprocess.Popen([str(project / '.flint/build/dev/shop'), f'--set=server.port={port}'],
                                   cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            body = None
            for _ in range(100):
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/greetings/Ada', timeout=2) as r:
                        body = json.loads(r.read())
                        break
                except OSError:
                    time.sleep(0.05)
            self.assertEqual(body, {'text': 'Hello, Ada!'})
        finally:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        misspelt = subprocess.run([str(project / '.flint/build/dev/shop'), '--set=server.prot=1'], cwd=project,
                                  capture_output=True, text=True, timeout=10)
        self.assertEqual(misspelt.returncode, 3, misspelt.stderr)
        self.assertIn('server.prot', misspelt.stderr)


if __name__ == '__main__':
    unittest.main()
