"""Regression tests for the JDK link-closure gate."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import jdk_link_closure as closure


class LinkClosureTests(unittest.TestCase):
    def test_baseline_compares_each_commit_and_rejects_readded_violations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', root], check=True)
            path = root / closure.BASELINE
            path.parent.mkdir(parents=True)
            violation = 'import|java|flint.java.lang|std.conv'

            def commit_baseline(violations):
                path.write_text(json.dumps({'schema': closure.BASELINE_SCHEMA,
                                            'source_commit': 'a' * 40, 'violations': violations}))
                closure.git(root, 'add', closure.BASELINE)
                closure.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                            'commit', '-qm', 'Update baseline')

            commit_baseline([violation])
            self.assertEqual(closure.baseline_growth(root, {violation}), [])
            commit_baseline([])
            self.assertEqual(closure.baseline_growth(root, set()), [])
            self.assertIn('violation added in working tree', closure.baseline_growth(root, {violation})[0])
            self.assertEqual(len(closure.check_violations(set(), {violation})), 1)
            self.assertEqual(closure.check_violations({violation}, {violation}), [])
            self.assertEqual(len(closure.check_violations({violation}, {violation}, release=True)), 1)

    def test_legacy_module_records_can_seed_a_new_probe_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', '-q', root], check=True)
            path = root / closure.BASELINE
            path.parent.mkdir(parents=True)
            old = 'link|java|flint.java.lang|integer|O3|undeclared module records flint.java.util'
            new = 'link|java-time|flint.java.time.period|parse|O3|undeclared module records flint.java.util'
            path.write_text(json.dumps({'schema': closure.BASELINE_SCHEMA, 'source_commit': 'a' * 40,
                                        'violations': [old]}))
            closure.git(root, 'add', '.')
            closure.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'Seed')
            manifest = root / 'framework/java-time/closure.json'
            manifest.parent.mkdir()
            manifest.write_text(json.dumps({'probes': {'flint.java.time.period': {
                'parse': {'leaves': ['flint.java.lang']},
            }}}))
            self.assertEqual(closure.baseline_growth(root, {old, new}), [])
            self.assertTrue(closure.baseline_growth(root, {old, new.replace('module records', 'leaf')}))
            closure.git(root, 'add', '.')
            closure.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                        'commit', '-qm', 'Add probe without exemption')
            self.assertTrue(closure.baseline_growth(root, {old, new}))

    def test_discarded_sections_are_ignored_but_local_data_is_checked(self):
        linker_map = """Discarded input sections
 .text._D3std5regex4testFZv
                0x00000000 0x5 discarded.o
Linker script and memory map
.text           0x00000010 0x5
 .text._D3std4conv4testFZv
                0x00000010 0x5 retained.o
 .text._D5flint4java4time10__functionFZv
                0x00000018 0x5 retained.o
"""
        symbols = """0000000000000020 r _D5flint4java4time4data5zonesyG200h
0000000000000030 T _D5flint4java4time5parseFZv
0000000000000040 T _D5flint4java4time6format5printFZv
"""
        modules = {'flint.java.time', 'flint.java.time.format', 'flint.java.time.data'}
        retained = closure.map_symbols(linker_map) | closure.defined_symbols(symbols)
        problems = closure.violations(retained, modules, {'flint.java.time'}, set())
        self.assertEqual(list(problems), ['banned Phobos std.conv', 'undeclared data flint.java.time.data',
                                          'undeclared leaf flint.java.time.format'])
        problems = closure.violations(retained, modules, modules - {'flint.java.time.data'}, {'flint.java.time.data'})
        self.assertEqual(list(problems), ['banned Phobos std.conv'])

    def test_lld_map_and_malformed_map(self):
        self.assertEqual(closure.map_symbols('VMA LMA Size Align Out In Symbol\n'
                                             ' 40 40 3 1          _D3std3uni4testFZv\n'),
                         {'_D3std3uni4testFZv'})
        with self.assertRaisesRegex(ValueError, 'linker map'):
            closure.map_symbols('Discarded input sections\n .text._D3std3uni4testFZv')

    def test_archive_trigger_follows_weak_instance_back_to_the_probe(self):
        linker_map = """Archive member included to satisfy reference by file (symbol)

libphobos.a(uni.o)
                /tmp/probe.o (symbol from plugin) (_D3std3uni4testFZv)
libphobos.a(curl.o)
                libphobos.a(uni.o) (_D4core8internal17arrayResizeSymbolFZv)
libphobos.a(curl.o)
                libphobos.a(uni.o) (_D3std3net4curl4testFZv)

