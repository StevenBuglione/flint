"""Flint's Conan recipe index stays generated from policy/native-lock.json and tools/native_build.py (ADR-023)."""
import hashlib
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from conan_index import INDEX, PROVIDERS  # noqa: E402


class RecipeIndexTests(unittest.TestCase):
    def test_the_checked_in_index_is_current(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/conan_index.py'), '--check'],
                                capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_recipe_pins_the_lock_and_the_build_steps(self):
        rows = {r['name']: r for r in json.loads((ROOT / 'policy/native-lock.json').read_text(encoding='utf-8'))['libraries']}
        engine = hashlib.sha256((ROOT / 'tools/native_build.py').read_bytes()).hexdigest()
        self.assertEqual(len(PROVIDERS), 20)
        for name in PROVIDERS:
            row = rows[name]
            data = (INDEX / 'recipes' / name / 'all' / 'conandata.yml').read_text(encoding='utf-8')
            self.assertIn('url: "' + row['archive_url'] + '"', data)
            self.assertIn('sha256: "' + row['archive_sha256'] + '"', data)
            recipe = (INDEX / 'recipes' / name / 'all' / 'conanfile.py').read_text(encoding='utf-8')
            self.assertIn("BUILD_ENGINE_SHA256 = '" + engine + "'", recipe)
            self.assertIn('license = ' + repr(row['license_selected']), recipe)
            for dependency in row['dependencies']:
                self.assertIn(repr(dependency + '/' + rows[dependency]['version']), recipe)
            self.assertTrue(re.search(r'"' + re.escape(row['version']) + r'":\n    folder: all',
                                      (INDEX / 'recipes' / name / 'config.yml').read_text(encoding='utf-8')))


    def test_a_stale_recipe_is_reported_for_the_structural_gate(self):
        """tools/gates.py fails the structural gate on stale_files(): an edit to native_build.py without --write
        would make every native build in a fresh checkout refuse to run."""
        import shutil
        import tempfile
        from unittest import mock

        import conan_index
        self.assertEqual(conan_index.stale_files(), [])
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / 'conan-index'
            shutil.copytree(INDEX, copy)
            recipe = copy / 'recipes/zlib/all/conanfile.py'
            recipe.write_text(recipe.read_text(encoding='utf-8') + '# edited\n', encoding='utf-8')
            with mock.patch.object(conan_index, 'INDEX', copy):
                self.assertEqual(conan_index.stale_files(), ['recipes/zlib/all/conanfile.py'])

if __name__ == '__main__':
    unittest.main()
