"""Unit tests of the measurement queue's quiet-window rules: `python3 tools/test_measure_queue.py`."""
import json
import socket
import subprocess
import sys
import time
import unittest
from unittest import mock

import measure_queue


class QuietWindow(unittest.TestCase):
    def test_reserved_and_busy_ports_are_refused(self):
        self.assertTrue(measure_queue.check_ports([8081]))
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            port = listener.getsockname()[1]
            self.assertEqual(measure_queue.check_ports([port]), [f'port {port} is in use'])
        self.assertEqual(measure_queue.check_ports([port]), [])

    def test_own_children_are_not_foreign_load(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(5)'])
        try:
            time.sleep(.2)
            self.assertIn(child.pid, measure_queue.own_tree())
        finally:
            child.kill()
            child.wait()

    def test_load_and_build_processes_make_the_window_busy(self):
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(0.4, 0.5, 0.6)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=[]):
            self.assertTrue(measure_queue.quiet_snapshot()['quiet'])
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(1.6, 0.5, 0.6)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=[]):
            self.assertFalse(measure_queue.quiet_snapshot()['quiet'])
            self.assertTrue(measure_queue.quiet_snapshot(own_load_ok=True)['quiet'])
        build = [{'pid': 1, 'command': 'ldc2', 'cwd': '/elsewhere'}]
        with mock.patch.object(measure_queue.os, 'getloadavg', return_value=(0.1, 0.1, 0.1)), \
                mock.patch.object(measure_queue, 'busy_processes', return_value=build):
            self.assertFalse(measure_queue.quiet_snapshot()['quiet'])

    def test_sleeping_build_processes_are_idle(self):
        sleeper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(5)'])
        try:
            rows = [{'pid': sleeper.pid, 'command': 'dmd', 'cwd': '/elsewhere',
                     'ticks': measure_queue.cpu_ticks(sleeper.pid)}]
            with mock.patch.object(measure_queue, 'build_processes', return_value=rows):
                self.assertEqual(measure_queue.busy_processes(.3), [])
                self.assertEqual(measure_queue.busy_processes.idle, 1)
        finally:
            sleeper.kill()
            sleeper.wait()

    def test_entries_are_well_formed(self):
        for entry in measure_queue.entries():
            self.assertIn(entry['status'], ('pending', 'blocked', 'done'))
            self.assertIn(entry['measure']['kind'], measure_queue.KINDS)
            self.assertFalse(measure_queue.check_ports(p for p in entry['measure'].get('ports', [])
                                                       if p in measure_queue.RESERVED_PORTS))
            json.dumps(entry)


if __name__ == '__main__':
    unittest.main()
