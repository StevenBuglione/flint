"""[native] packages through Flint's native resolver (Milestone 8, ADR-023): the hidden Conan, the recipe index,
the lock, conflicts, system = true and bundled linkage. Builds zlib from its pinned source on first use."""
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, codes, environment, flint, flint_json, setUpModule  # noqa: F401
from test_flint_native_c import CLANG

CONAN = ROOT / '.tools' / 'conan-2.34.0' / 'bin' / 'conan'
LOCK = {row['name']: row for row in json.loads((ROOT / 'policy/native-lock.json').read_text())['libraries']}

CRC_C = '''#include "crc.h"

#include <zlib.h>

uint32_t demo_zcrc(const uint8_t *data, size_t length)
{
    return (uint32_t)crc32(0L, data, (uInt)length);
}
'''
CRC_H = '''#ifndef DEMO_CRC_H
#define DEMO_CRC_H
#include <stddef.h>
#include <stdint.h>

uint32_t demo_zcrc(const uint8_t *data, size_t length);

#endif
'''
FFI = '''/// zlib's CRC-32 through embedded C, behind a safe D API.
module demo.ffi.crc;

@safe:

private extern (C) uint demo_zcrc(scope const(ubyte)* data, size_t length) @system nothrow @nogc;
private extern (C) const(char)* zlibVersion() @system nothrow @nogc;

// SAFETY: demo_zcrc reads exactly data.length bytes from data.ptr and keeps no pointer.
/// CRC-32 of `data`, computed by zlib.
uint crc32(scope const(ubyte)[] data) @trusted nothrow @nogc
{
    return demo_zcrc(data.ptr, data.length);
}

// SAFETY: zlibVersion returns a pointer to a static NUL-terminated string that lives as long as the program.
/// The linked zlib's version.
@trusted string zlibRelease()
{
    import std.string : fromStringz;

    return zlibVersion().fromStringz.idup;
}
'''
TEST = '''module demo.crc_test;

import demo.ffi.crc : crc32, zlibRelease;

@safe:

@("zlib computes the IEEE CRC-32 and is the pinned release")
unittest
{
    assert(crc32(cast(const(ubyte)[]) "123456789") == 0xCBF43926);
    assert(zlibRelease() == "{version}");
}
'''


