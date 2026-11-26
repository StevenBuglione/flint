"""tools/api_differences.py: the generated log of every Java difference (docs/spring/java-differences.md)."""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import api_differences  # noqa: E402

RULEBOOK = """# Rulebook

## Rules

### R2: Annotations
### R4: `Class<T>` parameters

## Deviations

| ID | Deviation | Reason |
| --- | --- | --- |
| D-7 | Typed null | overloads |

## Exclusions

| Category | Examples |
| --- | --- |
| `jvm-runtime` | ClassLoader |
| `deferred` | later |
"""


def manifest(types):
    return {'schema': 'flint.api-manifest/1', 'project': 'lib', 'version': '1.0', 'types': types}


def type_(tid, members=()):
    return {'id': tid, 'package': tid.rpartition('.')[0], 'module': 'lib', 'file': 'x.java', 'kind': 'class',
            'visibility': 'public', 'members': [{'kind': 'method', 'name': m, 'signature': m + '()'} for m in members]}


class ApiDifferencesTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        (self.root / 'api' / 'upstream').mkdir(parents=True)
        (self.root / 'api' / 'r').mkdir()
        (self.root / 'docs' / 'spring').mkdir(parents=True)
        (self.root / 'docs' / 'spring' / 'api-mapping.md').write_text(RULEBOOK)
        (self.root / 'api' / 'java-differences-intro.md').write_text('# Java differences\n\nIntro.\n')
        (self.root / 'api' / 'upstreams.json').write_text(json.dumps({'schema': 'flint.api-upstreams/1', 'upstreams': [
            {'project': 'lib', 'version': '1.0', 'repo': 'r', 'url': 'u', 'sha256': 'a' * 64, 'format': 'jar'}]}))
        (self.root / 'api' / 'upstream' / 'lib-1.0.json').write_text(json.dumps(manifest([
            type_('p.A', ['get']), type_('p.B', ['x', 'y']), type_('p.sub.C', ['z']), type_('q.Loader')])))

    def mapping(self, elements):
        (self.root / 'api' / 'r' / 'mapping.json').write_text(json.dumps(
            {'rulebook': 2, 'upstream': ['lib@1.0'], 'elements': elements}))

    def test_precedence_matches_flint_api_coverage(self):
        c = api_differences.Classifier({
            'p.**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
            'p.sub.**': {'status': 'excluded', 'category': 'deferred', 'phase': '3'},
            'p.B#**': {'status': 'ported'},
            'p.B#x()': {'status': 'adapted', 'rules': ['R4']},
        })
        self.assertEqual(c.classify('p.B#x()')[0], 'p.B#x()')          # an exact id wins
        self.assertEqual(c.classify('p.B#y()')[0], 'p.B#**')           # then the longest literal prefix
        self.assertEqual(c.classify('p.sub.C#z()')[0], 'p.sub.**')
        self.assertEqual(c.classify('p.A')[0], 'p.**')
        self.assertIsNone(c.classify('q.Loader'))
        single = api_differences.Classifier({'p.*': {'status': 'ported'}})
        self.assertIsNotNone(single.classify('p.A'))
        self.assertIsNone(single.classify('p.sub.C'))                  # '*' stays within one name

    def test_page_lists_adapted_and_excluded_and_counts_deferred(self):
        self.mapping({
            'p.**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
            'p.A#get()': {'status': 'adapted', 'rules': ['R4', 'D-7'], 'd': 'flint.p.A.get',
                          'note': "Java's null-argument exceptions are not reproduced"},
            'q.Loader': {'status': 'excluded', 'category': 'jvm-runtime'},
            'p.B#y()': {'status': 'excluded', 'category': 'deferred', 'phase': '2', 'reason': 'waits on NavigableSet'},
        })
        page, problems = api_differences.render(self.root)
        self.assertEqual(problems, [])
        self.assertIn("| Java's null-argument exceptions are not reproduced |", page)
        self.assertIn('| r | `p.B#y()` | 2 | waits on NavigableSet |', page)
        self.assertIn('| `p.A#get()` | `flint.p.A.get` | [R4](api-mapping.md#r4-classt-parameters), '
                      '[D-7](api-mapping.md#deviations) |', page)
        self.assertIn('| `q.Loader` | `jvm-runtime` |  |', page)
        self.assertIn('| p | 4 | 0 |', page)                        # p.A, p.B, p.B#x(), p.B#y()
        self.assertIn('| p.sub | 2 | 0 |', page)                    # p.sub.C, p.sub.C#z(), by their own package
        self.assertTrue(page.startswith('<!-- GENERATED'))
        self.assertIn('Intro.', page)

    def test_unknown_citation_and_category_fail(self):
        self.mapping({
            '**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
            'p.A#get()': {'status': 'adapted', 'rules': ['R99'], 'd': 'flint.p.A.get'},
            'q.Loader': {'status': 'excluded', 'category': 'made-up'},
        })
        _, problems = api_differences.render(self.root)
        self.assertEqual(len(problems), 2)
        self.assertIn('cites R99', problems[0])
        self.assertIn("'made-up'", problems[1])

    def test_check_fails_until_written(self):
        self.mapping({'**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'}})
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 1)
        self.assertEqual(api_differences.main(['--write', '--root', str(self.root)]), 0)
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 0)
        self.mapping({'**': {'status': 'excluded', 'category': 'deferred', 'phase': '3'}})
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 1)


    def test_deviation_table_is_rendered_from_files(self):
        self.mapping({'**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
                      'p.A#get()': {'status': 'adapted', 'rules': ['D-JPA-2'], 'd': 'flint.p.A.get'}})
        rulebook = self.root / 'docs' / 'spring' / 'api-mapping.md'
        rulebook.write_text(RULEBOOK.replace('| ID | Deviation | Reason |\n| --- | --- | --- |\n| D-7 | Typed null | overloads |\n',
                                             api_differences.BEGIN + '\n' + api_differences.END + '\n'))
        deviations = self.root / 'api' / 'deviations'
        deviations.mkdir()
        for ident, text in (('D-JPA-2', 'option enums'), ('D-7', 'typed null'), ('D-14', 'UTF-8')):
            (deviations / f'{ident}.json').write_text(json.dumps({'id': ident, 'deviation': text, 'reason': 'why'}))
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 1)
        self.assertEqual(api_differences.main(['--write', '--root', str(self.root)]), 0)
        table = rulebook.read_text()
        self.assertLess(table.index('| D-7 |'), table.index('| D-14 |'))
        self.assertLess(table.index('| D-14 |'), table.index('| D-JPA-2 |'))
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 0)
        (deviations / 'D-JPA-3.json').write_text(json.dumps({'id': 'D-JPA-3', 'deviation': 'x', 'reason': 'y'}))
        self.assertEqual(api_differences.main(['--check', '--root', str(self.root)]), 1)
        (deviations / 'D-JPA-3.json').unlink()
        rulebook.write_text(rulebook.read_text().replace('| D-7 | typed null |', '| D-7 | hand edited |'))
        self.assertEqual(api_differences.table_problems(rulebook.read_text(), api_differences.with_deviation_table(
            rulebook.read_text(), api_differences.load_deviations(self.root, []))), [
            'docs/spring/api-mapping.md: the D-7 row differs from api/deviations/D-7.json; edit api/deviations/D-7.json, '
            'not the table (it is generated), then run: python3 tools/api_differences.py --write'])
        (deviations / 'D-JPA-3.json').write_text(json.dumps({'id': 'D-JPA-4', 'deviation': 'x', 'reason': 'y'}))
        problems = []
        api_differences.load_deviations(self.root, problems)
        self.assertIn('match the file name', problems[0])


    def test_a_ported_member_whose_type_has_no_d_counterpart_is_a_gap(self):
        types = [type_('p.A'), type_('p.Bee'), type_('p.Cee')]
        types[0]['members'] = [
            {'kind': 'method', 'name': 'm', 'signature': 'm(Bee)', 'type': 'void'},
            {'kind': 'method', 'name': 'n', 'signature': 'n(Cee,int,String)', 'type': 'List<T>'},
            {'kind': 'method', 'name': 'o', 'signature': 'o()', 'type': '@Nullable Bee[]'}]
        (self.root / 'api' / 'upstream' / 'lib-1.0.json').write_text(json.dumps(manifest(types)))
        self.mapping({
            '**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
            'p.A': {'status': 'ported', 'd': 'flint.p.A'},
            'p.A#m(Bee)': {'status': 'ported', 'd': 'flint.p.A.m'},
            'p.A#n(Cee,int,String)': {'status': 'ported', 'd': 'flint.p.A.n'},
            'p.A#o()': {'status': 'adapted', 'rules': ['R5'], 'd': 'flint.p.A.o'},
            'p.Cee': {'status': 'ported', 'd': 'flint.p.C'},
        })
        gaps = api_differences.dependency_gaps(self.root)
        self.assertEqual(sorted(gaps), ['p.A#m(Bee) -> Bee', 'p.A#o() -> Bee'])   # C ported; int, String, T rule-mapped
        self.assertEqual(gaps['p.A#m(Bee) -> Bee'], 'r: p.Bee is deferred')
        baseline = self.root / 'api' / 'dependency-baseline.json'
        baseline.write_text(json.dumps({'gaps': {'p.A#m(Bee) -> Bee': 'r: p.Bee is deferred'}}))
        problems = api_differences.dependency_problems(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn('p.A#o() is ported or adapted, but its type Bee has no D counterpart', problems[0])
        self.mapping({'**': {'status': 'excluded', 'category': 'deferred', 'phase': '2'},
                      'p.A': {'status': 'ported', 'd': 'flint.p.A'}, 'p.Bee': {'status': 'ported', 'd': 'flint.p.B'},
                      'p.A#m(Bee)': {'status': 'ported', 'd': 'flint.p.A.m'}})
        self.assertIn('resolved; shrink it', api_differences.dependency_problems(self.root)[0])
        self.assertEqual(api_differences.dependency_problems(self.root, write=True), [])
        self.assertEqual(json.loads(baseline.read_text())['gaps'], {})


if __name__ == '__main__':
    unittest.main()
