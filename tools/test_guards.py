#!/usr/bin/env python3
"""Negative governance tests; synthetic metrics here are NEVER performance baselines."""
import copy
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import gates
import module_budgets
from d_source import tokens, imported_modules, module_default


class SourcePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.original = gates.ROOT
        self.root = Path(self.temporary.name)
        shutil.copy2(self.original / 'dub.sdl', self.root / 'dub.sdl')
        for name in gates.P:
            package = self.root / 'packages' / name
            package.mkdir(parents=True)
            shutil.copy2(self.original / 'packages' / name / 'dub.sdl', package / 'dub.sdl')
        gates.ROOT = self.root
    def tearDown(self):
        gates.ROOT = self.original
        self.temporary.cleanup()
    def source(self, package, module, body):
        path = self.root / 'packages' / package / 'source' / (module.replace('.', '/') + '.d')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('module ' + module + ';\n' + body, encoding='utf-8')
        return path
    def test_safe_default_before_code_passes(self):
        self.source('arena', 'flint.arena', '@safe:\nint value() { return 1; }\n')
        self.assertEqual(gates.structural(['arena'])['packages'], 1)
    def test_nested_safe_does_not_cover_unsafe_module(self):
        self.source('arena', 'flint.arena', 'void dangerous() {}\nstruct Nested { @safe: int x; }\n')
        with self.assertRaisesRegex(ValueError, 'module-scope'):
            gates.structural(['arena'])
    def test_late_safe_default_rejected(self):
        self.source('arena', 'flint.arena', 'void dangerous() {}\n@safe:\n')
        with self.assertRaisesRegex(ValueError, 'module-scope'):
            gates.structural(['arena'])
    def test_arbitrary_sys_directory_not_allowlisted(self):
        self.source('arena', 'flint.arena.user.sys.evasion', '@safe:\n// SAFETY: deliberately invalid location\n@trusted void bad() {}\n')
        with self.assertRaisesRegex(ValueError, 'outside allowlisted'):
            gates.structural(['arena'])
    def test_real_boundary_requires_rationale(self):
        self.source('arena', 'flint.arena.sys.memory', '@safe:\n@trusted void bad() {}\n')
        with self.assertRaisesRegex(ValueError, 'SAFETY'):
            gates.structural(['arena'])
    def test_trusted_scope_cannot_replace_tiny_function(self):
        self.source('arena', 'flint.arena.sys.memory', '@safe:\n// SAFETY: invalid blanket scope\n@trusted:\nvoid bad() {}\n')
        with self.assertRaisesRegex(ValueError, 'scopes/blocks'):
            gates.structural(['arena'])
    def test_allowed_raw_ffi_has_explicit_default(self):
        self.source('arena', 'flint.arena.ffi.pages', '@system:\nextern(C) void* allocate(ulong bytes);\n')
        gates.structural(['arena'])
    def test_module_path_mismatch_rejected(self):
        path = self.source('arena', 'flint.arena', '@safe:\n')
        path.write_text('module flint.conc;\n@safe:\n')
        with self.assertRaisesRegex(ValueError, 'module/path mismatch'):
            gates.structural(['arena'])
    def test_private_dependency_boundary_rejected(self):
        self.source('conc', 'flint.conc', 'import flint.arena.sys.memory;\n@safe:\n')
        with self.assertRaisesRegex(ValueError, 'private boundary'):
            gates.structural(['conc'])
    def test_string_mixin_outside_generator_rejected(self):
        self.source('arena', 'flint.arena', '@safe:\nmixin("im" ~ "port flint.web;");\n')
        with self.assertRaisesRegex(ValueError, 'outside approved generator'):
            gates.structural(['arena'])
    def test_module_thread_local_state_rejected(self):
        for body in ['private ulong requestId;\n', 'const(char)[] name;\n', 'version (linux) { int fd = -1; }\n',
                     'private { Object principal; }\n', 'static if (true) { auto cache = [1]; }\n',
                     'void* handle;\n', 'size_t f(int a = 1) { return a; }\nint[4] slots;\n']:
            with self.subTest(body=body):
                self.source('arena', 'flint.arena', '@safe:\n' + body)
                with self.assertRaisesRegex(ValueError, 'thread-local mutable'):
                    gates.structural(['arena'])
    def test_global_and_scoped_state_allowed(self):
        body = ('private shared ulong counter;\n__gshared int legacy;\nimmutable string name = "x";\n'
                'const(size_t) none = size_t.max;\nenum limit = 4;\nshared { int a; }\n'
                'alias Fn = void function();\nextern (C) int puts(const(char)* text) nothrow;\n'
                'int value() { int local; static int calls; return local + calls; }\n'
                'struct S { int field; static int count; }\nimmutable made = () { int x; return x; }();\n')
        self.source('arena', 'flint.arena', '@safe:\n' + body)
        self.assertEqual(gates.structural(['arena'])['packages'], 1)
    def test_thread_local_allowlist_is_exact(self):
        self.source('arena', 'flint.arena.sys.owner', '@safe:\nprivate uint ownerCounter;\n')
        self.assertEqual(gates.structural(['arena'])['packages'], 1)
        self.source('arena', 'flint.arena.sys.owner', '@safe:\nprivate shared uint ownerCounter;\n')
        with self.assertRaisesRegex(ValueError, 'stale thread_local_allowlist'):
            gates.structural(['arena'])
    def test_comments_strings_and_nested_comments_do_not_invent_imports(self):
        source = ('module example; /+ nested /+ import flint.web; +/ +/\n'
                  'import a = flint.arena : Buffer;\n@safe:\n'
                  'enum text = "import flint.web; @trusted:";\n')
        ts = list(tokens(source))
        self.assertEqual(imported_modules(ts), ['flint.arena'])
        self.assertEqual(module_default(ts), 'safe')
    @unittest.skipUnless(os.environ.get('DMD') or shutil.which('dmd'), 'DMD needed for real generated-code audit')
    def test_compiler_expansion_catches_split_import_string(self):
        self.source('di', 'flint.di.internal.wiring', '@safe:\nmixin("im" ~ "port flint.web;");\n')
        self.source('web', 'flint.web', '@safe:\n')
        with self.assertRaisesRegex(ValueError, 'generated import'):
            gates.structural(['di'])
    @unittest.skipUnless(os.environ.get('DMD') or shutil.which('dmd'), 'DMD needed for real generated-code audit')
    def test_compiler_expansion_catches_generated_trusted(self):
        self.source('di', 'flint.di.internal.wiring', '@safe:\nmixin("@tru" ~ "sted void bad() {}");\n')
        with self.assertRaisesRegex(ValueError, 'generated unsafe'):
            gates.structural(['di'])
    @unittest.skipUnless(os.environ.get('DMD') or shutil.which('dmd'), 'DMD needed for real generated-code audit')
    def test_compiler_expansion_accepts_safe_generated_code(self):
        self.source('di', 'flint.di.internal.wiring', '@safe:\nmixin("int value() { return 1; }");\n')
        result = gates.structural(['di'])
        self.assertEqual(result['generated_dependencies']['compiler_profiles'], 2)

    def test_standard_library_expansions_leave_project_expansions_auditable(self):
        installation = self.root / 'pinned-toolchain'
        compiler = installation / 'linux/bin64/dmd'
        library = installation / 'src/druntime/import/object.d'
        library.parent.mkdir(parents=True)
        library.touch()
        source = self.source('di', 'flint.di.internal.wiring', '@safe:\n')
        output = (f'// expansion at {library}(4990)\nimport imported = std.traits;\n\n'
                  f'// expansion at {source}(3)\nimport flint.web;\n')
        self.assertEqual(imported_modules(gates.project_mixin_tokens(output, compiler)), ['flint.web'])


