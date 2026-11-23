"""dscanner.ini excludes the Spring API layer from the checks that fight Java's shapes (work-queue item 22)."""
import configparser
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JAVA_SHAPED = ('unused_parameter_check', 'builtin_property_names_check', 'undocumented_declaration_check',
               'vcall_in_ctor', 'could_be_immutable_check', 'object_const_check')


def spring_roots():
    """Every module root of policy/framework.json (with its `also` roots) and of the Spring Boot libraries, without
    the engines registered there, which keep every check."""
    roots = set()
    framework = ROOT / 'policy/framework.json'
    if framework.is_file():
        for meta in json.loads(framework.read_text(encoding='utf-8'))['modules'].values():
            roots.update([meta['module'], *meta.get('also', [])])
    for meta in json.loads((ROOT / 'policy/boot.json').read_text(encoding='utf-8'))['libraries'].values():
        if meta['directory'].startswith(('boot/core', 'boot/module', 'boot/starter')):
            roots.add(meta['module'])
    return {root for root in roots if not root.startswith('flint.engine.')}


class QualityFilterTests(unittest.TestCase):
    def test_every_spring_module_root_is_excluded_from_the_java_shaped_checks(self):
        ini = configparser.ConfigParser()
        ini.read(ROOT / 'dscanner.ini')
        filters = ini['analysis.config.ModuleFilters']
        for check in JAVA_SHAPED:
            excluded = [entry[1:] for entry in filters[check].strip('"').split(',') if entry.startswith('-')]
            for root in sorted(spring_roots()):
                self.assertTrue(any(root == prefix or root.startswith(prefix + '.') for prefix in excluded),
                                f'{check} does not exclude {root}: add -{root} to dscanner.ini')
            self.assertFalse(any(prefix.startswith('flint.engine.') for prefix in excluded), check)


class ComplexityAllowlistTests(unittest.TestCase):
    """policy/complexity-allowlist.json: only ported functions, each citing its upstream file and method."""

    def test_every_entry_names_a_ported_function_and_its_upstream_method(self):
        import sys
        sys.path.insert(0, str(ROOT / 'tools'))
        import quality
        allowed = quality.complexity_allowlist()
        self.assertTrue(allowed)
        for (file, function), entry in allowed.items():
            source = (ROOT / file).read_text(encoding='utf-8')
            self.assertIn(function + '(', source, file)
            self.assertIn('Ported from', source[:2000], f'{file} is not a ported module')
            self.assertTrue(entry['upstream']['file'].endswith('.java'), entry)

    def test_an_entry_without_a_citation_is_refused(self):
        import shutil
        import sys
        import tempfile
        sys.path.insert(0, str(ROOT / 'tools'))
        import quality
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'policy').mkdir()
            shutil.copy(ROOT / 'policy/upstream-licences.json', root / 'policy')
            (root / 'a.d').write_text('void f() {}\n', encoding='utf-8')
            (root / 'policy/complexity-allowlist.json').write_text(json.dumps({'functions': [
                {'file': 'a.d', 'function': 'f', 'upstream': {'project': 'spring-framework', 'file': 'A.java'}}]}),
                encoding='utf-8')
            with self.assertRaises(SystemExit):
                quality.complexity_allowlist(root)

    def test_the_finding_names_the_function_on_its_declaration_line(self):
        import sys
        import tempfile
        sys.path.insert(0, str(ROOT / 'tools'))
        import quality
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'a.d'
            path.write_text('struct S\n{\n    static bool convert(T)(JSONValue v, out T r) const\n', encoding='utf-8')
            self.assertEqual(quality.function_at(path, 3), 'convert')


if __name__ == '__main__':
    unittest.main()
