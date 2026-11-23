#!/usr/bin/env python3
"""Adversarial evidence/protocol tests. Temporary synthetic data is never a baseline."""
from __future__ import annotations
import argparse
import hashlib
import copy
import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import collect_evidence as evidence
import gates
import measure_builds as builds
from perf_stats import finite_samples, median_ratio_interval
from test_guards import synthetic_evidence


def gc_fixture():
    return {'phase': 'steady_state', 'requests_completed': 100000, 'worker_count': 2,
            'worker_ids': [101, 102], 'before_barrier_workers': 2, 'after_barrier_workers': 2,
            'allocated_before_per_worker': [4000, 8000], 'allocated_after_per_worker': [4000, 8000],
            'allocated_bytes_per_worker': [0, 0], 'collections_before': 1, 'collections_after': 1,
            'collection_delta': 0}


class CounterProtocolTests(unittest.TestCase):
    def test_complete_raw_counter_protocol_is_accepted(self):
        self.assertEqual(evidence.validate_gc(gc_fixture())['allocated_bytes_per_worker'], [0, 0])

    def test_hidden_worker_allocation_is_rejected(self):
        payload = gc_fixture(); payload['allocated_after_per_worker'][1] += 16
        with self.assertRaisesRegex(ValueError, 'raw monotonic counters'):
            evidence.validate_gc(payload)

    def test_collection_cannot_be_hidden_by_zero_summary(self):
        payload = gc_fixture(); payload['collections_after'] += 1
        with self.assertRaisesRegex(ValueError, 'raw process counters'):
            evidence.validate_gc(payload)

    def test_replaced_or_missing_worker_is_rejected(self):
        for field, value in [('worker_ids', [101, 101]), ('after_barrier_workers', 1), ('before_barrier_workers', True)]:
            with self.subTest(field=field):
                payload = gc_fixture(); payload[field] = value
                with self.assertRaises(ValueError):evidence.validate_gc(payload)

    def test_short_request_run_is_not_hot_path_evidence(self):
        payload = gc_fixture(); payload['requests_completed'] = 99999
        with self.assertRaisesRegex(ValueError, '100000'):
            evidence.validate_gc(payload)

    def test_counter_wrap_or_decrease_is_rejected(self):
        payload = gc_fixture(); payload['allocated_after_per_worker'][0] = 1
        payload['allocated_bytes_per_worker'][0] = -3999
        with self.assertRaisesRegex(ValueError, 'allocation delta'):
            evidence.validate_gc(payload)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        self.path = self.root / 'output.log'; self.path.write_text('observed command output\n')
        self.receipt = {'schema': 1, 'commit': 'a' * 40, 'command': ['real-command'],
                        'exit_code': 0, 'artifact': self.path.name, 'sha256': evidence.digest(self.path)}

    def tearDown(self):self.temporary.cleanup()

    def test_receipt_rehashes_actual_file(self):
        self.assertEqual(evidence.verified_receipt(self.receipt, self.root, 'a' * 40), self.path)
        self.path.write_text('tampered command output\n')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            evidence.verified_receipt(self.receipt, self.root, 'a' * 40)

    def test_receipt_from_other_commit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'another source commit'):
            evidence.verified_receipt(self.receipt, self.root, 'b' * 40)

    def test_false_boolean_exit_code_is_not_zero(self):
        self.receipt['exit_code'] = False
        with self.assertRaisesRegex(ValueError, 'did not pass'):
            evidence.verified_receipt(self.receipt, self.root)

    def test_missing_artifact_does_not_become_pass(self):
        self.path.unlink()
        with self.assertRaisesRegex(ValueError, 'artifact missing'):
            evidence.verified_receipt(self.receipt, self.root)

    def test_escaping_portable_bundle_path_is_rejected(self):
        parent = self.root / 'bundle'; parent.mkdir()
        self.receipt['artifact'] = '../output.log'
        doc = {'mode': 'production', 'commit': self.receipt['commit'], 'receipts': {'quality': self.receipt}}
        with self.assertRaisesRegex(ValueError, 'leaves evidence bundle'):
            gates.verify_evidence_artifacts(doc, parent)

    def test_smoke_mode_cannot_be_promoted(self):
        with self.assertRaisesRegex(ValueError, 'smoke'):
            evidence.validate_http({'schema': 1, 'mode': 'smoke'}, {})

    def test_incomplete_production_http_fails_before_aggregation(self):
        with self.assertRaisesRegex(ValueError, 'did not complete'):
            evidence.validate_http({'schema': 1, 'mode': 'production', 'status': 'failed'}, {})

    def test_duplicate_json_key_is_rejected(self):
        self.path.write_text('{"exit_code":1,"exit_code":0}')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            evidence.read(self.path)

    def test_capture_payload_cannot_override_real_stdout(self):
        self.path.write_text('{"micro":{"fixture":[12]}}')
        self.receipt['sha256'] = evidence.digest(self.path)
        capture = {'schema': 1, 'mode': 'production', 'kind': 'micro', 'receipt': self.receipt,
                   'payload': {'micro': {'fixture': [12]}}}
        evidence.validate_capture(capture, self.root, self.receipt['commit'], 'micro')
        capture['payload']['micro']['fixture'][0] = .01
        with self.assertRaisesRegex(ValueError, 'differs from the captured command stdout'):
            evidence.validate_capture(capture, self.root, self.receipt['commit'], 'micro')

    def test_displayed_metrics_must_match_retained_payloads(self):
        document = {'mode': 'production', 'commit': 'a' * 40, 'packages': {'fixture': 1}, 'modules': {},
                    'apps': {}, 'go': {'apps': {}, 'rest': {'p99_ms': [2]}},
                    'rest': {'p99_ms': [1]}, 'micro': {'fixture': [3]}, 'gc': {'fixture': 0},
                    'platforms': {'fixture': True}, 'receipts': {}}
        payloads = {
            'compile': {'packages': document['packages'], 'modules': {}, 'apps': {}, 'go': {'apps': {}}},
            'size': {'packages': document['packages'], 'modules': {}, 'apps': {}, 'go': {'apps': {}}},
            'runtime': {'http': {'rest': document['rest'], 'go': {'rest': document['go']['rest']}}, 'micro': document['micro']},
            'hot_gc': {'gc': document['gc']}, 'cross_platform': {'platforms': document['platforms']}}
        for name, payload in payloads.items():
            path = self.root / (name + '.json'); path.write_text(json.dumps(payload))
            document['receipts'][name] = dict(self.receipt, artifact=path.name, sha256=evidence.digest(path))
        gates.verify_evidence_artifacts(document, self.root)
        document['rest']['p99_ms'][0] = .01
        with self.assertRaisesRegex(ValueError, 'summary differs'):
            gates.verify_evidence_artifacts(document, self.root)


class SourceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        subprocess.run(['git', 'init', '--quiet', self.root], check=True)
        (self.root / 'source.d').write_text('module example;\n')
        subprocess.run(['git', 'add', 'source.d'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        'commit', '--quiet', '-m', 'Synthetic test checkout'], cwd=self.root, check=True)

    def tearDown(self):self.temporary.cleanup()

    def test_committed_source_identity_is_observed(self):
        commit, native = builds.source_identity(self.root)
        self.assertEqual(len(commit), 40); self.assertIsNone(native)

    def test_uncommitted_source_does_not_inherit_head_identity(self):
        (self.root / 'source.d').write_text('module changed;\n')
        with self.assertRaisesRegex(RuntimeError, 'uncommitted source'):
            builds.source_identity(self.root)

    def test_untracked_source_does_not_inherit_head_identity(self):
        (self.root / 'extra.d').write_text('module extra;\n')
        with self.assertRaisesRegex(RuntimeError, 'untracked inputs'):
            builds.source_identity(self.root)

    def test_capture_json_runs_actual_command_and_retains_output(self):
        script = self.root / 'tools/collect_evidence.py'; script.parent.mkdir()
        shutil.copy2(evidence.__file__, script)
        output = self.root / 'artifacts/captured.json'
        command = [sys.executable, str(script), 'capture-json', '--kind', 'micro', '--output', str(output),
                   '--', sys.executable, '-c', 'print("{\\"fixture\\": 123}")']
        process = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        capture = evidence.read(output)
        self.assertEqual(capture['payload'], {'fixture': 123})
        artifact = evidence.verified_receipt(capture['receipt'], output.parent, capture['receipt']['commit'])
        self.assertEqual(evidence.read(artifact), capture['payload'])

    def test_wasi_baseline_requires_exact_verified_reference_archive(self):
        import native_build
        (self.root / '.gitignore').write_text('.native/\n')
        policy = self.root / 'policy'; policy.mkdir()
        lock = {'libraries': [{'name': 'wasmtime', 'consumers': ['engine-wasi'], 'dependencies': []}]}
        (policy / 'native-lock.json').write_text(json.dumps(lock))
        (policy / 'packages.json').write_text(json.dumps({'packages': {'engine-wasi': {}}}))
        package = self.root / 'packages/engine-wasi'; baseline = package / 'bench/baseline'
        baseline.mkdir(parents=True)
        recipe = package / 'dub.sdl'; control = baseline / 'dub.sdl'
        recipe.write_text('name "engine-wasi"\n')
        control_source = 'name "probe-wasi-baseline"\n'
        control.write_text(control_source)
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        'commit', '--quiet', '-m', 'Synthetic native recipe fixture'], cwd=self.root, check=True)
        prefix = self.root / '.native/install/linux-x86_64-glibc'
        lib = prefix / 'lib'; lib.mkdir(parents=True)

        def installed(name, payload=b'!<arch>\n'):
            path = lib / name
            path.write_bytes(payload)
            return {'path': str(path), 'sha256': builds.digest(path)}

        metadata = installed('native-static-link.json', b'{"flags": []}'); metadata['flags'] = []
        receipt = prefix / 'flint-native-install.json'
        state = {'target': 'linux-x86_64-glibc',
                 'ffi_archives': {'base': installed('libflint_ffi_base.a'),
                                  'framework': installed('libflint_ffi_framework.a')},
                 'wasi_reference_archive': installed('libflint_wasi_reference.a'),
                 'libraries': {'wasmtime': {'archives': [installed('libwasmtime.a')],
                                            'system_link_metadata': metadata}}}
        receipt.write_text(json.dumps(state))
        with patch.object(native_build, 'ROOT', self.root):
            args = argparse.Namespace(work_dir=self.root / '.native', target='linux-x86_64-glibc',
                                      prefix=None, cc=None, cxx=None, sanitize=None, phase='build')
            native_build.Builder(args, lock).emit_dub()
            self.assertNotIn('libflint_wasi_reference.a', recipe.read_text())
            original = control.read_text()
            self.assertLess(original.index('libflint_wasi_reference.a'), original.index('libwasmtime.a'))
            _, native = builds.source_identity(self.root)
            self.assertEqual(set(native['generated_blocks']), {str(path.relative_to(self.root)) for path in (recipe, control)})
            self.assertEqual(builds.workload_digest(self.root, control, native),
                             hashlib.sha256(control_source.encode()).hexdigest())
            control.write_text(original.replace('libflint_wasi_reference.a', 'unverified.a'))
            with self.assertRaisesRegex(RuntimeError, 'block differs'):
                builds.source_identity(self.root)
            with self.assertRaisesRegex(RuntimeError, 'benchmark flags changed'):
                builds.workload_digest(self.root, control, native)
            control.write_text(original)
            (lib / 'libflint_wasi_reference.a').write_bytes(b'altered archive')
            with self.assertRaisesRegex(RuntimeError, 'WASI reference archive changed'):
                builds.source_identity(self.root)

    def test_rpc_probe_and_unittest_flags_verify_the_installed_archive(self):
        import native_build
        (self.root / '.gitignore').write_text('.native/\n')
        policy = self.root / 'policy'; policy.mkdir()
        (policy / 'native-lock.json').write_text(json.dumps({'libraries': [
            {'name': 'protobuf-c', 'consumers': ['engine-rpc'], 'dependencies': []}
        ]}))
        (policy / 'packages.json').write_text(json.dumps({'packages': {'engine-rpc': {}}}))
        package = self.root / 'packages/engine-rpc'
        baseline = package / 'bench/baseline'; baseline.mkdir(parents=True)
        recipe = package / 'dub.sdl'
        recipe.write_text('name "engine-rpc"\nconfiguration "unittest" {\n    targetType "library"\n}\n')
        probes = {package / 'bench/dub.sdl': 'name "probe-rpc"\n',
                  baseline / 'dub.sdl': 'name "probe-rpc-baseline"\n'}
        for probe, text in probes.items():
            probe.write_text(text)
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        'commit', '--quiet', '-m', 'Native RPC recipe fixture'], cwd=self.root, check=True)
        prefix = self.root / '.native/install/linux-x86_64-glibc'
        lib = prefix / 'lib'; lib.mkdir(parents=True)
        def archive(name):
            path = lib / name
            path.write_bytes(b'!<arch>\n')
            return {'path': str(path), 'sha256': builds.digest(path)}
        receipt = prefix / 'flint-native-install.json'
        receipt.write_text(json.dumps({
            'target': 'linux-x86_64-glibc',
            'ffi_archives': {'base': archive('libflint_ffi_base.a'), 'framework': archive('libflint_ffi_framework.a')},
            'rpc_test_archive': archive('libflint_rpc_fixture.a'),
            'libraries': {'protobuf-c': {'archives': [archive('libprotobuf-c.a')]}}
        }))
        with patch.object(native_build, 'ROOT', self.root):
            args = argparse.Namespace(work_dir=self.root / '.native', target='linux-x86_64-glibc',
                                      prefix=None, cc=None, cxx=None, sanitize=None, phase='build')
            builder = native_build.Builder(args, json.loads((policy / 'native-lock.json').read_text()))
            builder.emit_dub()
            emitted = recipe.read_text()
            self.assertIn('libflint_rpc_fixture.a', emitted)
            self.assertNotIn('libflint_rpc_fixture.a', builds.NATIVE_BLOCK.findall(emitted)[0])
            _, native = builds.source_identity(self.root)
            for path, original in probes.items():
                with self.subTest(recipe=path):
                    text = path.read_text()
                    self.assertLess(text.index('libflint_rpc_fixture.a'), text.index('libprotobuf-c.a'))
                    self.assertEqual(builds.workload_digest(self.root, path, native),
                                     hashlib.sha256(original.encode()).hexdigest())
                    path.write_text(text.replace('libflint_rpc_fixture.a', 'unverified.a'))
                    with self.assertRaisesRegex(RuntimeError, 'block differs'):
                        builds.source_identity(self.root)
                    with self.assertRaisesRegex(RuntimeError, 'benchmark flags changed'):
                        builds.workload_digest(self.root, path, native)
                    path.write_text(original)
                    with self.assertRaisesRegex(RuntimeError, 'run native_build'):
                        builds.source_identity(self.root)
                    path.write_text(builds.NATIVE_BLOCK.findall(text)[0] + original)
                    with self.assertRaisesRegex(RuntimeError, 'non-generated recipe modification'):
                        builds.source_identity(self.root)
                    path.write_text(text)
            builder.emit_dub()
            self.assertEqual(builds.source_identity(self.root)[1], native)
            recipe.write_text(emitted.replace('libflint_rpc_fixture.a', 'unverified.a'))
            with self.assertRaisesRegex(RuntimeError, 'non-generated recipe modification'):
                builds.source_identity(self.root)
            recipe.write_text(emitted)
            (lib / 'libflint_rpc_fixture.a').write_bytes(b'altered archive')
            with self.assertRaisesRegex(RuntimeError, 'RPC test fixture archive changed'):
                builds.source_identity(self.root)


