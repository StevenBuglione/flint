import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from measure_builds import package_template_instances, template_instances  # noqa: E402

LINE = 'x.d(1,1): vtemplate: {} ({} distinct) instantiation(s) of template `T(U)` found, they are:\n'


def invocation(directory, identity, cwd, sources, count):
    (directory / (identity + '.stdout.txt')).write_text('')
    (directory / (identity + '.stderr.txt')).write_text(LINE.format(count, 1))
    record = directory / (identity + '.invocation.json')
    record.write_text(json.dumps({'cwd': cwd, 'expanded_arguments': ['-c', *sources],
                                  'stdout': identity + '.stdout.txt', 'stderr': identity + '.stderr.txt'}))
    return record


class PackageTemplateCounts(unittest.TestCase):
    def test_counts_only_the_package_library_and_probe(self):
        with tempfile.TemporaryDirectory() as temporary:
            traces = Path(temporary)
            workspace = '/tmp/w/workspace'
            records = [
                invocation(traces, 'a', workspace + '/packages/engine-web/bench', ['../source/flint/engine/web/router.d'], 300),
                invocation(traces, 'b', workspace + '/packages/engine-web/bench', ['source/app.d', 'harness/h.d'], 40),
                invocation(traces, 'c', workspace + '/packages/engine-web/bench', ['../../reactor/source/flint/engine/reactor/package.d'], 900),
                invocation(traces, 'd', workspace + '/packages/webview/bench', ['source/app.d'], 7),
            ]
            self.assertEqual(package_template_instances(records, 'engine-web'), 340)
            closure = ''.join((traces / (i + '.stderr.txt')).read_text() for i in 'abcd')
            self.assertEqual(template_instances(closure), 1247)

    def test_no_matching_invocation_counts_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            traces = Path(temporary)
            records = [invocation(traces, 'a', '/w/packages/arena', ['source/flint/arena/package.d'], 5)]
            self.assertEqual(package_template_instances(records, 'conc'), 0)


if __name__ == '__main__':
    unittest.main()
