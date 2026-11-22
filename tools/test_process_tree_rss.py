import os
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import measure_builds  # noqa: E402


def resident(pid):
    with open(f'/proc/{pid}/statm') as stream:
        return int(stream.read().split()[1]) * measure_builds.PAGE_BYTES


class ProcessTreeRssTest(unittest.TestCase):
    def test_sums_descendants_and_excludes_other_processes(self):
        # A shell whose child allocates; the unrelated sleeper must not be counted.
        unrelated = subprocess.Popen(['sleep', '30'])
        tree = subprocess.Popen([sys.executable, '-c',
                                 'import subprocess,sys;'
                                 'subprocess.run([sys.executable,"-c","b=bytearray(64<<20);import time;time.sleep(30)"])'])
        try:
            children = []
            for _ in range(200):
                children = [int(p) for p in os.listdir('/proc') if p.isdigit() and self.parent(int(p)) == tree.pid]
                if children and resident(children[0]) > 60 << 20:
                    break
                time.sleep(.02)
            self.assertTrue(children, 'grandchild did not start')
            expected = resident(tree.pid) + resident(children[0])
            for floor in (tree.pid, 0):
                total = measure_builds.process_tree_rss(tree.pid, floor)
                self.assertGreaterEqual(total, 64 << 20)
                self.assertLess(abs(total - expected), 4 << 20)
            self.assertLess(measure_builds.process_tree_rss(tree.pid, 0) - expected, resident(unrelated.pid))
        finally:
            for process in (tree, unrelated):
                process.kill()
                process.wait()
            for pid in children:
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass

    @staticmethod
    def parent(pid):
        try:
            with open(f'/proc/{pid}/stat', 'rb') as stream:
                stat = stream.read()
        except OSError:
            return None
        return int(stat[stat.rindex(b')') + 2:].split()[1])

    def test_timed_process_reports_peak(self):
        log = Path(os.environ.get('TMPDIR', '/tmp')) / f'flint-rss-test-{os.getpid()}.log'
        try:
            result = measure_builds.timed_process(
                [sys.executable, '-c', 'b=bytearray(48<<20);import time;time.sleep(.3)'], '.', dict(os.environ), log)
        finally:
            log.unlink(missing_ok=True)
        self.assertGreaterEqual(result['peak_rss_bytes'], 48 << 20)
        self.assertEqual(result['exit_code'], 0)


if __name__ == '__main__':
    unittest.main()