@unittest.skipUnless(CONAN.is_file() and CLANG.is_file(), 'flint toolchain install has not installed the native engine')
class NativePackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-native-')
        base = Path(cls.temporary.name)
        cls.base = base
        cls.env = environment(SOURCE_DATE_EPOCH='1700000000')
        status, document = flint_json('new', 'demo', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'demo'
        cls.manifest = cls.project / 'flint.toml'
        cls.original = cls.manifest.read_text()
        (cls.project / 'native').mkdir()
        (cls.project / 'native' / 'crc.c').write_text(CRC_C)
        (cls.project / 'native' / 'crc.h').write_text(CRC_H)
        (cls.project / 'src' / 'demo' / 'ffi').mkdir()
        (cls.project / 'src' / 'demo' / 'ffi' / 'crc.d').write_text(FFI)
        (cls.project / 'test' / 'demo' / 'crc_test.d').write_text(TEST.replace('{version}', LOCK['zlib']['version']))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def use(self, native):
        self.manifest.write_text(self.original + '\n[native]\n' + native)
        (self.project / 'flint.lock').unlink(missing_ok=True)

    def run_flint(self, *arguments):
        return flint_json(*arguments, cwd=self.project, env=self.env)

    def test_1_a_native_package_builds_tests_and_locks(self):
        self.use('zlib = "1.4"\n')
        status, document = self.run_flint('test', '--compiler', 'both')
        self.assertEqual(status, 0, document['diagnostics'])
        lock = (self.project / 'flint.lock').read_text()
        self.assertIn('[[native]]\nname = "zlib"\nversion = "1.4"\nlinkage = "static"\ntarget = "linux-x86_64-glibc"\n', lock)
        self.assertIn('source_sha256 = "' + LOCK['zlib']['archive_sha256'] + '"', lock)
        for key in ('recipe_revision', 'package_id', 'binary_sha256'):
            self.assertRegex(lock, key + ' = "[0-9a-f]{32,64}"')
        receipt = json.loads((self.project / '.flint/build/test/demo-test.receipt.json').read_text())
        self.assertEqual(receipt['native_packages'][0]['name'], 'zlib')
        self.assertTrue(receipt['portable'])

    def test_2_the_engine_never_shows_through(self):
        self.use('zlib = "1.4"\n')
        result = flint('build', '--verbose', cwd=self.project, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('conan', (result.stdout + result.stderr).lower())
        self.assertIn('Native zlib 1.4 for linux-x86_64-glibc', result.stderr)
        self.assertFalse(list(self.project.glob('conan*')))

    def test_3_unknown_versions_and_conflicts_are_flint_errors(self):
        self.use('zlib = "1.2.13"\n')
        status, document = self.run_flint('lock')
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0318']))
        self.assertIn('the index has zlib/1.4', document['diagnostics'][0]['fix'])
        library = self.base / 'zipper'
        if not library.exists():
            flint_json('new', 'zipper', '--type', 'library', cwd=self.base, env=self.env)
            (library / 'flint.toml').write_text((library / 'flint.toml').read_text() + '\n[native]\nzlib = "1.3.1"\n')
        self.manifest.write_text(self.original.replace('[dependencies]\n', '[dependencies]\nzipper = { path = "../zipper" }\n')
                                 + '\n[native]\nzlib = "1.4"\n')
        status, document = self.run_flint('lock')
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0320']))
        message = document['diagnostics'][0]['message']
        self.assertIn('the project needs 1.4', message)
        self.assertIn('zipper needs 1.3.1', message)

    def test_4_a_changed_binary_fails_the_lock(self):
        self.use('zlib = "1.4"\n')
        self.assertEqual(self.run_flint('lock')[0], 0)
        lock = (self.project / 'flint.lock').read_text()
        tampered = lock.replace('binary_sha256 = "', 'binary_sha256 = "0', 1)
        (self.project / 'flint.lock').write_text(tampered)
        status, document = self.run_flint('build', '--locked')
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0202']))
        self.assertIn('changed native zlib', document['diagnostics'][0]['message'])

    def test_5_bundled_ships_a_shared_library_with_a_run_path(self):
        self.use('zlib = { version = "1.4", linkage = "bundled" }\n')
        status, document = self.run_flint('package')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertIn('libzlib-flint.so', document['needed'])
        archive = next(self.project / o['path'] for o in document['outputs'] if o['kind'] == 'archive')
        with tempfile.TemporaryDirectory() as directory, tarfile.open(archive) as tar:
            tar.extractall(directory, filter='data')
            top = Path(directory) / 'demo-0.1.0'
            self.assertTrue((top / 'lib' / 'libzlib-flint.so').is_file())
            dynamic = subprocess.run(['readelf', '-dW', str(top / 'bin' / 'demo')], capture_output=True, text=True).stdout
            self.assertIn('$ORIGIN/../lib', dynamic)
            ran = subprocess.run([str(top / 'bin' / 'demo'), '--name', 'bundled'], cwd=top, capture_output=True, text=True)
            self.assertEqual(ran.returncode, 0, ran.stderr)

    @unittest.skipUnless(subprocess.run(['pkg-config', '--exists', 'zlib']).returncode == 0, 'host has no zlib.pc')
    def test_6_system_true_uses_the_host_library_and_is_not_portable(self):
        self.use('zlib = { version = "1.2", system = true }\n')
        result = flint('build', cwd=self.project, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Non-portable', result.stderr)
        receipt = json.loads((self.project / '.flint/build/dev/demo.receipt.json').read_text())
        self.assertFalse(receipt['portable'])
        self.assertIn("uses the host's zlib", receipt['non_portable_reasons'][0])
        lock = (self.project / 'flint.lock').read_text()
        self.assertIn('linkage = "system"', lock)
        self.assertNotIn('package_id', lock)

    def test_7_audit_and_sbom_list_the_native_package(self):
        self.use('zlib = "1.4"\n')
        self.assertEqual(self.run_flint('lock')[0], 0)
        status, document = self.run_flint('deps', 'audit')
        self.assertEqual(status, 0, document['diagnostics'])
        components = {c['name']: c for c in document['components']}
        self.assertEqual((components['zlib']['license'], components['zlib']['origin']), ('Zlib', 'native'))
        self.assertTrue(any(line.startswith('native zlib 1.4 source sha256 ' + LOCK['zlib']['archive_sha256'])
                            for line in document['verified']))


    @unittest.skipUnless((ROOT / '.tools/ldc-1.43.0-sanitizer-runtime/flint-sanitizer-runtime.json').is_file(),
                         'sanitizer runtime not installed (flint toolchain install --sanitizers)')
    def test_8_sanitize_builds_the_native_package_instrumented(self):
        self.use('zlib = "1.4"\n')
        self.assertEqual(self.run_flint('lock')[0], 0)
        status, document = self.run_flint('test', '--sanitize')
        self.assertEqual(status, 0, document['diagnostics'])
        receipt = json.loads((self.project / '.flint/build/test/demo-test.receipt.json').read_text())
        locked = (self.project / 'flint.lock').read_text()
        sanitized = receipt['native_packages'][0]
        # The instrumented variant is another binary package of the same locked recipe and source.
        self.assertIn('recipe_revision = "' + sanitized['recipe_revision'] + '"', locked)
        self.assertNotIn('package_id = "' + sanitized['package_id'] + '"', locked)


if __name__ == '__main__':
    unittest.main()
