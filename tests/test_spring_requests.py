"""The request exports of the side-by-side suites stay in step with the Python suites (tools/spring_requests.py)."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_requests  # noqa: E402


class SpringRequestExports(unittest.TestCase):
    def test_every_export_matches_its_suite(self):
        spring_requests.main(['--check'])


if __name__ == '__main__':
    unittest.main()
