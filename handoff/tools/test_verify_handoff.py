#!/usr/bin/env python3
"""Adversarial integrity fixtures: malformed files must not turn into green checks."""
from pathlib import Path
import tempfile
import unittest
from verify_handoff import load_json, yaml_documents, parse_sdl, markdown_links, d_blocks


class IntegrityFixtures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
    def tearDown(self):
        self.temporary.cleanup()
    def file(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding='utf-8')
        return path
    def test_duplicate_budget_cannot_override_original(self):
        path = self.file('budgets.json', '{"cap":100,"cap":999999}')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            load_json(path)
    def test_nonfinite_metric_is_rejected(self):
        path = self.file('metric.json', '{"value":NaN}')
        with self.assertRaisesRegex(ValueError, 'nonfinite'):
            load_json(path)
    def test_workflow_on_stays_on(self):
        path = self.file('ci.yml', 'on: [push, pull_request]\njobs:\n  check:\n    runs-on: ubuntu-latest\n')
        self.assertIn('on', yaml_documents(path)[0])
    def test_duplicate_workflow_jobs_rejected(self):
        path = self.file('ci.yml', 'on: push\njobs: {}\njobs: {}\n')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            yaml_documents(path)
    def test_sdl_nested_recipe_and_attributes(self):
        recipe = ('name "flint"\nconfiguration "release" {\n'
                  '  dflags "-O3"\n}\ndependency ":arena" version="*"\n')
        nodes = parse_sdl(recipe)
        self.assertEqual(nodes[1]['children'][0]['values'], ['-O3'])
        self.assertEqual(nodes[2]['attributes'], {'version': '*'})
    def test_sdl_comments_do_not_create_dependencies(self):
        nodes = parse_sdl('name "x" // dependency ":web"\n/* hidden */ targetType "none"\n')
        self.assertEqual([x['name'] for x in nodes], ['name', 'targetType'])
    def test_sdl_unbalanced_and_unknown_syntax_reject(self):
        for text in ['configuration "x" {\nname "x"\n', 'name "x"\n}\n', 'name "x" $bogus\n']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_sdl(text)
    def test_sdl_duplicate_attribute_reject(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            parse_sdl('dependency ":arena" version="*" version="~master"\n')
    def test_missing_and_external_local_links_reject(self):
        path = self.file('docs/a.md', '[missing](no.md)\n[outside](../../out.md)\n[web](https://example.com/a)\n')
        errors = markdown_links(path, self.root)
        self.assertEqual(len(errors), 2)
        self.assertTrue(any('leaves archive' in x for x in errors))
    def test_links_in_examples_not_treated_as_references(self):
        self.file('docs/ok.md', '# Exists\n')
        path = self.file('docs/a.md', '[valid](ok.md#exists)\n```text\n[example](missing.md)\n```\n')
        self.assertEqual(markdown_links(path, self.root), [])
    def test_only_complete_d_modules_are_extracted(self):
        path = self.file('api.md', '```d\nint x;\n```\n\n```d\nmodule demo;\n@safe: int f() { return 1; }\n```\n')
        self.assertEqual(len(list(d_blocks(path))), 1)


if __name__ == '__main__':
    unittest.main()
