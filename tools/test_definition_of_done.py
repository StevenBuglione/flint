#!/usr/bin/env python3
"""The per-module definition of done: `python3 tools/measure_queue.py hold -- python3 tools/test_definition_of_done.py`.

Every step runs with a fake command runner; resolution and ownership read the real policy."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import definition_of_done as dod  # noqa: E402

ROOT = dod.ROOT


class FakeRunner:
    """Answers each command by the first rule whose words all appear in it; records every command."""

    def __init__(self, *rules, default=(0, '', '')):
        self.rules = rules
        self.default = default
        self.calls = []
        self.envs = []

    def __call__(self, argv, timeout=3600, env=None):
        argv = [str(a) for a in argv]
        self.calls.append(argv)
        self.envs.append(env or {})
        for words, answer in self.rules:
            if all(w in argv for w in words):
                return answer(argv) if callable(answer) else answer
        return self.default


def module(**fields):
    base = dict(name='jdbc', kind='framework', repo='framework', directory='framework/jdbc', roots=['framework/jdbc'],
                java_packages=['org.springframework.jdbc'], upstream='spring-framework@v7.1.0',
                budget={'incremental_linked_bytes': 1000, 'template_instances': 100}, provisional=['ldc_cold_seconds'])
    base.update(fields)
    return dod.Module(**base)


class Resolve(unittest.TestCase):
    def test_a_framework_module_resolves_with_its_java_packages(self):
        m = dod.resolve('framework/web/')
        self.assertEqual((m.name, m.kind, m.repo), ('web', 'framework', 'framework'))
        self.assertEqual(m.java_packages, ['org.springframework.http', 'org.springframework.web'])
        self.assertEqual(m.upstream, 'spring-framework@v7.1.0')
        self.assertIn('template_instances', m.budget)

    def test_a_port_of_another_library_owns_that_library_s_packages(self):
        self.assertEqual(dod.resolve('framework/jackson-databind').java_packages, ['tools.jackson.databind'])

    def test_a_spring_boot_port_is_a_boot_module_with_the_spring_boot_pin(self):
        m = dod.resolve('boot/module/flint-boot-webmvc')
        self.assertEqual((m.kind, m.java_packages), ('boot', ['org.springframework.boot.webmvc']))
        self.assertTrue(m.upstream.startswith('spring-boot@'))

    def test_flint_s_own_boot_library_and_engine_packages_port_nothing(self):
        self.assertEqual(dod.resolve('boot/boot').java_packages, [])
        self.assertEqual(dod.resolve('packages/arena').kind, 'package')

    def test_an_unregistered_directory_says_how_to_register_it(self):
        with self.assertRaises(LookupError) as caught:
            dod.resolve('framework/nonesuch')
        self.assertIn('FLINT-E0535', str(caught.exception))
        self.assertIn('platform_modules.py --write', str(caught.exception))

    def test_the_longest_package_prefix_owns_an_element(self):
        table = dod.ownership(ROOT)
        self.assertEqual(dod.owner('org.springframework.web.servlet.DispatcherServlet#doService()', table), 'webmvc')
        self.assertEqual(dod.owner('org.springframework.web.bind.annotation.RequestMapping', table), 'web')
        self.assertEqual(dod.owner('org.springframework.validation.Errors', table), 'context')
        self.assertEqual(dod.owner('org.springframework.jdbc.core.JdbcTemplate#query', table), 'jdbc')
        self.assertEqual(dod.owner('org/springframework/boot/SpringApplicationTests', table), 'boot-core')

    def test_spring_package_segments_reverse_r19_keyword_escapes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'policy').mkdir()
            (root / 'policy' / 'framework.json').write_text(json.dumps({'modules': {
                'ai-commons': {
                    'module': 'flint.ai.content',
                    'also': ['flint.ai.template_', 'flint.ai.function_.support', 'flint.ai.custom_'],
                    'upstream': 'spring-ai@v2.1.0',
                },
            }}))
            table = dod.ownership(root)

        self.assertEqual(table, {
            'org.springframework.ai.content': 'ai-commons',
            'org.springframework.ai.template': 'ai-commons',
            'org.springframework.ai.function.support': 'ai-commons',
            'org.springframework.ai.custom_': 'ai-commons',
        })
        self.assertEqual(dod.owner('org/springframework/ai/template/NoOpTemplateRendererTests', table), 'ai-commons')

    def test_openjdk_type_scope_keeps_unrelated_package_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'policy').mkdir()
            (root / 'api' / 'framework').mkdir(parents=True)
            (root / 'policy' / 'framework.json').write_text(json.dumps({'modules': {
                'java-util': {'module': 'flint.java.util.hexformat', 'upstream': 'openjdk@21.0.13'},
                'java-collections': {'module': 'flint.java.util.bitset', 'upstream': 'openjdk@21.0.13',
                                     'java_types': ['java.util.BitSet']},
            }}))
            (root / 'api' / 'framework' / 'mapping.json').write_text(json.dumps({'elements': {
                'java.util.BitSet': {'d': 'flint.java.util.bitset.BitSet'},
                'java.util.HexFormat': {'d': 'flint.java.util.hexformat.HexFormat'},
            }}))
            table = dod.ownership(root)
        self.assertEqual(dod.owner('java.util.BitSet#get(int)', table), 'java-collections')
        self.assertEqual(dod.owner('java/util/BitSet/stream/BitSetStreamTest', table), 'java-collections')
        self.assertEqual(dod.owner('java.util.HexFormat', table), 'java-util')
        self.assertEqual(dod.owner('java/util/ArrayList/ArrayListBash', table), 'java-util')

    def test_apps_are_chosen_by_dependency_closure(self):
        self.assertEqual(dod.using_apps(dod.resolve('framework/jdbc')), ['gs-relational-data-access', 'petclinic-rest'])
        self.assertNotIn('gs-relational-data-access', dod.using_apps(dod.resolve('framework/webmvc')))


class HostToolchain(unittest.TestCase):
    """sol-security, 2026-11-26: a sorted glob put the alpine (musl) LDC first on glibc Linux."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.tools = self.root / '.tools'
        for name in ('ldc2-1.43.0-alpine-x86_64', 'ldc2-1.43.0-linux-x86_64', 'ldc2-1.42.0-linux-x86_64',
                     'ldc2-1.43.0-linux-aarch64'):
            (self.tools / name / 'bin').mkdir(parents=True)
        (self.tools / 'ldc2-1.44.0-linux-x86_64.tar.xz').write_text('')

    def test_glibc_linux_takes_the_newest_linux_ldc_never_alpine(self):
        self.assertEqual(dod.host_ldc(self.tools, 'Linux', 'x86_64', 'glibc'),
                         self.tools / 'ldc2-1.43.0-linux-x86_64' / 'bin')

    def test_musl_takes_alpine_and_arm_takes_its_own(self):
        self.assertEqual(dod.host_ldc(self.tools, 'Linux', 'x86_64', ''), self.tools / 'ldc2-1.43.0-alpine-x86_64' / 'bin')
        self.assertEqual(dod.host_ldc(self.tools, 'Linux', 'aarch64', 'glibc'),
                         self.tools / 'ldc2-1.43.0-linux-aarch64' / 'bin')
        self.assertIsNone(dod.host_ldc(self.tools, 'Darwin', 'arm64', ''))

    def test_the_runner_s_path_has_one_ldc_and_it_is_the_host_s(self):
        path = dod.Runner(hold=False, root=self.root).environment()['PATH'].split(os.pathsep)
        ldcs = [p for p in path if 'ldc2-' in p and p.startswith(str(self.tools))]
        self.assertEqual(ldcs, [str(dod.host_ldc(self.tools))])
        self.assertNotIn('alpine', ldcs[0]) if 'glibc' in __import__('platform').libc_ver()[0] else None


