"""Unit tests of the SQL census's log assignment: `python3 tools/test_spring_sql_census.py`."""
import unittest

import spring_sql_census as census


def line(ms, text, db='petclinic1'):
    return f'2026-11-24 04:00:00.{ms:03d} UTC [7] db={db} LOG:  {text}'


class Assign(unittest.TestCase):
    def test_lines_go_to_the_request_they_fall_in(self):
        base = census.log_time(line(0, 'x'))
        marks = [('a', 'GET', '/a', base + 0.100, base + 0.200), ('b', 'GET', '/b', base + 0.300, base + 0.400)]
        lines = [line(50, 'duration: 0.1 ms  statement: CREATE TABLE t ()'),
                 line(150, 'duration: 0.1 ms  parse <unnamed>: BEGIN READ ONLY'),
                 line(151, 'duration: 0.1 ms  execute <unnamed>: BEGIN READ ONLY'),
                 line(152, 'duration: 0.1 ms  execute S_1: SELECT 1'),
                 line(153, 'duration: 0.1 ms  execute <unnamed>: COMMIT'),
                 '\tcontinuation',
                 line(250, 'duration: 0.1 ms  statement: SELECT 2'),
                 line(350, 'duration: 0.1 ms  statement: DELETE FROM t')]
        groups = census.assign(lines, marks)
        self.assertEqual(len(groups['startup']), 1)
        self.assertEqual(len(groups[0]), 4)
        self.assertEqual(len(groups['between']), 1)
        self.assertEqual(len(groups[1]), 1)
        first = census.summarize(groups[0])
        self.assertEqual(first['counts']['transaction_commands'], 2)
        self.assertEqual(first['counts']['data_statements'], 1)
        self.assertEqual(first['counts']['parse_unnamed'], 1)
        self.assertEqual(first['statements'], ['BEGIN READ ONLY', 'SELECT 1', 'COMMIT'])

    def test_table_marks_divergence_from_java(self):
        def result(impl, kinds):
            counts = {'data_statements': 1, 'transaction_commands': 0, 'parse': 0, 'parse_unnamed': 0, 'execute': 1,
                      'simple': 0}
            return {'impl': impl, 'cases': [{'name': 'c', 'method': 'GET', 'path': '/x', 'kinds': kinds, 'counts': counts}]}
        text, differing = census.table([result('java', {'begin': 1, 'select': 1, 'commit': 1}),
                                        result('go', {'select': 1})])
        self.assertEqual(differing, 1)
        self.assertIn("go: txn {} vs {'begin': 1, 'commit': 1}", text)


if __name__ == '__main__':
    unittest.main()