Discarded input sections
"""
        triggers = closure.phobos_triggers(linker_map, {'std.uni', 'std.net'})
        self.assertEqual(triggers['std.net']['object'], 'probe.o')
        self.assertEqual(triggers['std.net']['symbol'], '_D3std3uni4testFZv')
        self.assertEqual(triggers['std.net']['archive_member'], 'libphobos.a(curl.o)')

    def test_module_record_exception_does_not_allow_code_from_same_leaf(self):
        module = 'flint.java.time'
        record = '_D5flint4java4time11__moduleRefZ'
        function = '_D5flint4java4time5parseFZv'
        existing = closure.violations({record}, {module}, set(), set())
        self.assertEqual(existing, {'undeclared module records flint.java.time': record})
        leaking = closure.violations({record, function}, {module}, set(), set())
        self.assertEqual(closure.check_violations(set(leaking), set(existing)),
                         ['new violation: undeclared leaf flint.java.time'])

    def test_file_backed_allocated_sections_exclude_padding_and_nobits(self):
        sections = """
  [ 1] .text            PROGBITS 00004000 004000 000020 00 AX  0   0  8
  [ 2] .rodata          PROGBITS 00009000 009000 000012 00  A  0   0  8
  [ 3] .bss             NOBITS   0000a000 00a000 000fff 00 WA  0   0  8
  [ 4] .debug_info      PROGBITS 00000000 00a000 000080 00     0   0  1
"""
        self.assertEqual(closure.loadable_section_bytes(sections), 0x32)
        with self.assertRaisesRegex(ValueError, 'loadable'):
            closure.loadable_section_bytes('no section headers')

    def test_structural_bans_match_import_families(self):
        self.assertEqual(closure.banned_imports('module flint.java.a;\n'
                                               'static import n = std.net.curl;\n'
                                               'void render() { import std.format : format; }\n'
                                               'alias Convert = imported!("std.conv");\n'
                                               '// import std.file;\n'
                                               'import std.utf : decode;\n'),
                         ['std.conv', 'std.format', 'std.net.curl'])

    def test_new_public_leaf_cannot_be_omitted_from_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            source = package / 'source/flint/java'
            source.mkdir(parents=True)
            (source / 'package.d').write_text('module flint.java;\npublic import flint.java.sample;\n@safe:\n')
            (source / 'sample.d').write_text('module flint.java.sample;\n@safe:\nint example() { return 1; }\n')
            (package / 'closure.json').write_text('{"schema": "flint.jdk-closure/1", "probes": {}}')
            modules = closure.source_modules(package)
            with self.assertRaisesRegex(ValueError, 'missing probes for flint.java.sample'):
                closure.read_manifest(package, modules)

    def test_selective_reexport_from_a_leaf_still_needs_a_probe(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            source = package / 'source/flint/java'
            source.mkdir(parents=True)
            (source / 'object.d').write_text('module flint.java.object;\n'
                                            'public import flint.engine.aot.any : Any;\n@safe:\n')
            self.assertEqual(closure.source_modules(package), {'flint.java.object': True})

    @unittest.skipUnless(sys.platform.startswith('linux') and all(shutil.which(tool)
                         for tool in ('dub', 'ldc2', 'readelf', 'nm')), 'requires the ELF probe toolchain')
    def test_real_thinlto_links_report_undeclared_data_in_both_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'workspace'
            package = root / 'framework/java'
            modules = package / 'source/flint/java'
            for directory in (root / 'policy', modules / 'data', package / 'closure'):
                directory.mkdir(parents=True)
            (root / 'dub.sdl').write_text('name "flint"\ntargetType "none"\nsubPackage "framework/java"\n')
            (package / 'dub.sdl').write_text('name "java"\ntargetType "library"\n')
            (root / 'policy/framework.json').write_text('{"modules":{"java":{"directory":"framework/java"}}}')
            (modules / 'data/table.d').write_text('module flint.java.data.table;\n@safe:\n'
                                                  'immutable int[6] values = [7, 5, 2, 8, 4, 0];\n')
            (modules / 'sample.d').write_text('module flint.java.sample;\n@safe:\n'
                'int lookup(size_t index) { import flint.java.data.table : values; return values[index % values.length]; }\n')
            (package / 'closure/sample.d').write_text('module app;\nimport flint.java.sample : lookup;\n@safe:\n'
                                                      'int main(string[] args) { return lookup(args.length); }\n')
            entry = {'source': 'closure/sample.d', 'leaves': [], 'data': []}
            document = {'schema': closure.SCHEMA, 'probes': {'flint.java.sample': {'sample': entry}}}
            manifest = package / 'closure.json'
            with patch.object(closure, 'ROOT', root), patch.object(closure, 'copy_workspace',
                                                                  lambda dest: shutil.copytree(root, dest)):
                manifest.write_text(json.dumps(document))
                report = closure.audit('java', None)['flint.java.sample']['sample']
                self.assertEqual(set(report), {'O3', 'Oz'})
                for profile in report.values():
                    self.assertIn('undeclared data flint.java.data.table', profile['violations'])
                    self.assertGreater(profile['loadable_bytes'], 0)
                entry['data'].append('flint.java.data.table')
                manifest.write_text(json.dumps(document))
                report = closure.audit('java', None)['flint.java.sample']['sample']
                for profile in report.values():
                    self.assertFalse(profile['violations'])

if __name__ == '__main__':
    unittest.main()
