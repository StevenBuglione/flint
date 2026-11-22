"""tools/install_quality_tools.py fails with a plain message, never a traceback, when DUB cannot download."""
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import install_quality_tools  # noqa: E402


class QualityToolInstallerTests(unittest.TestCase):
    def test_a_missing_libcurl_is_named_with_the_fix(self):
        with mock.patch.object(install_quality_tools, 'CURL_LIBRARIES', ('libflint-absent-curl.so.9',)), \
                mock.patch.object(sys, 'argv', ['install_quality_tools.py']), \
                mock.patch.object(install_quality_tools.subprocess, 'run') as run:
            with self.assertRaises(SystemExit) as raised:
                install_quality_tools.main()
        run.assert_not_called()
        self.assertIn('dub cannot download the quality tools', str(raised.exception))
        self.assertIn('LD_LIBRARY_PATH', str(raised.exception))
        self.assertIn('NixOS', str(raised.exception))

    def test_a_failing_command_exits_with_its_last_error_line(self):
        with self.assertRaises(SystemExit) as raised:
            install_quality_tools.run([sys.executable, '-c', 'import sys; sys.stderr.write("first\\nFailed to download\\n"); sys.exit(2)'],
                                      capture_output=True, text=True)
        self.assertIn('failed with exit status 2: Failed to download', str(raised.exception))

    def test_the_script_reports_without_a_traceback(self):
        code = ('import sys; sys.path.insert(0, %r); import install_quality_tools as q; '
                'q.CURL_LIBRARIES = ("libflint-absent-curl.so.9",); sys.argv = ["x"]; q.main()') % str(ROOT / 'tools')
        result = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('Traceback', result.stderr)
        self.assertIn('dub cannot download', result.stderr)


if __name__ == '__main__':
    unittest.main()
