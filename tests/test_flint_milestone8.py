"""Milestone 8's definition of done, end to end (ADR-023): a new project with a git-fixture Flint library dependency,
a [native] package and embedded C builds, tests and packages (a runnable scratch image and SBOMs) through flint
alone, and the native engine is visible nowhere."""
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, environment, flint, flint_json, setUpModule  # noqa: F401
from test_flint_deps import publish
from test_flint_native import CONAN, CRC_C, CRC_H, FFI, LOCK
from test_flint_package import MUSL, docker_available

CHECKSUM = ('\n/// Hex of a CRC.\nstring hex(uint value) pure\n{\n    import std.format : format;\n\n'
            '    return format("%08x", value);\n}\n')
APP_TEST = '''module done.app_test;

import checksum : hex;
import done.ffi.crc : crc32, zlibRelease;

@safe:

@("the fixture library, zlib and the embedded C work together")
unittest
{
    assert(hex(crc32(cast(const(ubyte)[]) "123456789")) == "cbf43926");
    assert(zlibRelease() == "{version}");
}
'''


@unittest.skipUnless(CONAN.is_file() and MUSL, 'needs flint toolchain install --musl')
class MilestoneEightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-m8-')
        base = Path(cls.temporary.name)
        proxy = base / 'proxy'
        publish(proxy, 'checksum', '1.0.0', body=CHECKSUM)
        cls.env = environment(FLINT_PROXY='file://' + str(proxy), FLINT_CACHE=str(base / 'cache'),
                              SOURCE_DATE_EPOCH='1700000000')
        cls.outputs = []
        status, document = cls.call(cls, 'new', 'done', cwd=base)
        assert status == 0, document
        cls.project = base / 'done'
        manifest = cls.project / 'flint.toml'
        manifest.write_text(manifest.read_text(encoding='utf-8').replace('version = "0.1.0"\n', 'version = "0.1.0"\nlicense = "MIT"\n')
                            .replace('[dependencies]\n', '[dependencies]\n"example.test/acme/checksum" = "1.0.0"\n')
                            + '\n[native]\nzlib = "1.4"\n', encoding='utf-8')
        (cls.project / 'native').mkdir()
        (cls.project / 'native' / 'crc.c').write_text(CRC_C, encoding='utf-8')
        (cls.project / 'native' / 'crc.h').write_text(CRC_H, encoding='utf-8')
        (cls.project / 'src' / 'done' / 'ffi').mkdir()
        (cls.project / 'src' / 'done' / 'ffi' / 'crc.d').write_text(FFI.replace('module demo.ffi.crc', 'module done.ffi.crc'), encoding='utf-8')
        (cls.project / 'test' / 'done' / 'app_test.d').write_text(APP_TEST.replace('{version}', LOCK['zlib']['version']), encoding='utf-8')
        app = cls.project / 'src' / 'done' / 'app.d'
        app.write_text(app.read_text(encoding='utf-8').replace('import done.greeting : greet;\n',
                                               'import checksum : hex;\nimport done.ffi.crc : crc32;\nimport done.greeting : greet;\n')
                       .replace('    writeln(greet(settings.value.greeting, parsed.options.name));\n',
                                '    writeln(greet(settings.value.greeting, parsed.options.name), " crc32=",\n'
                                '            hex(crc32(cast(const(ubyte)[]) "123456789")));\n'), encoding='utf-8')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def call(self, *arguments, cwd=None):
        result = flint(*arguments, '--json', cwd=cwd or self.project, env=self.env)
        self.outputs.append(result.stdout + result.stderr)
        document = json.loads(result.stdout)
        return result.returncode, document

    def test_1_builds_tests_and_packages_through_flint_alone(self):
        status, document = self.call('lock')
        self.assertEqual(status, 0, document['diagnostics'])
        status, document = self.call('build')
        self.assertEqual(status, 0, document['diagnostics'])
        status, document = self.call('test', '--compiler', 'both')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(len(document['runs']), 2)
        status, document = self.call('check')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertIn('clang-tidy', document['checks'])
        lock = (self.project / 'flint.lock').read_text(encoding='utf-8')
        self.assertIn('name = "example.test/acme/checksum"\nkind = "remote"', lock)
        self.assertIn('[[native]]\nname = "zlib"', lock)

        status, document = self.call('package', '--container', '--sbom')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertTrue(document['fully_static'])
        files = {o['kind']: self.project / o['path'] for o in document['outputs']}
        spdx = json.loads(files['spdx'].read_text(encoding='utf-8'))
        names = {p['name']: p for p in spdx['packages']}
        for name in ('done', 'example.test/acme/checksum', 'zlib', 'native/crc.c', 'musl', 'druntime'):
            self.assertIn(name, names)
        self.assertEqual(names['zlib']['licenseDeclared'], 'Zlib')
        self.assertEqual(names['zlib']['checksums'][0]['checksumValue'], LOCK['zlib']['archive_sha256'])
        cdx = json.loads(files['cyclonedx'].read_text(encoding='utf-8'))
        self.assertIn('zlib', {c['name'] for c in cdx['components']})
        with tempfile.TemporaryDirectory() as directory, tarfile.open(files['archive']) as tar:
            tar.extractall(directory, filter='data')
            top = Path(directory) / 'done-0.1.0'
            ran = subprocess.run([str(top / 'bin' / 'done'), '--name', 'm8'], cwd=top, capture_output=True, text=True, encoding='utf-8')
            self.assertIn('Hello, m8! crc32=cbf43926', ran.stdout, ran.stderr)
        if docker_available():
            loaded = subprocess.run(['docker', 'load', '-i', str(files['image'])], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(loaded.returncode, 0, loaded.stderr)
            try:
                ran = subprocess.run(['docker', 'run', '--rm', 'done:0.1.0', '--name', 'scratch'], capture_output=True,
                                     text=True, encoding='utf-8', timeout=120)
                self.assertIn('Hello, scratch! crc32=cbf43926', ran.stdout, ran.stderr)
            finally:
                subprocess.run(['docker', 'image', 'rm', '-f', 'done:0.1.0'], capture_output=True)

        status, document = self.call('deps', 'audit')
        self.assertEqual(status, 0, document['diagnostics'])
        # The native engine never shows: not in any output, nor as files in the project.
        for output in self.outputs:
            self.assertNotIn('conan', output.lower())
        visible = [p for p in self.project.rglob('*') if 'conan' in p.name.lower()]
        self.assertEqual(visible, [])


if __name__ == '__main__':
    unittest.main()
