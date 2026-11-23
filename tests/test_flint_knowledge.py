"""flint docs, examples, generate and AGENTS.md (Milestone 9, ADR-027)."""
import json
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, codes, environment, flint, flint_json, setUpModule  # noqa: F401

# Web and data applications link the native providers through the workspace recipes' generated blocks.
NATIVE_LINKED = 'BEGIN FLINT NATIVE' in (ROOT / 'packages/engine-web/dub.sdl').read_text()

WIRING = '''module shop.order.wiring_test;

import shop.order.controller : OrderController;
import shop.order.properties : OrderProperties;
import shop.order.repository : OrderBindings;
import shop.order.service : OrderService;
import flint.config : ConfigOptions, load;
import flint.engine.di : AppContext, Provided;
import flint.engine.sql : Pool;
import flint.engine.web : ServerOptions, runApplication;

@safe:

/// The application root the generated controller registers in.
struct Application
{
    /// The generated controller.
    OrderController orders;
}

/// Compiled, never run: the framework's compile-time checks accept every generated component.
int wire(ref Pool pool)
{
    AppContext!(Provided!Pool, OrderBindings, OrderService, OrderController) context;
    if (context.provide!Pool(pool).code != 0 || context.initialize().code != 0)
        return 1;
    ConfigOptions options;
    if (!load!OrderProperties(options).ok())
        return 2;
    auto application = Application(context.get!OrderController());
    ServerOptions server;
    return runApplication!Application(application, server);
}

@("the generated components wire into the framework")
unittest
{
    static assert(is(typeof(&wire)));
}
'''


class DocsTests(unittest.TestCase):
    def test_the_index_covers_every_package(self):
        status, document = flint_json('docs')
        self.assertEqual(status, 0, document['diagnostics'])
        packages = {p['name']: p for p in document['packages']}
        self.assertEqual(len(packages), 37)
        self.assertTrue(all(not p['problem'] for p in packages.values()), [p for p in packages.values() if p['problem']])
        self.assertGreater(packages['engine-di']['symbols'], 10)  # re-exported from internal modules
        self.assertGreater(sum(p['symbols'] for p in packages.values()), 2000)
        self.assertGreater(sum(p['with_examples'] for p in packages.values()), 500)

    def test_an_exact_name_shows_signature_documentation_and_tested_examples(self):
        status, document = flint_json('docs', 'flint.os.run')
        self.assertEqual(status, 0, document['diagnostics'])
        symbol = document['symbols'][0]
        self.assertEqual(symbol['signature'], '@safe Result!ExitStatus run(ref scope Context context, '
                         'scope const(char[])[] argv, ProcessOptions options = ProcessOptions.init)')
        self.assertIn('Execute literal argv', symbol['comment'])
        self.assertTrue(symbol['examples'])
        example = symbol['examples'][0]
        self.assertTrue(example['file'].startswith('packages/os/tests/'))
        source = (ROOT / example['file']).read_text().splitlines()
        self.assertIn(source[example['line'] - 1].strip(), example['code'])

    def test_search_finds_templates_and_reports_misses(self):
        status, document = flint_json('docs', 'config', 'load')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(document['symbols'][0]['qualified'], 'flint.config.load')
        self.assertIn('load(T)(', document['symbols'][0]['signature'])
        status, document = flint_json('docs', 'zzqqxx-nothing')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0007']))

    def test_export_writes_llms_files(self):
        with tempfile.TemporaryDirectory() as directory:
            status, document = flint_json('docs', '--export', directory)
            self.assertEqual(status, 0, document['diagnostics'])
            summary = (Path(directory) / 'llms.txt').read_text()
            full = (Path(directory) / 'llms-full.txt').read_text()
            self.assertIn('`flint.engine.di`', summary)
            self.assertIn('### flint.os.run', full)

    def test_examples_return_tested_code(self):
        status, document = flint_json('examples', 'os', 'run')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertTrue(document['examples'])
        self.assertIn('unittest', document['examples'][0]['example']['code'])
        status, document = flint_json('examples', 'rest', 'service')
        self.assertIn('examples/golden-rest-service', document['applications'])


class GenerateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-generate-')
        status, document = flint_json('new', 'shop', cwd=cls.temporary.name)
        assert status == 0, document
        cls.project = Path(cls.temporary.name) / 'shop'

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_flint(self, *arguments):
        return flint_json(*arguments, cwd=self.project)

    def test_1_new_projects_carry_agents_md(self):
        guide = (self.project / 'AGENTS.md').read_text()
        self.assertIn('# shop: working in a Flint project', guide)
        self.assertIn('module shop.order.service;', guide)
        self.assertIn('flint docs', guide)

    def test_2_plan_writes_nothing(self):
        status, document = self.run_flint('generate', 'entity', 'Order', '--plan')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertTrue(document['plan'])
        self.assertEqual(document['files'][0]['path'], 'src/shop/order/order.d')
        self.assertIn('flint:engine-data', document['dependencies_added'])
        self.assertFalse((self.project / 'src/shop/order').exists())

    def test_3_every_generator_builds_wires_and_checks(self):
        for kind in ('entity', 'repository', 'service', 'controller', 'config', 'migration'):
            status, document = self.run_flint('generate', kind, 'Order')
            self.assertEqual(status, 0, (kind, document['diagnostics']))
        self.assertTrue((self.project / 'resources/migrations/V000001__order.sql').is_file())
        manifest = (self.project / 'flint.toml').read_text()
        for package in ('engine-data', 'engine-di', 'engine-web', 'config', 'engine-migrate', 'engine-sql'):
            self.assertIn('"flint:' + package + '"', manifest)
        status, document = self.run_flint('lock', '--check')
        self.assertEqual(status, 0, document['diagnostics'])
        status, document = self.run_flint('check')
        self.assertEqual(status, 0, document['diagnostics'])  # generated code is dfmt- and D-Scanner-clean
        status, document = self.run_flint('generate', 'entity', 'Order')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0008']))
        if NATIVE_LINKED:
            (self.project / 'test/shop/order').mkdir(parents=True, exist_ok=True)
            (self.project / 'test/shop/order/wiring_test.d').write_text(WIRING)
            status, document = self.run_flint('test')
            self.assertEqual(status, 0, document['diagnostics'])

    def test_4_bad_requests(self):
        status, document = self.run_flint('generate', 'widget', 'Order')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0003']))
        status, document = self.run_flint('generate', 'entity', 'order')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0003']))

    def test_5_generate_agents_refreshes_agents_md(self):
        (self.project / 'AGENTS.md').write_text('stale\n')
        status, document = self.run_flint('generate', 'agents')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertIn('Flint way', (self.project / 'AGENTS.md').read_text())


if __name__ == '__main__':
    unittest.main()