class MeasurementDefinitionTests(unittest.TestCase):
    def test_size_policy_allows_glibc_libutil_and_rejects_private_shared_libraries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / 'probe'; target.write_bytes(b'synthetic ELF fixture')
            log = root / 'strip.log'
            output = '(NEEDED) Shared library: [libutil.so.1]\n'
            result = subprocess.CompletedProcess([], 0, stdout=output, stderr='')
            with patch.object(builds, 'run_checked', return_value=result):
                size = builds.stripped_size(target, 'strip', 'readelf', root, log)
                self.assertEqual(size['dynamic_system_dependencies'], ['libutil.so.1'])
                result.stdout += '(NEEDED) Shared library: [libprivate.so.1]\n'
                with self.assertRaisesRegex(RuntimeError, 'uncounted shared dependency'):
                    builds.stripped_size(target, 'strip', 'readelf', root, log)

    def test_equivalent_native_profiles_ignore_install_prefix_only(self):
        first = {'engine-wasi': 'versions "FlintNativeWasmtime"\nlflags "/base/native/lib/libwasmtime.a"\n'}
        second = {'engine-wasi': 'versions "FlintNativeWasmtime"\nlflags "/candidate/native/lib/libwasmtime.a"\n'}
        self.assertEqual(builds.native_profile_hash(first, '/base/native'),
                         builds.native_profile_hash(second, '/candidate/native'))
        second['engine-wasi'] = second['engine-wasi'].replace('Wasmtime', 'Wamr')
        self.assertNotEqual(builds.native_profile_hash(first, '/base/native'),
                            builds.native_profile_hash(second, '/candidate/native'))
    def test_independent_estimator_is_ratio_of_group_medians(self):
        first = list(range(1, 10)); second = [9] + list(range(1, 9))
        self.assertEqual(median_ratio_interval(first, second, 1000)[0], 1.0)

    def test_independent_estimator_accepts_unequal_group_counts(self):
        self.assertEqual(median_ratio_interval([2] * 9, [4] * 21, 1000), (.5, .5, .5))

    def test_boolean_or_nonfinite_samples_are_rejected(self):
        for value in [True, float('nan'), float('inf'), 0, -1]:
            with self.subTest(value=value), self.assertRaises(ValueError):finite_samples([value] * 9, 9)

    def test_actual_dmd_vtemplate_line_format(self):
        text = 'a.d(1,2): vtemplate: 9 (3 distinct) instantiation(s) of template `x(T)` found\n'
        self.assertEqual(builds.template_instances(text), 9)
        self.assertEqual(builds.template_instances('successful build with no templates'), 0)

    def test_retry_does_not_reuse_prior_instrumentation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); traces = root / 'traces'; traces.mkdir()
            (traces / 'old.stdout.txt').write_text('vtemplate: 999 (1 distinct) instantiation(s)')
            builds.instrumented_compiler(root, '/unused/dmd', traces)
            self.assertEqual(list(traces.iterdir()), [])

    def test_package_module_edit_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); module = root / 'source/flint/cli/package.d'
            module.parent.mkdir(parents=True); module.write_text('module flint.cli;\n')
            selected = builds.source_edit(root, 'source/flint/cli.d', 3)
            self.assertEqual(selected, 'source/flint/cli/package.d')
            self.assertIn('__flint_measure_edit_3', module.read_text())

    def test_release_profile_has_no_debug_build_type(self):
        command, cwd, env = builds.dub_invocation('dub', Path('/tmp/work'), 'bench', 'ldc2',
                                                  builds.native_profiles()['O3'], {})
        self.assertIn('--build=plain', command)
        self.assertNotIn('-debug', env['DFLAGS']); self.assertNotIn(' -g ', env['DFLAGS'])
        self.assertEqual(env['DUB_HOME'], '/tmp/work/.dub-home')
        self.assertIn('-link-defaultlib-shared=false', env['DFLAGS'])

    def test_initial_baseline_is_not_regression_certification(self):
        document = synthetic_evidence('a' * 40, .8)
        # The live policy/framework.json lists modules this synthetic document does not measure.
        with patch.object(gates, 'median_ratio_interval', return_value=(.5, .5, .5)), \
                patch.object(gates.framework_budgets, 'modules', return_value={}):
            result = gates.measured(document)
        self.assertEqual(result['initial_baseline_validation'], 'pass')
        self.assertEqual(result['regression_comparison'], 'not_run_no_prior_baseline')
        self.assertNotIn('all_six_gates', result)

    def test_initial_baseline_still_enforces_absolute_caps(self):
        document = synthetic_evidence('a' * 40, .8)
        document['packages']['arena']['dmd_cold_seconds'] = [1000] * 9
        with self.assertRaisesRegex(ValueError, 'absolute ceiling'):
            gates.measured(document)

    def test_framework_modules_need_their_measurements(self):
        document = synthetic_evidence('a' * 40, .8)
        listed = {'core': {'directory': 'framework/core', 'module': 'flint.core'}}
        with patch.object(gates, 'median_ratio_interval', return_value=(.5, .5, .5)), \
                patch.object(gates.framework_budgets, 'modules', return_value=listed):
            with self.assertRaisesRegex(ValueError, 'framework modules measured'):
                gates.measured(document)

    def test_initial_baseline_still_enforces_go_comparison(self):
        document = synthetic_evidence('a' * 40, .8)
        with patch.object(gates, 'median_ratio_interval', return_value=(2.0, 1.5, 2.5)):
            with self.assertRaisesRegex(ValueError, 'Go comparison'):
                gates.measured(document)