class Structural(unittest.TestCase):
    def test_pass(self):
        run = FakeRunner()
        self.assertEqual(dod.structural(module(), run).status, 'pass')
        self.assertEqual(run.calls[0][-2:], ['--repo', 'framework'])

    def test_an_engine_package_is_checked_alone(self):
        run = FakeRunner()
        dod.structural(module(name='arena', kind='package', repo='flint'), run)
        self.assertEqual(run.calls[0][-2:], ['--package', 'arena'])

    def test_a_failure_naming_the_module_is_the_module_s(self):
        run = FakeRunner(default=(1, '', 'GATE FAILED: jdbc imports flint.web without a DUB dependency\n'))
        result = dod.structural(module(), run)
        self.assertEqual(result.status, 'fail')
        self.assertIn('jdbc imports flint.web', result.messages[0])

    def test_a_failure_elsewhere_is_an_environment_error(self):
        run = FakeRunner(default=(1, '', 'GATE FAILED: webmvc: stale platform modules (FLINT-E0534)\n'))
        result = dod.structural(module(), run)
        self.assertEqual(result.status, 'error')
        self.assertIn('not this module', result.messages[1])


class Api(unittest.TestCase):
    def setUp(self):
        self.flint = Path(tempfile.mkdtemp()) / 'flint'
        self.flint.write_text('')

    def coverage(self, ids):
        return json.dumps({'ok': False, 'result': {'manifests': []},
                           'unclassified_ids': {'spring-framework@v7.1.0': ids}})

    def test_only_the_module_s_unclassified_elements_count(self):
        run = FakeRunner((['headers'], (0, json.dumps({'ok': True, 'files': 3, 'ported': 2, 'problems': 0}), '')),
                         (['coverage'], (1, self.coverage(['org.springframework.jdbc.core.JdbcTemplate#queryForStream()',
                                                           'org.springframework.web.client.RestClient']), '')))
        result = dod.api(module(), run, self.flint)
        self.assertEqual(result.status, 'fail')
        self.assertEqual(result.details['unclassified'], 1)
        self.assertIn('  org.springframework.jdbc.core.JdbcTemplate#queryForStream()', result.messages)
        self.assertFalse(any('RestClient' in m for m in result.messages))
        self.assertIn('api/framework/mapping.json', result.messages[-1])

    def test_another_module_s_gaps_do_not_fail_this_one(self):
        run = FakeRunner((['headers'], (0, json.dumps({'ok': True}), '')),
                         (['coverage'], (1, self.coverage(['org.springframework.web.client.RestClient']), '')))
        self.assertEqual(dod.api(module(), run, self.flint).status, 'pass')

    def test_header_problems_name_the_file(self):
        bad = {'ok': False, 'diagnostics': [{'severity': 'error', 'file': 'framework/jdbc/source/flint/jdbc/x.d',
                                             'message': 'no "Modified by the Flint authors"'}]}
        run = FakeRunner((['headers'], (1, json.dumps(bad), '')), (['coverage'], (0, self.coverage([]), '')))
        result = dod.api(module(), run, self.flint)
        self.assertEqual(result.status, 'fail')
        self.assertIn('framework/jdbc/source/flint/jdbc/x.d', result.messages[1])

    def test_another_build_module_s_types_are_not_the_module_s(self):
        web = dod.resolve('framework/web')
        self.assertEqual(web.upstream_modules, ['spring-web'])
        run = FakeRunner((['headers'], (0, json.dumps({'ok': True}), '')),
                         (['coverage'], (1, self.coverage(['org.springframework.web.reactive.DispatcherHandler',
                                                           'org.springframework.web.client.RestClient#nope()']), '')))
        result = dod.api(web, run, self.flint)
        self.assertEqual(result.details['unclassified'], 1)
        self.assertIn('  org.springframework.web.client.RestClient#nope()', result.messages)

    def test_no_json_is_an_environment_error(self):
        run = FakeRunner(default=(1, '', 'Segmentation fault'))
        self.assertEqual(dod.api(module(), run, self.flint).status, 'error')

    def test_a_missing_flint_is_an_environment_error(self):
        self.assertEqual(dod.api(module(), FakeRunner(), self.flint.parent / 'nope').status, 'error')


