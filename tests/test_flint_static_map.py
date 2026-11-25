"""The static-data map (docs/spring/phase1/gc.md, section 3c): flint build appends it, flint.arena applies it.

A flint-built program's writable static data is mostly class metadata, `__init` images and ModuleInfo, none of
which holds a GC pointer. The map takes those bytes out of the GC's roots at startup. These tests build a small
program, then check, from the program itself:
- its state: applied in release builds, audited (validated, nothing trimmed, watched) in dev builds;
- that an object held only by a __gshared variable survives collections;
- the switches: FLINT_GC_STATIC_TRIM=0 and =provable, and FLINT_GC_STATIC_VERIFY;
- that a damaged or stripped map leaves the whole range scanned.
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import environment, flint_json, setUpModule  # noqa: F401

APP = '''module demo.app;

import core.memory : GC;
import flint.arena.data_roots : StaticMapState, staticAuditRunning, staticMapState, staticTrimmedBytes;
import std.stdio : writefln;

@safe:

final class Anchored
{
    int value;
    shared static bool finalized;

    this(int value)
    {
        this.value = value;
    }

    ~this() nothrow @nogc
    {
        finalized = true;
    }
}

void main()
{
    import demo.sys.roots : anchor, names, setAnchor;

    setAnchor(new Anchored(42));
    foreach (_; 0 .. 4)
    {
        foreach (__; 0 .. 10_000)
            cast(void) new ubyte[64];
        GC.collect();
    }
    const survived = !Anchored.finalized && (cast(Anchored) anchor()).value == 42 && names() == ["kept", "data"];
    writefln("state=%d trimmed=%d audit=%d survived=%d", cast(int) staticMapState(), staticTrimmedBytes(),
            cast(int) staticAuditRunning(), cast(int) survived);
}
'''

ROOTS = '''module demo.sys.roots;

@safe:

// Reachable only through the writable data the map must keep scanning: one in .bss, one in .data.
private __gshared Object held;
private __gshared string[] kept = ["kept", "data"];

// SAFETY: The test program sets the global once, from main, before reading it; no other thread exists.
void setAnchor(Object value) @trusted nothrow @nogc
{
    held = value;
}

// SAFETY: As setAnchor.
Object anchor() @trusted nothrow @nogc
{
    return held;
}

// SAFETY: As setAnchor.
string[] names() @trusted nothrow @nogc
{
    return kept;
}
'''

ABSENT, MISMATCHED, DISABLED, AUDITED, APPLIED = range(5)


@unittest.skipUnless(sys.platform.startswith('linux'), 'the static-data map is ELF-only')
class StaticMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-static-map-')
        base = Path(cls.temporary.name)
        cls.env = environment()
        status, document = flint_json('new', 'demo', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'demo'
        manifest = cls.project / 'flint.toml'
        text = manifest.read_text(encoding='utf-8')
        if '"flint:arena"' not in text.split('[test-dependencies]')[0]:
            text = text.replace('[dependencies]\n', '[dependencies]\n"flint:arena" = {}\n', 1)
        manifest.write_text(text, encoding='utf-8', newline='\n')
        app = next((cls.project / 'src').rglob('app.d'))
        app.write_text(APP, encoding='utf-8', newline='\n')
        (app.parent / 'sys').mkdir(exist_ok=True)
        (app.parent / 'sys' / 'roots.d').write_text(ROOTS, encoding='utf-8', newline='\n')
        for profile in ('dev', 'release'):
            status, document = flint_json('build', '--profile', profile, cwd=cls.project, env=cls.env)
            assert status == 0, document['diagnostics']

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def binary(self, profile):
        return self.project / '.flint' / 'build' / profile / 'demo'

    def run_program(self, binary, **variables):
        env = environment(**variables)
        for name in ('FLINT_GC_STATIC_TRIM', 'FLINT_GC_STATIC_VERIFY'):
            if name not in variables:
                env.pop(name, None)
        result = subprocess.run([str(binary)], env=env, capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)
        fields = dict(item.split('=') for item in result.stdout.split())
        return {key: int(value) for key, value in fields.items()}

    def test_release_build_applies_the_map_and_keeps_globals_alive(self):
        report = self.run_program(self.binary('release'))
        self.assertEqual(report['state'], APPLIED)
        self.assertGreater(report['trimmed'], 0)
        self.assertEqual(report['audit'], 0)
        self.assertEqual(report['survived'], 1)

    def test_dev_build_audits_instead_of_trimming(self):
        report = self.run_program(self.binary('dev'))
        self.assertEqual(report['state'], AUDITED)
        self.assertEqual(report['audit'], 1)
        self.assertEqual(report['survived'], 1)

    def test_switches_turn_trimming_off_or_to_provable_only(self):
        off = self.run_program(self.binary('release'), FLINT_GC_STATIC_TRIM='0')
        self.assertEqual((off['state'], off['trimmed'], off['survived']), (DISABLED, 0, 1))
        full = self.run_program(self.binary('release'))
        provable = self.run_program(self.binary('release'), FLINT_GC_STATIC_TRIM='provable')
        self.assertEqual((provable['state'], provable['survived']), (APPLIED, 1))
        self.assertLess(provable['trimmed'], full['trimmed'])
        audited = self.run_program(self.binary('release'), FLINT_GC_STATIC_VERIFY='1')
        self.assertEqual((audited['state'], audited['audit']), (AUDITED, 1))

    def test_a_damaged_or_stripped_map_leaves_the_range_whole(self):
        work = Path(self.temporary.name) / 'copies'
        work.mkdir(exist_ok=True)
        damaged = work / 'damaged'
        shutil.copy2(self.binary('release'), damaged)
        data = bytearray(damaged.read_bytes())
        data[-64 - 9] ^= 0xFF  # a byte of the last keep span: the checksum no longer matches
        damaged.write_bytes(bytes(data))
        report = self.run_program(damaged)
        self.assertEqual((report['state'], report['trimmed'], report['survived']), (MISMATCHED, 0, 1))
        stripped = work / 'stripped'
        shutil.copy2(self.binary('release'), stripped)
        subprocess.run(['strip', str(stripped)], check=True)
        report = self.run_program(stripped)
        self.assertEqual((report['state'], report['survived']), (ABSENT, 1))


if __name__ == '__main__':
    unittest.main()
