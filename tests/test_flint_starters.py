"""Milestone 10 (ADR-028): compile-time conditional registration driven by config/application.toml, starters
and `flint add`."""
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import FLINT, environment, flint_json, setUpModule  # noqa: F401

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


if __name__ == '__main__':
    unittest.main()