class Tests(unittest.TestCase):
    def test_both_compilers_and_the_record_s_test_packages_run(self):
        run = FakeRunner()
        result = dod.tests(module(name='webmvc'), run, {'test_packages': [':webmvc', ':framework-test']})
        self.assertEqual(result.status, 'pass')
        self.assertEqual([c[2:4] for c in run.calls], [[':webmvc', '--compiler=dmd'], [':webmvc', '--compiler=ldc2'],
                                                       [':framework-test', '--compiler=dmd'],
                                                       [':framework-test', '--compiler=ldc2']])

    def test_test_binaries_build_outside_the_module_in_a_private_temp_directory(self):
        run = FakeRunner()
        dod.tests(module(name='security-core'), run)
        self.assertTrue(all('--temp-build' in c for c in run.calls))
        self.assertEqual({e['TMPDIR'] for e in run.envs}, {str(ROOT / '.flint' / 'definition-of-done' / 'security-core')})

    def test_a_failing_compiler_names_the_command(self):
        run = FakeRunner((['--compiler=ldc2'], (1, 'core.exception.AssertError@x.d(9): unittest failure\n', '')))
        result = dod.tests(module(), run)
        self.assertEqual(result.status, 'fail')
        self.assertIn('`dub test :jdbc --compiler=ldc2 --build=unittest` failed (exit 1):', result.messages)

    def test_missing_natives_are_an_environment_error(self):
        run = FakeRunner(default=(2, '', 'Error: the pinned llhttp provider is unavailable\n'))
        self.assertEqual(dod.tests(module(), run).status, 'error')


SINGLE = '''/++
Ported from spring-projects/spring-framework v7.1.0,
spring-jdbc/src/test/java/org/springframework/jdbc/support/JdbcUtilsTests.java.
Modified by the Flint authors.
+/
module flint.jdbc.jdbc_utils_tests;

@("commonDatabaseName")
unittest {}

@("lookupColumnName") @safe
unittest {}

@("a reused statement keeps its text")  // Flint's own
unittest {}
'''

MULTI = '''// Ported from spring-framework v7.1.0: spring-jdbc/src/test/java/org/springframework/jdbc/core/AlphaTests.java
// Ported from spring-framework v7.1.0: spring-jdbc/src/test/java/org/springframework/jdbc/core/BetaTests.java
@("AlphaTests.one")  // gh-1
unittest {}
@("BetaTests.two")
nothrow unittest {}
@("BetaTests.three")
void notATest() {}
'''


class UpstreamTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        tests = self.root / 'framework' / 'jdbc' / 'tests'
        tests.mkdir(parents=True)
        (tests / 'single.d').write_text(SINGLE)
        (tests / 'multi.d').write_text(MULTI)
        (self.root / 'policy').mkdir()
        (self.root / 'policy' / 'framework.json').write_text(json.dumps({'modules': {
            'jdbc': {'module': 'flint.jdbc', 'upstream': 'spring-framework@v7.1.0', 'directory': 'framework/jdbc'},
            'web': {'module': 'flint.web', 'upstream': 'spring-framework@v7.1.0', 'directory': 'framework/web'}}}))
        (self.root / 'api').mkdir()
        (self.root / 'api' / 'upstreams.json').write_text(json.dumps({'upstreams': [
            {'project': 'spring-framework', 'version': 'v7.1.0', 'repo': 'framework', 'format': 'tar.gz'}]}))
        self.cache = self.root / 'cache'
        dod._OWNERSHIP.pop(self.root, None)

    def inventory(self, *classes):
        for cls in classes:
            path = self.cache / 'spring-framework-v7.1.0' / 'spring-jdbc' / 'src' / 'test' / 'java' / cls
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('class X { @Test void t() {} }')

    def test_drafting_reads_headers_and_names(self):
        record = dod.draft(module(), self.root)
        classes = record['classes']
        self.assertEqual(classes['org/springframework/jdbc/support/JdbcUtilsTests.java']['methods']['ported'],
                         ['commonDatabaseName', 'lookupColumnName'])
        self.assertEqual(classes['org/springframework/jdbc/core/AlphaTests.java']['methods']['ported'], ['one'])
        self.assertEqual(classes['org/springframework/jdbc/core/BetaTests.java']['methods']['ported'], ['two'])
        self.assertTrue((self.root / 'framework' / 'jdbc' / 'upstream-tests.json').is_file())

    def test_a_class_ported_across_files_lists_every_file(self):
        (self.root / 'framework' / 'jdbc' / 'tests' / 'more.d').write_text(
            '// Ported from spring-framework v7.1.0: spring-jdbc/src/test/java/org/springframework/jdbc/core/AlphaTests.java\n'
            '// Ported from spring-framework v7.1.0: spring-jdbc/src/test/java/org/springframework/jdbc/core/GammaTests.java\n'
            '@("AlphaTests.four")\nunittest {}\n')
        record = dod.draft(module(), self.root)
        alpha = record['classes']['org/springframework/jdbc/core/AlphaTests.java']
        self.assertEqual(alpha['d'], ['framework/jdbc/tests/more.d', 'framework/jdbc/tests/multi.d'])
        self.assertEqual(alpha['methods']['ported'], ['four', 'one'])
        self.assertEqual(dod.check_upstream_tests(module(), record, self.root), [])

    def test_a_drafted_record_checks_clean_against_its_inventory(self):
        dod.draft(module(), self.root)
        self.inventory('org/springframework/jdbc/support/JdbcUtilsTests.java',
                       'org/springframework/jdbc/core/AlphaTests.java', 'org/springframework/jdbc/core/BetaTests.java')
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(result.details['methods_ported'], 4)
        self.assertEqual(result.details['inventory'], 3)

    def test_an_uncovered_upstream_class_fails(self):
        dod.draft(module(), self.root)
        self.inventory('org/springframework/jdbc/support/JdbcUtilsTests.java',
                       'org/springframework/jdbc/core/AlphaTests.java', 'org/springframework/jdbc/core/BetaTests.java',
                       'org/springframework/jdbc/core/JdbcTemplateTests.java',
                       'org/springframework/web/OtherModuleTests.java')
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'fail')
        self.assertIn('  org/springframework/jdbc/core/JdbcTemplateTests.java', result.messages)
        self.assertFalse(any('OtherModuleTests' in m for m in result.messages))

    def test_tests_are_found_by_annotation_not_name(self):
        base = self.cache / 'spring-framework-v7.1.0' / 'spring-jdbc' / 'src' / 'test' / 'java' / 'org' / 'springframework' / 'jdbc'
        base.mkdir(parents=True, exist_ok=True)
        (base / 'TestNamingStrategyStd.java').write_text('class TestNamingStrategyStd { @ParameterizedTest void p() {} }')
        (base / 'AbstractJdbcHelper.java').write_text('public abstract class AbstractJdbcHelper { @Test void t() {} }')
        (base / 'InheritingTests.java').write_text('class InheritingTests extends AbstractJdbcHelper { }')  # by name
        (base / 'FixtureSupport.java').write_text('class FixtureSupport { }')
        (base / 'RowTests.java').write_text('class RowTests { @Test void t() {} }')
        (base / 'LegacyTests.java').write_text('public class LegacyTests extends TestCase { public void testOld() {} }')
        (base / 'SuiteTests.java').write_text('public class SuiteTests { public static Test suite() { return null; } }')
        self.assertEqual(dod.upstream_inventory(module(), self.root, [self.cache]), [
            'org/springframework/jdbc/InheritingTests.java', 'org/springframework/jdbc/LegacyTests.java',
            'org/springframework/jdbc/RowTests.java',
            'org/springframework/jdbc/SuiteTests.java', 'org/springframework/jdbc/TestNamingStrategyStd.java'])

    def test_the_inventory_keeps_to_the_module_s_build_modules(self):
        dod.draft(module(), self.root)
        self.inventory('org/springframework/jdbc/support/JdbcUtilsTests.java',
                       'org/springframework/jdbc/core/AlphaTests.java', 'org/springframework/jdbc/core/BetaTests.java')
        stray = self.cache / 'spring-framework-v7.1.0' / 'spring-other' / 'src' / 'test' / 'java' / 'org' / \
            'springframework' / 'jdbc' / 'core' / 'StrayTests.java'
        stray.parent.mkdir(parents=True)
        stray.write_text('class X { @Test void t() {} }')
        self.assertIn('org/springframework/jdbc/core/StrayTests.java',
                      dod.upstream_inventory(module(), self.root, [self.cache]))
        narrowed = dod.upstream_inventory(module(upstream_modules=['spring-jdbc']), self.root, [self.cache])
        self.assertEqual(len(narrowed), 3)
        (self.root / 'framework' / 'jdbc' / 'tests' / 'x.d').write_text(
            '// Ported from spring-projects/spring-framework v7.1.0: spring-jdbc/src/main/java/org/x/Y.java\n'
            '// Ported from spring-projects/spring-boot v4.2.0: core/spring-boot/src/main/java/org/x/Z.java\n')
        self.assertEqual(dod.upstream_modules(module(), self.root), ['spring-jdbc'])

    def test_no_fetched_upstream_is_an_environment_error(self):
        dod.draft(module(), self.root)
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'error')
        self.assertIn('flint api fetch --tests', result.messages[0])

    def test_each_inconsistency_is_named(self):
        record = {'schema': dod.SCHEMA, 'classes': {
            'org/springframework/jdbc/core/AlphaTests.java': {'status': 'ported', 'd': 'framework/jdbc/tests/multi.d',
                                                             'methods': {'ported': ['one', 'missing']}},
            'org/springframework/jdbc/core/BetaTests.java': {'status': 'partial', 'd': 'framework/jdbc/tests/multi.d',
                                                            'methods': {'ported': ['two', 'three']}},
            'org/springframework/jdbc/core/GammaTests.java': {'status': 'excluded'},
            'org/springframework/jdbc/core/DeltaTests.java': {'status': 'ported', 'd': 'framework/jdbc/tests/gone.d'},
            'org/springframework/jdbc/core/EpsilonTests.java': {'status': 'partial', 'd': 'framework/jdbc/tests/multi.d',
                                                               'methods': {'skipped': {'x': ''}}},
            'org/springframework/jdbc/core/ZetaTests.java': {'status': 'todo'}}}
        text = '\n'.join(dod.check_upstream_tests(module(), record, self.root))
        self.assertIn('AlphaTests.java: ported method missing has no `@("AlphaTests.missing") unittest`', text)
        self.assertIn('BetaTests.java: ported method three', text)  # @("BetaTests.three") is not on a unittest
        self.assertIn('BetaTests.java: "partial", but', text)
        self.assertIn('GammaTests.java: excluded without a "reason"', text)
        self.assertIn("DeltaTests.java: its D file 'framework/jdbc/tests/gone.d' does not exist", text)
        self.assertIn('EpsilonTests.java: skipped method x has no reason', text)
        self.assertIn("ZetaTests.java: \"status\" must be ported, partial, excluded or deferred, not 'todo'", text)

    INVENTORY = ('org/springframework/jdbc/support/JdbcUtilsTests.java', 'org/springframework/jdbc/core/AlphaTests.java',
                 'org/springframework/jdbc/core/BetaTests.java', 'org/springframework/jdbc/core/JdbcTemplateTests.java',
                 'org/springframework/jdbc/core/KappaTests.java')

    def seeded(self):
        self.inventory(*self.INVENTORY)
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache], seed_phase='2')
        record = json.loads((self.root / 'framework' / 'jdbc' / 'upstream-tests.json').read_text())
        return result, record

    def save(self, record):
        (self.root / 'framework' / 'jdbc' / 'upstream-tests.json').write_text(json.dumps(record))

    def test_seeding_defers_only_the_unrecorded_classes_and_passes(self):
        result, record = self.seeded()
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(result.details['deferred'], 2)
        self.assertEqual(record['classes']['org/springframework/jdbc/core/KappaTests.java'],
                         {'status': 'deferred', 'phase': '2'})
        self.assertEqual(record['classes']['org/springframework/jdbc/core/AlphaTests.java']['status'], 'ported')
        baseline = json.loads((self.root / dod.DEFERRED_BASELINE).read_text())['modules']
        self.assertEqual(baseline, {'jdbc': ['org/springframework/jdbc/core/JdbcTemplateTests.java',
                                             'org/springframework/jdbc/core/KappaTests.java']})

    def test_a_class_another_module_ports_is_seeded_as_ported_not_deferred(self):
        entry = {'status': 'ported', 'd': 'framework/jdbc/tests/single.d', 'methods': {'ported': ['commonDatabaseName']},
                 'note': 'ported in framework-test'}
        original = dod.ported_elsewhere
        dod.ported_elsewhere = lambda module, root=ROOT: {'org/springframework/jdbc/core/KappaTests.java': entry}
        try:
            result, record = self.seeded()
        finally:
            dod.ported_elsewhere = original
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(record['classes']['org/springframework/jdbc/core/KappaTests.java'], entry)
        self.assertEqual(result.details['deferred'], 1)

    def test_seeding_never_changes_a_recorded_entry(self):
        dod.draft(module(), self.root)
        path = self.root / 'framework' / 'jdbc' / 'upstream-tests.json'
        record = json.loads(path.read_text())
        record['classes']['org/springframework/jdbc/core/KappaTests.java'] = {'status': 'excluded', 'reason': 'R12'}
        path.write_text(json.dumps(record))
        _, seeded = self.seeded()
        self.assertEqual(seeded['classes']['org/springframework/jdbc/core/KappaTests.java'],
                         {'status': 'excluded', 'reason': 'R12'})

    def test_deferred_fails_under_release(self):
        self.seeded()
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache], release=True)
        self.assertEqual(result.status, 'fail')
        self.assertIn('2 upstream test classes are deferred; a release ports or excludes each:', result.messages)

    def test_a_new_deferral_fails_the_ratchet(self):
        _, record = self.seeded()
        record['classes']['org/springframework/jdbc/core/AlphaTests.java'] = {'status': 'deferred', 'phase': '2'}
        self.save(record)
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'fail')
        self.assertIn('  org/springframework/jdbc/core/AlphaTests.java', result.messages)
        self.assertIn('deferrals only shrink', result.messages[0])

    def test_a_resolved_deferral_fails_until_the_baseline_shrinks(self):
        _, record = self.seeded()
        record['classes']['org/springframework/jdbc/core/KappaTests.java'] = {'status': 'excluded', 'reason': 'R12'}
        self.save(record)
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertIn('--shrink-upstream-tests', result.messages[0])
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache], shrink_baseline=True)
        self.assertEqual(result.status, 'pass', result.messages)
        baseline = json.loads((self.root / dod.DEFERRED_BASELINE).read_text())['modules']
        self.assertEqual(baseline, {'jdbc': ['org/springframework/jdbc/core/JdbcTemplateTests.java']})

    def test_a_deferral_needs_its_phase(self):
        record = {'schema': dod.SCHEMA, 'classes': {'org/springframework/jdbc/core/KappaTests.java': {'status': 'deferred'}}}
        self.assertIn('org/springframework/jdbc/core/KappaTests.java: deferred without "phase": "2" or "3"',
                      dod.check_upstream_tests(module(), record, self.root))

    def test_without_pinned_test_sources_the_record_alone_is_checked(self):
        dod.draft(module(), self.root)
        result = dod.upstream_tests(module(upstream='jackson-core@3.1.8'), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(result.details['inventory'], 'none: no test sources are pinned')

    def pin_openjdk(self, signatures_only=True, licence_use=None, test_archive=False):
        pins = json.loads((self.root / 'api' / 'upstreams.json').read_text())
        pins['upstreams'].append({'project': 'openjdk', 'version': '21.0.13', 'repo': 'framework', 'format': 'tar.gz',
                                  **({'signatures_only': True} if signatures_only else {})})
        (self.root / 'api' / 'upstreams.json').write_text(json.dumps(pins))
        if licence_use:
            (self.root / 'policy' / 'upstream-licences.json').write_text(json.dumps(
                {'projects': [{'name': 'openjdk', 'use': licence_use}]}))
        if test_archive:
            (self.root / 'api' / 'upstream-tests.json').write_text(json.dumps(
                {'archives': [{'project': 'openjdk', 'version': '21.0.13', 'tests': 'src/test/java'}]}))
        # A fetched copy with test classes, which must never be demanded of a clean-room module.
        jtreg = self.cache / 'openjdk-21.0.13' / 'jdk' / 'src' / 'test' / 'java' / 'org' / 'springframework' / 'jdbc'
        jtreg.mkdir(parents=True)
        (jtreg / 'ConcurrentTests.java').write_text('class X { @Test void t() {} }')
        return module(name='jdbc', upstream='openjdk@21.0.13')

    def test_a_signatures_only_upstream_demands_no_upstream_tests(self):
        jdk = self.pin_openjdk()
        result = dod.upstream_tests(jdk, root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'skip')
        self.assertIn('clean-room', result.messages[0])
        self.assertIsNone(dod.upstream_inventory(jdk, self.root, [self.cache]))

    def test_a_clean_room_module_s_own_record_is_still_checked(self):
        jdk = self.pin_openjdk(signatures_only=False, licence_use='clean-room')
        dod.draft(jdk, self.root)  # its original tests
        result = dod.upstream_tests(jdk, root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(result.details['inventory'], 'none: clean-room upstream')
        path = self.root / 'framework' / 'jdbc' / 'upstream-tests.json'
        record = json.loads(path.read_text())
        record['classes']['org/apache/harmony/tests/java/util/ArrayListTest.java'] = {'status': 'excluded'}
        path.write_text(json.dumps(record))
        self.assertEqual(dod.upstream_tests(jdk, root=self.root, caches=[self.cache]).status, 'fail')

    def test_openjdk_jtreg_tests_are_inventoried_and_plain_gpl_ones_need_a_covering_flint_test(self):
        jdk = self.pin_openjdk(signatures_only=False, licence_use='gpl-ce-module')
        jtreg = self.cache / 'openjdk-21.0.13' / 'test' / 'jdk'
        (jtreg / 'java' / 'sql' / 'Timestamp').mkdir(parents=True)
        (jtreg / 'java' / 'sql' / 'Timestamp' / 'TimestampTests.java').write_text('/* @test */ class T {}')
        (jtreg / 'java' / 'sql' / 'Timestamp' / 'Helper.java').write_text('class Helper {}')  # no @test
        (jtreg / 'java' / 'sql' / 'testng').mkdir(parents=True)
        (jtreg / 'java' / 'sql' / 'testng' / 'DateTests.java').write_text('class D { @Test public void t() {} }')
        (jtreg / 'java' / 'net' / 'URL').mkdir(parents=True)
        (jtreg / 'java' / 'net' / 'URL' / 'Equals.java').write_text('/* @test */ class E {}')  # owned elsewhere
        (jtreg / 'java' / 'awt' / 'Frame').mkdir(parents=True)
        (jtreg / 'java' / 'awt' / 'Frame' / 'Show.java').write_text('/* @test */ class S {}')  # java.desktop: no scope
        (self.root / 'api' / 'upstream').mkdir(parents=True, exist_ok=True)
        (self.root / 'api' / 'upstream' / 'openjdk-21.0.13.json').write_text(json.dumps({'types': [
            {'id': 'java.sql.Timestamp', 'package': 'java.sql'}, {'id': 'java.net.URL', 'package': 'java.net'}]}))
        dod._OWNERSHIP[self.root] = {'java.sql': 'jdbc', 'java.awt': 'jdbc'}
        self.assertEqual(dod.upstream_inventory(jdk, self.root, [self.cache]),
                         ['java/sql/Timestamp/TimestampTests.java', 'java/sql/testng/DateTests.java'])
        dod._OWNERSHIP[self.root] = {'java.sql': 'jdbc'}
        self.addCleanup(dod._OWNERSHIP.pop, self.root, None)
        self.assertEqual(dod.upstream_inventory(jdk, self.root, [self.cache]),
                         ['java/sql/Timestamp/TimestampTests.java', 'java/sql/testng/DateTests.java'])
        record = {'schema': dod.SCHEMA, 'classes': {'java/sql/Timestamp/TimestampTests.java': {
            'status': 'excluded', 'reason': 'plain-gpl: GPL-2.0 without the Classpath Exception'}}}
        problems = dod.check_upstream_tests(jdk, record, self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn('needs "covered_by"', problems[0])
        flint_test = self.root / 'framework' / 'jdbc' / 'tests' / 'timestamp_test.d'
        flint_test.parent.mkdir(parents=True, exist_ok=True)
        flint_test.write_text('module t;\n')
        record['classes']['java/sql/Timestamp/TimestampTests.java']['covered_by'] = 'framework/jdbc/tests/timestamp_test.d'
        self.assertEqual(dod.check_upstream_tests(jdk, record, self.root), [])

    def test_module_files_skip_build_output_only_below_the_checkout(self):
        nested = self.root / '.flint' / 'checkout'
        (nested / 'framework' / 'beans' / 'source').mkdir(parents=True)
        (nested / 'framework' / 'beans' / 'source' / 'a.d').write_text('module a;')
        (nested / 'framework' / 'beans' / '.dub').mkdir(parents=True)
        (nested / 'framework' / 'beans' / '.dub' / 'gen.d').write_text('module gen;')
        found = dod.module_files(module(name='beans', directory='framework/beans', roots=['framework/beans']), nested)
        self.assertEqual([p.name for p in found], ['a.d'])

    def test_an_openjdk_port_owns_the_java_packages_its_d_modules_name(self):
        policy = self.root / 'policy' / 'framework.json'
        policy.parent.mkdir(parents=True, exist_ok=True)
        saved = policy.read_text() if policy.is_file() else None
        self.addCleanup(lambda: policy.write_text(saved) if saved is not None else policy.unlink())
        policy.write_text(json.dumps({'modules': {
            'java': {'directory': 'framework/java', 'module': 'flint.java', 'also': ['flint.javax'],
                     'upstream': 'openjdk@21.0.13'},
            'java-util': {'directory': 'framework/java-util', 'module': 'flint.java.util.uuid',
                          'also': ['flint.java.util'], 'upstream': 'openjdk@21.0.13'},
            'web': {'directory': 'framework/web', 'module': 'flint.web', 'upstream': 'spring-framework@v7.1.0'}}}))
        dod._OWNERSHIP.pop(self.root, None)
        self.addCleanup(dod._OWNERSHIP.pop, self.root, None)
        table = dod.ownership(self.root)
        self.assertEqual(dod.owner('java/lang/String/Chars', table), 'java')         # no mapped element needed
        self.assertEqual(dod.owner('java/util/HashMap/KeySetRemove', table), 'java-util')  # longest prefix wins
        self.assertEqual(dod.owner('javax/net/ssl/X', table), 'java')
        self.assertEqual(dod.owner('org/springframework/web/X', table), 'web')

    def test_an_upstream_without_pinned_tests_and_no_record_skips(self):
        result = dod.upstream_tests(module(upstream='jackson-core@3.1.8'), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'skip')
        self.assertIn('no test sources are pinned for jackson-core@3.1.8', result.messages[0])

    def test_an_explicit_test_archive_still_counts_for_a_clean_room_project(self):
        jdk = self.pin_openjdk(test_archive=True)
        self.assertTrue(dod.test_sources_pinned(jdk, self.root))

    def test_a_missing_record_fails_with_the_drafting_command(self):
        result = dod.upstream_tests(module(), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'fail')
        self.assertIn('--write-upstream-tests', result.messages[1])

    def test_a_module_with_no_pinned_upstream_skips(self):
        result = dod.upstream_tests(module(upstream='Flint AOT contract'), root=self.root, caches=[self.cache])
        self.assertEqual(result.status, 'skip')


class Budgets(unittest.TestCase):
    def sizes(self, linked, templates):
        def write(argv):
            Path(argv[argv.index('--output') + 1]).write_text(json.dumps({'framework': {'jdbc': {
                'incremental_linked_bytes': linked, 'template_instances': templates}}}))
            return 0, '', ''
        return FakeRunner((['--framework-sizes'], write))

    def test_within_budget_passes_and_reports_the_provisional_keys(self):
        result = dod.budgets(module(), self.sizes(999, 100))
        self.assertEqual(result.status, 'pass')
        self.assertEqual(result.details['provisional, not gated'], ['ldc_cold_seconds'])

    def test_a_miss_is_a_blocker(self):
        result = dod.budgets(module(), self.sizes(1001, 100))
        self.assertEqual(result.status, 'fail')
        self.assertIn('incremental_linked_bytes 1001 exceeds the budget 1000', result.messages[0])

    def test_a_module_without_a_probe_fails(self):
        run = FakeRunner((['--framework-sizes'], lambda argv: (Path(argv[argv.index('--output') + 1]).write_text(
            json.dumps({'framework': {}})), 0, '', '')[1:]))
        self.assertIn('"bench" entry', dod.budgets(module(), run).messages[0])

    def test_engine_packages_skip_rather_than_pass(self):
        self.assertEqual(dod.budgets(module(kind='package'), FakeRunner()).status, 'skip')


class Apps(unittest.TestCase):
    def setUp(self):
        self.flint = Path(tempfile.mkdtemp()) / 'flint'
        self.flint.write_text('')

    def test_without_flint_budget_its_part_is_skipped_not_passed(self):
        run = FakeRunner((['budget', '--help'], (1, '', 'unknown command budget')))
        result = dod.applications(module(), run, 'petclinic-rest', self.flint)
        self.assertEqual(result.status, 'pass')
        self.assertTrue(result.details['petclinic-rest flint budget'].startswith('skip'))
        self.assertIn(['-C', 'benchmarks/spring/flint/petclinic-rest', '--compiler', 'both', '--verify'],
                      [c[2:] for c in run.calls])

    def test_a_flint_budget_regression_fails_the_step(self):
        run = FakeRunner((['budget', '--app'], (1, '', 'petclinic-rest: GET /owners: 74 allocations against a budget of 70')))
        result = dod.applications(module(), run, 'petclinic-rest', self.flint)
        self.assertEqual(result.status, 'fail')
        self.assertIn('  petclinic-rest: GET /owners: 74 allocations against a budget of 70', result.messages)

    def test_flint_budget_off_its_runner_class_is_a_skip(self):
        message = "petclinic-rest: budgets recorded on 'posidon-i7-11700K'; this runner is 'venus-x'"
        run = FakeRunner((['budget', '--app'], (1, message + '\n', '')))
        result = dod.applications(module(), run, 'petclinic-rest', self.flint)
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertTrue(result.details['petclinic-rest flint budget'].startswith('skip: not the budget runner class'))
        self.assertIn(['budget', '--app', 'petclinic-rest'], [c[1:] for c in run.calls])

    def test_a_failing_golden_suite_fails_the_step(self):
        run = FakeRunner((['accept'], (1, 'GET /owners/1: status 500, expected 200', '')))
        result = dod.applications(module(), run, 'petclinic-rest', self.flint)
        self.assertIn('petclinic-rest: the golden suite fails in exact mode (benchmarks/spring/suites):',
                      result.messages)

    def fake_database(self, opened):
        import contextlib

        @contextlib.contextmanager
        def cluster(app, root=ROOT):
            opened.append(app)
            yield (lambda: {'POSTGRES_URL': f'jdbc:postgresql://127.0.0.1:5999/{app}'}) if app == 'petclinic-rest' else dict
        return cluster

    def test_petclinic_gets_a_disposable_database_and_both_ci_configurations(self):
        opened = []
        original, dod.app_database = dod.app_database, self.fake_database(opened)
        try:
            run = FakeRunner((['budget', '--help'], (1, '', '')))
            result = dod.applications(module(), run, 'petclinic-rest,gs-rest-service', self.flint)
        finally:
            dod.app_database = original
        self.assertEqual(result.status, 'pass', result.messages)
        self.assertEqual(opened, ['petclinic-rest', 'gs-rest-service'])
        tests = [(c[3], e) for c, e in zip(run.calls, run.envs) if c[1] == 'test']
        self.assertEqual([(app.rsplit('/', 1)[-1], e.get('POSTGRES_URL', '-'), e.get('FLINT_GC_STATIC_VERIFY', '-'))
                          for app, e in tests],
                         [('petclinic-rest', 'jdbc:postgresql://127.0.0.1:5999/petclinic-rest', '-'),
                          ('petclinic-rest', 'jdbc:postgresql://127.0.0.1:5999/petclinic-rest', '0'),
                          ('gs-rest-service', '-', '-'), ('gs-rest-service', '-', '0')])

    def test_only_petclinic_needs_postgresql(self):
        self.assertEqual(dod.postgres_apps(), {'petclinic-rest'})

    def test_a_missing_postgresql_peer_is_an_environment_error(self):
        def missing(app, root=ROOT):
            raise dod.DatabaseUnavailable('PostgreSQL 18.7 is missing; install it with python3 tools/install_peers.py')
        original, dod.app_database = dod.app_database, missing
        try:
            result = dod.applications(module(), FakeRunner(), 'petclinic-rest', self.flint)
        finally:
            dod.app_database = original
        self.assertEqual(result.status, 'error')
        self.assertIn('install_peers.py', result.messages[0])

    def test_a_postmaster_pg_ctl_left_running_is_stopped_by_pid(self):
        import spring_bench
        data = Path(tempfile.mkdtemp())
        server = subprocess.Popen(['sleep', '60'])
        (data / 'postmaster.pid').write_text(f'{server.pid}\n{data}\n')
        spring_bench.stop_postmaster(data, grace=0.2)
        self.assertEqual(server.wait(timeout=5), -15)

    def test_no_flint_budget_skips_it_on_a_verifier_without_budgets(self):
        run = FakeRunner()
        result = dod.applications(module(), run, 'gs-rest-service', self.flint, budget=False)
        self.assertFalse(any('budget' in c for c in run.calls))
        self.assertIn('--no-flint-budget', result.details['gs-rest-service flint budget'])

    def test_none_skips(self):
        self.assertEqual(dod.applications(module(), FakeRunner(), 'none', self.flint).status, 'skip')


FAKE_DFMT = '''#!/usr/bin/env python3
import sys
if '--version' in sys.argv: print('v0.15.2+flint.stack-udas'); sys.exit(0)
text = open(sys.argv[-1]).read()
sys.stdout.write(text.replace('UNFORMATTED', 'formatted'))
'''
FAKE_DSCANNER = '''#!/usr/bin/env python3
import json, sys
issues = []
for name in [a for a in sys.argv[1:] if a.endswith('.d')]:
    for number, line in enumerate(open(name), 1):
        if 'WARN' in line:
            issues.append({'type': 'warn', 'key': 'dscanner.fake', 'fileName': name, 'line': number,
                           'message': 'fake finding on line %d' % number})
print(json.dumps({'issues': issues}))
'''


class QualityRatchet(unittest.TestCase):
    """quality.py --baseline: inherited findings pass, new ones fail, and the baseline only shrinks."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.tree = self.dir / 'tree'
        self.tree.mkdir()
        for name, text in (('dfmt', FAKE_DFMT), ('dscanner', FAKE_DSCANNER)):
            (self.dir / name).write_text(text)
            (self.dir / name).chmod(0o755)
        self.baseline = self.dir / 'baseline.json'
        (self.tree / 'a.d').write_text('module a;\n// WARN one\n// WARN two\n')
        (self.tree / 'b.d').write_text('module b; // UNFORMATTED\n')

    def quality(self, *extra):
        return subprocess.run([sys.executable, str(ROOT / 'tools' / 'quality.py'), '--dfmt', str(self.dir / 'dfmt'),
                               '--dscanner', str(self.dir / 'dscanner'), '--path', str(self.tree),
                               '--baseline', str(self.baseline), *extra], capture_output=True, text=True)

    def recorded(self):
        return {f: v for tree in json.loads(self.baseline.read_text())['trees'].values() for f, v in tree.items()}

    def test_without_a_baseline_entry_every_finding_fails(self):
        done = self.quality()
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('fake finding on line 2', done.stderr)
        self.assertIn('b.d: formatter difference', done.stderr)

    def test_recorded_findings_pass_even_when_lines_move(self):
        self.assertEqual(self.quality('--record-baseline').returncode, 0)
        (self.tree / 'a.d').write_text('module a;\n\n\n// WARN one\n// WARN two\n')
        done = self.quality()
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_a_new_finding_fails_alone(self):
        self.quality('--record-baseline')
        (self.tree / 'a.d').write_text('module a;\n// WARN one\n// WARN two\n// WARN three\n')
        (self.tree / 'c.d').write_text('module c; // UNFORMATTED\n')
        done = self.quality()
        self.assertNotEqual(done.returncode, 0)
        failures = [line for line in done.stderr.splitlines() if line.strip()]
        self.assertEqual(len(failures), 2, failures)
        self.assertTrue(any(line.endswith('a.d:4: fake finding on line 4') for line in failures), failures)
        self.assertTrue(any(line.endswith('c.d: formatter difference') for line in failures), failures)

    def test_a_fixed_finding_fails_until_the_baseline_shrinks_and_shrinking_never_adds(self):
        self.quality('--record-baseline')
        (self.tree / 'a.d').write_text('module a;\n// WARN one\n')
        (self.tree / 'b.d').write_text('module b; // WARN new\n')
        done = self.quality()
        self.assertIn('1 of 2 baseline finding(s) "dscanner.fake: fake finding on line #" are gone', done.stderr)
        self.assertIn('--shrink-baseline', done.stderr)
        self.assertEqual(self.quality('--shrink-baseline').returncode, 0)
        counts = self.recorded()
        self.assertEqual([v for f, v in counts.items() if f.endswith('a.d')], [{'dscanner.fake: fake finding on line #': 1}])
        self.assertFalse(any(f.endswith('b.d') for f in counts), counts)  # its dfmt entry is gone, its new WARN not added
        self.assertIn('b.d:1: fake finding on line 1', self.quality().stderr)

    def test_the_step_runs_against_the_committed_baseline(self):
        run = FakeRunner()
        self.assertEqual(dod.quality(module(), run).status, 'pass')
        self.assertEqual(run.calls[0][-2:], ['--baseline', 'policy/quality-baseline.json'])


class Command(unittest.TestCase):
    def test_exit_status_orders_fail_over_error(self):
        R = dod.Result
        self.assertEqual(dod.exit_status([R('a', 'pass'), R('b', 'skip')]), 0)
        self.assertEqual(dod.exit_status([R('a', 'error'), R('b', 'pass')]), 2)
        self.assertEqual(dod.exit_status([R('a', 'error'), R('b', 'fail')]), 1)

    def test_gates_py_dispatches_and_reports(self):
        done = subprocess.run([sys.executable, str(ROOT / 'tools' / 'gates.py'), '--module', 'framework/jdbc',
                               '--definition-of-done', '--step', 'resolve', '--no-hold', '--json'],
                              cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        out = json.loads(done.stdout)
        self.assertEqual((out['schema'], out['module'], out['done']), ('flint.definition-of-done/1', 'jdbc', True))
        self.assertEqual(out['steps'][0]['details']['java_packages'], ['org.springframework.jdbc'])

    def test_an_unregistered_module_exits_1_with_its_fix(self):
        done = subprocess.run([sys.executable, str(ROOT / 'tools' / 'gates.py'), '--module', 'framework/nonesuch',
                               '--definition-of-done', '--no-hold'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn('FLINT-E0535', done.stdout)
        self.assertIn('NOT DONE: framework/nonesuch', done.stdout)

    def test_the_structural_gate_is_unchanged(self):
        done = subprocess.run([sys.executable, str(ROOT / 'tools' / 'gates.py'), '--help'], cwd=ROOT,
                              capture_output=True, text=True)
        self.assertIn('--gate', done.stdout)


if __name__ == '__main__':
    unittest.main()
