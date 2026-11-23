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
        for meta in json.loads(framework.read_text())['modules'].values():
            roots.update([meta['module'], *meta.get('also', [])])
    for meta in json.loads((ROOT / 'policy/boot.json').read_text())['libraries'].values():
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


if __name__ == '__main__':
    unittest.main()