class TemplateCountMethodTests(unittest.TestCase):
    """The instrumented compiler traces the package's own `-lib` compile as well as `-c` compiles (ADR-019)."""
    def run_wrapper(self, arguments):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            fake = temporary / 'fake-dmd'
            fake.write_text('#!/bin/sh\necho "vtemplate: 7 (3 distinct) instantiation(s) of template x"\n')
            fake.chmod(0o755)
            wrapper = builds.instrumented_compiler(temporary, fake, temporary / 'traces')
            subprocess.run([str(wrapper), *arguments], check=True, capture_output=True)
            return len(list((temporary / 'traces').glob('*.invocation.json')))

    def test_library_and_object_compiles_are_traced(self):
        self.assertEqual(self.run_wrapper(['-lib', '-oflibx.a', 'packages/x/source/x.d']), 1)
        self.assertEqual(self.run_wrapper(['-c', 'packages/x/source/x.d']), 1)
        self.assertEqual(self.run_wrapper(['-ofapp', 'app.o']), 0)

    def test_methods_must_match_for_regression(self):
        base, current = synthetic_evidence('a' * 40, .8), synthetic_evidence('b' * 40, .8)
        base['template_count_method'] = 'own-library-and-probe/2'
        with self.assertRaisesRegex(ValueError, 'template_count_method differs'):
            gates.measured(current, base)


