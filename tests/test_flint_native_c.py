"""Embedded C through flint (Milestone 8, ADR-023): hardening, the object cache, clang-tidy and the ffi rule."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, codes, environment, error, flint_json, setUpModule  # noqa: F401

CLANG = ROOT / '.tools' / ('LLVM-22.1.8-macOS-ARM64' if sys.platform == 'darwin' else 'LLVM-22.1.8-Linux-X64') / 'bin' / 'clang'
SANITIZER_RUNTIME = ROOT / '.tools' / 'ldc-1.43.0-sanitizer-runtime' / 'flint-sanitizer-runtime.json'

CRC = '''#include "crc.h"

#include <stdlib.h>
#include <string.h>

uint32_t demo_crc32(const uint8_t *data, size_t length)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
        }
    }
    return ~crc;
}

int demo_peek(size_t count, size_t index)
{
    int *values = malloc(count * sizeof *values);
    if (values == NULL) {
        return -1;
    }
    memset(values, 0, count * sizeof *values);
    int found = values[index];
    free(values);
    return found;
}

int demo_add(int left, int right)
{
    return left + right;
}
'''
HEADER = '''#ifndef DEMO_CRC_H
#define DEMO_CRC_H
#include <stddef.h>
#include <stdint.h>

uint32_t demo_crc32(const uint8_t *data, size_t length);
int demo_peek(size_t count, size_t index);
int demo_add(int left, int right);

#endif
'''
FFI = '''/// The embedded C, behind a safe D API.
module demo.ffi.crc;

@safe:

private extern (C) uint demo_crc32(scope const(ubyte)* data, size_t length) @system nothrow @nogc;
private extern (C) int demo_peek(size_t count, size_t index) @system nothrow @nogc;
private extern (C) int demo_add(int left, int right) @system nothrow @nogc;

// SAFETY: demo_crc32 reads exactly data.length bytes from data.ptr and keeps no pointer.
/// CRC-32 (IEEE) of `data`.
uint crc32(scope const(ubyte)[] data) @trusted nothrow @nogc
{
    return demo_crc32(data.ptr, data.length);
}

// SAFETY: deliberately unchecked so the sanitizer test can read past a C allocation; tests only.
/// Element `index` of a zeroed C array of `count` ints, checked only by the sanitizers.
int peek(size_t count, size_t index) @trusted nothrow @nogc
{
    return demo_peek(count, index);
}

// SAFETY: demo_add takes two ints by value and touches no memory.
/// left + right in C, where signed overflow is undefined.
int add(int left, int right) @trusted nothrow @nogc
{
    return demo_add(left, right);
}
'''
TEST = '''module demo.crc_test;

import demo.ffi.crc : crc32;

@safe:

@("crc32 matches the IEEE check value")
unittest
{
    assert(crc32(cast(const(ubyte)[]) "123456789") == 0xCBF43926);
}
'''
OVERFLOW_TEST = '''module demo.overflow_test;

import demo.ffi.crc : peek;

@safe:

@("reading past the end of a C allocation is caught by ASan")
unittest
{
    assert(peek(4, 4) != 12345);
}
'''

SIGNED_OVERFLOW_TEST = '''module demo.signed_test;

import demo.ffi.crc : add;

@safe:

@("signed overflow in C is caught by UBSan")
unittest
{
    assert(add(int.max, 1) != 7);
}
'''


@unittest.skipUnless(CLANG.is_file(), 'pinned clang not installed (flint toolchain install)')
class EmbeddedCTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-native-c-')
        base = Path(cls.temporary.name)
        cls.env = environment()
        status, document = flint_json('new', 'demo', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'demo'
        (cls.project / 'native').mkdir()
        (cls.project / 'native' / 'crc.c').write_text(CRC, encoding='utf-8', newline='\n')
        (cls.project / 'native' / 'crc.h').write_text(HEADER, encoding='utf-8', newline='\n')
        (cls.project / 'src' / 'demo' / 'ffi').mkdir()
        (cls.project / 'src' / 'demo' / 'ffi' / 'crc.d').write_text(FFI, encoding='utf-8', newline='\n')
        (cls.project / 'test' / 'demo' / 'crc_test.d').write_text(TEST, encoding='utf-8', newline='\n')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_flint(self, *arguments):
        return flint_json(*arguments, cwd=self.project, env=self.env)

    def receipt(self, document):
        return json.loads((self.project / '.flint/build/dev/demo.receipt.json').read_text(encoding='utf-8'))

    def test_1_build_hardens_and_records_the_c(self):
        status, document = self.run_flint('build')
        self.assertEqual(status, 0, document['diagnostics'])
        binary = self.project / '.flint/build/dev/demo'
        if sys.platform == 'darwin':
            # Mach-O (ADR-024): a PIE executable whose fixups ld64 resolves at load (chained fixups).
            header = subprocess.run(['otool', '-hv', str(binary)], capture_output=True, text=True, encoding='utf-8').stdout
            commands = subprocess.run(['otool', '-l', str(binary)], capture_output=True, text=True, encoding='utf-8').stdout
            self.assertIn('PIE', header)
            self.assertIn('LC_DYLD_CHAINED_FIXUPS', commands)
        else:
            headers = subprocess.run(['readelf', '-lW', str(binary)], capture_output=True, text=True, encoding='utf-8').stdout
            dynamic = subprocess.run(['readelf', '-dW', str(binary)], capture_output=True, text=True, encoding='utf-8').stdout
            self.assertIn('GNU_RELRO', headers)
            self.assertIn('Position-Independent Executable', headers)
            self.assertIn('BIND_NOW', dynamic)
        # ld64 dead-strips functions the executable never calls, as main here never calls the C (ADR-024).
        built = [str(binary)] if sys.platform != 'darwin' else [str(p) for p in (self.project / '.flint/cache/c').glob('*.o')]
        symbols = subprocess.run(['nm', *built], capture_output=True, text=True, encoding='utf-8').stdout
        self.assertIn('demo_crc32', symbols)
        embedded = self.receipt(document)['embedded_c']
        self.assertEqual([s['path'] for s in embedded['sources']], ['native/crc.c'])
        expected = ['-std=c17', '-Wall', '-Wextra', '-Werror', '-D_FORTIFY_SOURCE=3', '-fstack-protector-strong',
                    '-ftrivial-auto-var-init=zero']
        # Darwin arm64 has no stack-clash probing to switch on; it compiles against the SDK instead (ADR-024).
        expected += ['-isysroot'] if sys.platform == 'darwin' else ['-fstack-clash-protection']
        for flag in expected:
            self.assertIn(flag, embedded['flags'])
        self.assertEqual(len(embedded['compiler_sha256']), 64)

    def test_2_objects_are_cached_by_content_including_headers(self):
        cache = self.project / '.flint/cache/c'
        before = sorted(p.name for p in cache.glob('*.o'))
        self.assertEqual(self.run_flint('build')[0], 0)
        self.assertEqual(sorted(p.name for p in cache.glob('*.o')), before)
        header = self.project / 'native' / 'crc.h'
        header.write_text(HEADER.replace('#endif', 'int demo_version(void);\n#endif'), encoding='utf-8', newline='\n')
        try:
            self.assertEqual(self.run_flint('build')[0], 0)
            # A header change that alters the preprocessed unit gives a new key; a cached object is never
            # reused for a different translation unit.
            self.assertEqual(len(list(cache.glob('*.o'))), len(before) + 1)
        finally:
            header.write_text(HEADER, encoding='utf-8', newline='\n')

    def test_3_tests_run_on_both_compilers(self):
        for compiler in ('dmd', 'ldc'):
            status, document = self.run_flint('test', '--compiler', compiler)
            self.assertEqual(status, 0, document['diagnostics'])
            self.assertIn('passed', document['runs'][0]['summary'])

    def test_4_warnings_are_errors(self):
        source = self.project / 'native' / 'crc.c'
        source.write_text(CRC + '\nint demo_unused(int value);\nint demo_unused(int value)\n{\n    int x;\n'
                          '    return value;\n}\n', encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('build')
            self.assertEqual(status, 1)
            self.assertEqual(codes(document), ['FLINT-E0708'])
            self.assertIn('-Wunused-variable', error(document, 'FLINT-E0708')['fix'])
        finally:
            source.write_text(CRC, encoding='utf-8', newline='\n')

    def test_5_check_runs_the_fixed_clang_tidy_profile(self):
        status, document = self.run_flint('check')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertIn('clang-tidy', document['checks'])
        self.assertEqual(document['c_files'], 1)
        source = self.project / 'native' / 'crc.c'
        source.write_text('#include <string.h>\n' + CRC + '\nvoid demo_copy(char *to, const char *from);\n'
                          'void demo_copy(char *to, const char *from)\n{\n    strcpy(to, from);\n}\n', encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('check')
            self.assertEqual(status, 1)
            tidy = [d for d in document['diagnostics'] if d['code'] == 'FLINT-E0603']
            self.assertEqual(len(tidy), 1, document['diagnostics'])
            self.assertEqual(tidy[0]['file'], 'native/crc.c')
            self.assertIn('strcpy', tidy[0]['message'])
        finally:
            source.write_text(CRC, encoding='utf-8', newline='\n')

    def test_6_c_is_reached_only_through_ffi_modules(self):
        rogue = self.project / 'src' / 'demo' / 'rogue.d'
        rogue.write_text('/// Rogue.\nmodule demo.rogue;\n\n@safe:\n\nextern (C) int puts(scope const(char)* text) '
                         '@system nothrow @nogc;\n', encoding='utf-8', newline='\n')
        imported = self.project / 'src' / 'demo' / 'direct.c'
        imported.write_text('int demo_direct(void);\nint demo_direct(void) { return 1; }\n', encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('build')
            self.assertEqual(status, 1)
            found = {(d['code'], d['file']) for d in document['diagnostics']}
            self.assertIn(('FLINT-E0513', 'src/demo/rogue.d'), found)
            self.assertIn(('FLINT-E0513', 'src/demo/direct.c'), found)
        finally:
            rogue.unlink()
            imported.unlink()

    @unittest.skipUnless(SANITIZER_RUNTIME.is_file(), 'sanitizer runtime not installed (flint toolchain install --sanitizers)')
    def test_7_sanitize_instruments_the_c(self):
        status, document = self.run_flint('test', '--sanitize')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(document['runs'][0]['compiler'], 'ldc2')
        overflow = self.project / 'test' / 'demo' / 'overflow_test.d'
        overflow.write_text(OVERFLOW_TEST, encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('test', '--sanitize')
            self.assertEqual(status, 1)
            self.assertEqual(codes(document), ['FLINT-E0702'])
            self.assertIn('heap-buffer-overflow', error(document, 'FLINT-E0702')['fix'])
            # Without sanitizers the same read goes unnoticed: the instrumentation is what caught it.
            status, document = self.run_flint('test')
            self.assertEqual(status, 0, document['diagnostics'])
        finally:
            overflow.unlink()
        signed = self.project / 'test' / 'demo' / 'signed_test.d'
        signed.write_text(SIGNED_OVERFLOW_TEST, encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('test', '--sanitize')
            self.assertEqual(status, 1)
            self.assertIn('signed integer overflow', error(document, 'FLINT-E0702')['fix'])
        finally:
            signed.unlink()

    def test_8_sanitize_rejects_dmd_and_the_workspace(self):
        status, document = self.run_flint('test', '--sanitize', '--compiler', 'dmd')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0003']))
        status, document = flint_json('test', '--sanitize', cwd=ROOT, env=self.env)
        self.assertEqual(codes(document), ['FLINT-E0004'])


if __name__ == '__main__':
    unittest.main()
