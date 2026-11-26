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

    def test_only_exact_fixture_module_records_are_exempt(self):
        aggregate = 'flint.java'
        other = 'flint.java.text'
        module = 'flint.java.nio.buffer_state_probe'
        prefix = closure.mangle_prefix(module)
        own = prefix + '11__moduleRefZ'
        own_info = prefix + '12__ModuleInfoZ.llvm.0'
        helper = prefix + '6helperFZv'
        aggregate_record = closure.mangle_prefix(aggregate) + '11__moduleRefZ'
        other_record = closure.mangle_prefix(other) + '11__moduleRefZ'
        phobos = '_D3std3uni4testFZv'
        modules = {aggregate, other}
        symbols = {own, own_info, helper, aggregate_record, other_record, phobos}

        findings = closure.violations(symbols, modules, set(), set(), probe_module=module)
        self.assertEqual(findings, {
            'banned Phobos std.uni': phobos,
            'undeclared leaf flint.java': helper,
            'undeclared module records flint.java': aggregate_record,
            'undeclared module records flint.java.text': other_record,
        })
        with self.assertRaisesRegex(ValueError, 'probe module is a registered JDK module'):
            closure.violations(symbols, modules, set(), set(), probe_module=aggregate)

    def test_repeated_module_segments_resolve_identifier_backreferences(self):
        root = 'flint.java.util.regex'
        internal = root + '.internal.regex'
        function = '_D5flint4java4util5regex8internalQp10FrameStack4pushMFZv'
        record = '_D5flint4java4util5regex8internalQp11__moduleRefZ.llvm.0'
        modules = {root, internal}
        self.assertEqual(closure.violations({function, record}, modules, {root}, set()),
                         {f'undeclared leaf {internal}': function, f'undeclared module records {internal}': record})
        self.assertEqual(closure.violations({function, record}, modules, {internal}, set()), {})

        nested = root + '.abcdefghijklmnopqrstuvwxy.regex'
        long_backref = '_D5flint4java4util5regex25abcdefghijklmnopqrstuvwxyQBh4testFZv'
        self.assertEqual(closure.violations({long_backref}, {root, nested}, {root}, set()),
                         {f'undeclared leaf {nested}': long_backref})

    def test_loadable_sections_exclude_padding_and_thread_local_bss(self):
        sections = """
  [ 1] .text            PROGBITS 00004000 004000 000020 00 AX  0   0  8
  [ 2] .rodata          PROGBITS 00009000 009000 000012 00  A  0   0  8
  [ 3] .bss             NOBITS   0000a000 00a000 000fff 00 WA  0   0  8
  [ 4] .tbss            NOBITS   0000b000 00a000 000800 00 WAT 0   0  8
  [ 5] .debug_info      PROGBITS 00000000 00a000 000080 00     0   0  1
"""
        self.assertEqual(closure.loadable_section_bytes(sections), 0x1031)
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

    def test_independent_probe_files_can_share_a_leaf_with_legacy_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            leaf = 'flint.java.sample'
            fragments = package / 'closure-probes' / leaf
            fragments.mkdir(parents=True)
            fixtures = package / 'closure'
            fixtures.mkdir()
            first = {'source': 'closure/first.d', 'leaves': [], 'data': []}
            second = {'source': 'closure/second.d', 'leaves': [], 'data': []}
            for name in ('first', 'second'):
                (fixtures / f'{name}.d').write_text(f'import {leaf};\n')
            (fragments / 'second.json').write_text(json.dumps(second))
            self.assertEqual(closure.read_manifest(package, {leaf: True}), {leaf: {'second': second}})

            manifest = package / 'closure.json'
            manifest.write_text(json.dumps({'schema': closure.SCHEMA, 'probes': {leaf: {'first': first}}}))
            self.assertEqual(closure.read_manifest(package, {leaf: True}), {leaf: {'first': first, 'second': second}})

            (fragments / 'first.json').write_text(json.dumps(first))
            with self.assertRaisesRegex(ValueError, 'duplicate probe record'):
                closure.read_manifest(package, {leaf: True})
            (fragments / 'first.json').unlink()
            (fragments / 'second.json').write_text(json.dumps(first))
            with self.assertRaisesRegex(ValueError, 'duplicate probe source'):
                closure.read_manifest(package, {leaf: True})

    def test_probe_files_preserve_identity_in_baseline_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', root], check=True)
            package = root / 'framework/java-time'
            leaf = 'flint.java.time.sample'
            path = package / 'closure-probes' / leaf / 'sample.json'
            path.parent.mkdir(parents=True)
            entry = {'source': 'closure/sample.d', 'leaves': ['flint.java.lang'], 'data': []}
            legacy = package / 'closure.json'
            legacy.write_text(json.dumps({'schema': closure.SCHEMA, 'probes': {leaf: {'sample': entry}}}))
            closure.git(root, 'add', '.')
            closure.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                        'commit', '-qm', 'Add legacy probe')
            legacy.unlink()
            path.write_text(json.dumps(entry))
            self.assertEqual(closure.probe_record(root, None, 'java-time', leaf, 'sample'), entry)
            row = f'link|java-time|{leaf}|sample|O3|undeclared module records flint.java.util'
            self.assertFalse(closure.may_seed_legacy_record(root, None, row, {'flint.java.util'}))

            closure.git(root, 'add', '-A')
            closure.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                        'commit', '-qm', 'Move probe to its own file')
            self.assertEqual(closure.probe_record(root, 'HEAD', 'java-time', leaf, 'sample'), entry)
            self.assertFalse(closure.may_seed_legacy_record(root, 'HEAD', row, {'flint.java.util'}))

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
    def test_abstract_leaf_can_use_a_concrete_probe_only_with_real_coverage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / 'framework/java'
            modules = package / 'source/flint/java'
            for directory in (root / 'policy', modules, package / 'closure'):
                directory.mkdir(parents=True)
            (root / 'dub.sdl').write_text('name "flint"\ntargetType "none"\nsubPackage "framework/java"\n')
            (package / 'dub.sdl').write_text('name "java"\ntargetType "library"\n')
            (root / 'policy/framework.json').write_text('{"modules":{"java":{"directory":"framework/java"}}}')
            base, child = 'flint.java.buffer', 'flint.java.bytebuffer'
            base_source = modules / 'buffer.d'
            abstract_base = (
                f'module {base};\n@safe:\nabstract class Buffer {{\n'
                '    protected this() {}\n'
                '    int position(int n) { return n + stride(); }\n'
                '    int snapshot()() { return stride(); }\n'
                '    abstract int stride();\n'
                '}\n'
            )
            base_source.write_text(abstract_base)
            child_source = modules / 'bytebuffer.d'
            concrete_child = (
                f'module {child};\nimport {base} : Buffer;\n@safe:\n'
                'final class ByteBuffer : Buffer {\n'
                '    override int stride() { return 1; }\n'
                '    static ByteBuffer allocate() { return new ByteBuffer; }\n'
                '}\n'
            )
            child_source.write_text(concrete_child)
            fixture = package / 'closure/cursor.d'
            use_buffer = (f'module cursor;\nimport {child} : ByteBuffer;\n@safe:\n'
                          'int main(string[] args) { return ByteBuffer.allocate().position(cast(int) args.length); }\n')
            fixture.write_text(use_buffer)
            covering = {'leaf': child, 'probe': 'cursor', 'abstract_type': 'Buffer', 'concrete_type': 'ByteBuffer'}
            fragments = {
                base: {'covered_by': covering},
                child: {'source': 'closure/cursor.d', 'leaves': [base], 'data': []},
            }
            for leaf, entry in fragments.items():
                path = package / closure.PROBE_DIRECTORY / leaf / 'cursor.json'
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(entry))
            with patch.object(closure, 'ROOT', root), patch.object(closure, 'copy_workspace',
                                                                  lambda dest: shutil.copytree(root, dest)):
                report = closure.audit('java', None)
                concrete = report[child]['cursor']
                self.assertEqual(set(concrete), {'O3', 'Oz'})
                self.assertTrue(all(not result['violations'] for result in concrete.values()))
                for result in concrete.values():
                    self.assertTrue(result['covers'][base + '/cursor'].startswith(closure.mangle_prefix(base)))

                base_source.write_text(abstract_base.replace('protected this()', 'public this()'))
                with self.assertRaisesRegex(closure.BuildError, 'public constructor'):
                    closure.audit('java', None)

                base_source.write_text(abstract_base.replace('    abstract int stride();',
                    '    abstract int stride();\n    static Buffer factory() { return null; }'))
                with self.assertRaisesRegex(closure.BuildError, 'public factory'):
                    closure.audit('java', None)

                base_source.write_text(abstract_base.replace('    abstract int stride();',
                    '    abstract int stride();\n    static Buffer factory()() { return null; }'))
                with self.assertRaisesRegex(closure.BuildError, 'public factory'):
                    closure.audit('java', None)

                base_source.write_text(abstract_base)
                child_source.write_text(concrete_child.replace('class ByteBuffer : Buffer', 'class ByteBuffer')
                                                     .replace('override int stride', 'int stride'))
                with self.assertRaisesRegex(closure.BuildError, 'needs a concrete subclass'):
                    closure.audit('java', None)

                child_source.write_text(concrete_child)
                fixture.write_text(use_buffer.replace('@safe:', f'import {base} : Buffer;\n@safe:'))
                with self.assertRaisesRegex(ValueError, 'probe must import only the JDK leaf'):
                    closure.audit('java', None)

                fixture.write_text(use_buffer.replace('ByteBuffer.allocate().position(cast(int) args.length)',
                                                      'cast(int) args.length'))
                with self.assertRaisesRegex(closure.BuildError, 'no retained Buffer'):
                    closure.audit('java', None)

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
            (modules / 'package.d').write_text('module flint.java;\npublic import flint.java.sample;\n@safe:\n')
            (modules / 'sample.d').write_text('module flint.java.sample;\n@safe:\n'
                'int lookup(size_t index) { import flint.java.data.table : values; return values[index % values.length]; }\n')
            (package / 'closure/sample.d').write_text('module flint.java.sample_probe;\n'
                                                      'import flint.java.sample : lookup;\n@safe:\n'
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
                fragment = package / 'closure-probes/flint.java.sample/sample.json'
                fragment.parent.mkdir(parents=True)
                fragment.write_text(json.dumps(entry))
                manifest.unlink()
                report = closure.audit('java', None)['flint.java.sample']['sample']
                for profile in report.values():
                    self.assertFalse(profile['violations'])

if __name__ == '__main__':
    unittest.main()