class PublishedBinaryTests(unittest.TestCase):
    """Synthetic byte files test integrity only; none is a framework executable."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        (self.root / 'build').mkdir()
        self.document = {'apps': {'bench-cli': {}, 'bench-rest': {}, 'bench-wasm': {}},
                         'go': {'apps': {}}, 'build_artifacts': {}}
        def artifact(name, data):
            path = self.root / 'build' / name; path.write_bytes(data)
            self.document['build_artifacts'][name] = {'bytes': len(data), 'sha256': evidence.digest(path)}
            return {'binary_bytes': len(data), 'sha256': evidence.digest(path)}
        for name in ['bench-cli', 'bench-rest']:
            self.document['go']['apps'][name] = artifact('reference-go-cli' if name == 'bench-cli' else 'reference-go-rest', b'synthetic Go size fixture')
            for profile, suffix in [('O3', ''), ('Oz', '-Oz')]:
                self.document['apps'][name][profile] = artifact(name + suffix, b'synthetic D size fixture')
        data = b'\0asm\x01\0\0\0'
        for profile, name in [('O3', 'bench.wasm'), ('Oz', 'bench-wasm-Oz.wasm')]:
            value = artifact(name, data)
            self.document['apps']['bench-wasm'][profile] = {
                'raw_bytes': len(data), 'gzip_bytes': len(gzip.compress(data, compresslevel=9, mtime=0)),
                'sha256': value['sha256']}
        self.patch = patch.object(evidence, 'ROOT', self.root); self.patch.start()

    def tearDown(self):self.patch.stop(); self.temporary.cleanup()

    def test_all_published_size_fields_bind_to_actual_bytes(self):
        self.assertEqual(len(evidence.validate_published_binaries(self.document)), 8)

    def test_inflating_go_binary_size_cannot_create_a_win(self):
        self.document['go']['apps']['bench-rest']['binary_bytes'] = 99999999
        with self.assertRaisesRegex(ValueError, 'Go size differs'):
            evidence.validate_published_binaries(self.document)

    def test_wasm_gzip_size_is_recomputed(self):
        self.document['apps']['bench-wasm']['Oz']['gzip_bytes'] = 1
        with self.assertRaisesRegex(ValueError, 'WASM size differs'):
            evidence.validate_published_binaries(self.document)


class RealCompilerProtocolTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('DMD') and os.environ.get('LDC') and os.environ.get('DUB'),
                         'provide DMD, LDC and DUB for actual measurement-tool integration probes')
    def test_actual_compiler_profiles_cache_and_separate_traces(self):
        with tempfile.TemporaryDirectory(prefix='flint-build-protocol-test-') as temporary:
            root = Path(temporary); workspace = root / 'workspace'; source = workspace / 'source'; source.mkdir(parents=True)
            (workspace / 'dub.sdl').write_text('name "flint-protocol-test"\ntargetType "executable"\nsourcePaths "source"\ntargetPath "build"\n')
            (source / 'app.d').write_text('module app; T twice(T)(T n) { return n+n; } int main(){return twice(3)==6?0:1;}\n')
            env = os.environ.copy(); env.pop('DFLAGS', None)
            command, cwd, configured = builds.dub_invocation(os.environ['DUB'], workspace, '.', os.environ['LDC'],
                                                            builds.native_profiles()['O3'], env)
            result = subprocess.run(command + ['--verbose'], cwd=cwd, env=configured, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            compile_line = next(line for line in result.stdout.splitlines() if ' -c ' in line and 'ldc' in line)
            self.assertNotIn(' -d-debug ', compile_line); self.assertNotIn(' -g ', compile_line)
            self.assertIn(str(workspace / '.dub-home'), compile_line)
            self.assertEqual(subprocess.run([str(workspace / 'build/flint-protocol-test')]).returncode, 0)
            size_log = root / 'size.log'; size_log.write_text('Synthetic native size-tool integration test\n')
            size = builds.stripped_size(workspace / 'build/flint-protocol-test', 'strip', 'readelf', workspace, size_log)
            self.assertGreater(size['binary_bytes'], 0)
            self.assertFalse(any('phobos' in name or 'druntime' in name for name in size['dynamic_system_dependencies']))
            trace_dir = root / 'traces'; wrapper = builds.instrumented_compiler(root, os.environ['DMD'], trace_dir)
            command, cwd, configured = builds.dub_invocation(os.environ['DUB'], workspace, '.', wrapper,
                                                            builds.native_profiles()['dmd'], env)
            result = subprocess.run(command, cwd=cwd, env=configured, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            compiler_stdout = ''.join(path.read_text() for path in trace_dir.glob('*.stdout.txt'))
            self.assertEqual(builds.template_instances(compiler_stdout), 1)
            self.assertEqual(len(list(trace_dir.glob('*.trace.json'))), 1)
            self.assertEqual(len(list(trace_dir.glob('*.invocation.json'))), 1)


if __name__ == '__main__':unittest.main()