def synthetic_evidence(commit, scale=1.0):
    """Synthetic constant series for gate logic only; never write this to baselines/."""
    sample = lambda value: [value] * 21
    doc = {'schema': 1, 'commit': commit,
           'environment': {k: 'fixture' for k in ['runner_fingerprint', 'toolchain_fingerprint',
                                                 'dependency_lock_sha256', 'workload_sha256']},
           'packages': {}, 'modules': {}, 'apps': {}, 'receipts': {}, 'gc': {'worker_count': 2,
           'allocated_bytes_per_worker': [0, 0], 'collection_delta': 0}}
    doc['environment']['runner_label'] = gates.B['runner']
    for name in ['quality', 'safety', 'dag', 'betterc', 'sanitizers', 'cross_platform',
                 'hot_gc', 'runtime', 'compile', 'size']:
        doc['receipts'][name] = {'exit_code': 0, 'command': ['synthetic-test-only'], 'sha256': '0' * 64}
    for name, meta in gates.P.items():
        doc['packages'][name] = {k: sample(value * .4 * scale) if k.endswith('seconds')
                                 else max(1, int(value * .4 * scale)) for k, value in meta['budget'].items()}
    for name, caps in gates.B['benchmark_apps'].items():
        doc['apps'][name] = {'O3': {}, 'Oz': {}}
        for key, value in caps.items():
            if key.endswith('seconds'):
                doc['apps'][name][key] = sample(value * .4 * scale)
            else:
                for profile in ['O3', 'Oz']:
                    doc['apps'][name][profile][key] = int(value * .4 * scale)
    doc['platforms'] = {p: True for p in ['linux-x86_64-glibc', 'linux-aarch64-glibc',
        'linux-x86_64-musl', 'linux-aarch64-musl', 'macos-arm64', 'windows-x86_64', 'wasm32']}
    doc['rest'] = {k: sample(scale) for k in ['p50_ms', 'p99_ms', 'p999_ms', 'peak_rss_bytes', 'cpu_ns_per_request']}
    doc['rest']['requests_per_second'] = sample(100 / scale)
    doc['micro'] = {k: sample(scale) for k in ['arena', 'serde', 'validate', 'router', 'reactor_echo']}
    doc['go'] = {'rest': {k: sample(2.0) for k in ['p99_ms', 'peak_rss_bytes', 'cpu_ns_per_request']},
                 'apps': {}}
    doc['go']['rest']['requests_per_second'] = sample(50.0)
    for name in ['bench-cli', 'bench-rest']:
        doc['go']['apps'][name] = {'cold_seconds': sample(100), 'binary_bytes': 999999999}
    return doc


class EvidencePolicyTests(unittest.TestCase):
    def test_boolean_platform_receipt_required(self):
        current, baseline = synthetic_evidence('candidate', .8), synthetic_evidence('base')
        current['platforms']['windows-x86_64'] = 'false'
        with self.assertRaisesRegex(ValueError, 'cross-platform'):
            gates.measured(current, baseline)
    def test_malformed_digest_rejected(self):
        current, baseline = synthetic_evidence('candidate', .8), synthetic_evidence('base')
        current['receipts']['safety']['sha256'] = 'trust-me'
        with self.assertRaisesRegex(ValueError, 'malformed'):
            gates.measured(current, baseline)
    def test_new_gc_allocation_fails(self):
        current, baseline = synthetic_evidence('candidate', .8), synthetic_evidence('base')
        current['gc']['allocated_bytes_per_worker'][1] = 1
        with self.assertRaisesRegex(ValueError, 'GC activity'):
            gates.measured(current, baseline)
    def test_missing_platform_fails(self):
        current, baseline = synthetic_evidence('candidate', .8), synthetic_evidence('base')
        del current['platforms']['linux-aarch64-musl']
        with self.assertRaisesRegex(ValueError, 'cross-platform'):
            gates.measured(current, baseline)


class ModuleBudgetTests(unittest.TestCase):
    """policy/budgets.json module_linked_bytes: per-module linked-bytes budgets."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for name in ('fixture', 'baseline'):
            (self.root / 'probe' / name / 'source').mkdir(parents=True)
            (self.root / 'probe' / name / 'dub.sdl').write_text('name "probe"\n')
            (self.root / 'probe' / name / 'source/app.d').write_text('void main() {}\n')
        for module in ('flint.arena', 'flint.arena.pages'):
            path = self.root / 'packages/arena/source' / (module.replace('.', '/') + '.d')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('module ' + module + ';\n')
    def tearDown(self):
        self.temporary.cleanup()
    def policy(self, modules=None, required=()):
        return {'module_linked_bytes': {'required_packages': list(required), 'modules': modules or {}}}
    def entry(self, linked=4096):
        return {'fixture': 'probe/fixture', 'baseline': 'probe/baseline', 'linked_bytes': linked}
    def test_repository_policy_is_valid(self):
        module_budgets.load(gates.B, gates.P, gates.ROOT)
    def test_missing_section_fails(self):
        with self.assertRaisesRegex(ValueError, 'module_linked_bytes'):
            module_budgets.load({}, gates.P, self.root)
    def test_unknown_required_package_fails(self):
        with self.assertRaisesRegex(ValueError, 'unknown required package'):
            module_budgets.load(self.policy(required=['nope']), gates.P, self.root)
    def test_required_package_needs_every_module(self):
        with self.assertRaisesRegex(ValueError, 'missing flint.arena.pages'):
            module_budgets.load(self.policy({'flint.arena': self.entry()}, ['arena']), gates.P, self.root)
        module_budgets.load(self.policy({'flint.arena': self.entry(), 'flint.arena.pages': self.entry()}, ['arena']),
                            gates.P, self.root)
    def test_unowned_module_fails(self):
        with self.assertRaisesRegex(ValueError, 'no package owns'):
            module_budgets.load(self.policy({'flint.nowhere': self.entry()}), gates.P, self.root)
    def test_missing_fixture_fails(self):
        entry = dict(self.entry(), fixture='probe/absent')
        with self.assertRaisesRegex(ValueError, 'dub.sdl and source/app.d'):
            module_budgets.load(self.policy({'flint.arena': entry}), gates.P, self.root)
    def test_nonpositive_budget_fails(self):
        with self.assertRaisesRegex(ValueError, 'positive integer'):
            module_budgets.load(self.policy({'flint.arena': self.entry(0)}), gates.P, self.root)
    def test_measured_budget_and_regression(self):
        modules = module_budgets.load(self.policy({'flint.arena': self.entry(4096)}), gates.P, self.root)
        row = lambda size: {'modules': {'flint.arena': {'incremental_linked_bytes': size}}}
        module_budgets.check_measured(modules, row(4000), None, 1.05)
        with self.assertRaisesRegex(ValueError, 'budget exceeded'):
            module_budgets.check_measured(modules, row(5000), None, 1.05)
        with self.assertRaisesRegex(ValueError, 'regression'):
            module_budgets.check_measured(modules, row(3000), row(2000), 1.05)
        # A module new in the candidate has no base measurement to regress against.
        module_budgets.check_measured(modules, row(3000), {'modules': {}}, 1.05)
        with self.assertRaisesRegex(ValueError, 'differ from the module budgets'):
            module_budgets.check_measured(modules, {'modules': {}}, None, 1.05)


if __name__ == '__main__':
    unittest.main()
