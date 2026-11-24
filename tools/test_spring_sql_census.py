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
        failed = census.summarize([line(1, 'ERROR:  insert or update on table "visits" violates foreign key constraint'),
                                   line(1, 'DETAIL:  Key (pet_id)=(999) is not present in table "pets".'),
                                   line(1, 'STATEMENT:  INSERT INTO visits (pet_id) VALUES($1)')])
        self.assertEqual(failed['kinds'], {'failed insert': 1})
        self.assertEqual(failed['counts']['data_statements'], 1)
        first = census.summarize(groups[0])
        self.assertEqual(first['counts']['transaction_commands'], 2)
        self.assertEqual(first['counts']['data_statements'], 1)
        self.assertEqual(first['counts']['parse_unnamed'], 1)
        self.assertEqual(first['statements'], ['BEGIN READ ONLY', 'SELECT 1', 'COMMIT continuation'])  # joined

    def test_continuation_lines_join_their_statement(self):
        base = census.log_time(line(0, 'x'))
        marks = [('a', 'POST', '/a', base + 0.100, base + 0.200)]
        lines = [line(150, 'duration: 0.1 ms  execute <unnamed>: INSERT INTO owners (a) VALUES($1)'), '\tRETURNING "id"']
        self.assertEqual(census.summarize(census.assign(lines, marks)[0])['statements'],
                         ['INSERT INTO owners (a) VALUES($1) RETURNING "id"'])

    def test_table_marks_divergence_from_java(self):
        def result(impl, kinds):
            counts = {'data_statements': 1, 'transaction_commands': 0, 'parse': 0, 'parse_unnamed': 0, 'execute': 1,
                      'simple': 0}
            return {'impl': impl, 'cases': [{'name': 'c', 'method': 'GET', 'path': '/x', 'kinds': kinds, 'counts': counts}]}
        text, differing = census.table([result('java', {'begin': 1, 'select': 1, 'commit': 1}),
                                        result('go', {'select': 1})])
        self.assertEqual(differing, 1)
        self.assertIn("go: txn {} vs {'begin': 1, 'commit': 1}", text)



class Registration(unittest.TestCase):
    def test_census_required_current_and_clean(self):
        import json
        import tempfile
        from pathlib import Path
        from unittest import mock
        import spring_bench
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(spring_bench, 'CENSUS', Path(temporary)):
            self.assertIn('no SQL census', spring_bench.census_problems('petclinic-rest', 'abc')[0])
            path = Path(temporary) / 'petclinic-rest.json'
            path.write_text(json.dumps({'comparator_sha256': 'abc', 'divergences': {'go': 0, 'flint': 2}}))
            self.assertEqual(spring_bench.census_problems('petclinic-rest', 'abc'), [])
            self.assertIn('another comparator source', spring_bench.census_problems('petclinic-rest', 'def')[0])
            path.write_text(json.dumps({'comparator_sha256': 'abc', 'divergences': {'go': 3}}))
            self.assertIn('differs from the reference', spring_bench.census_problems('petclinic-rest', 'abc')[0])
            self.assertEqual(spring_bench.census_problems('gs-rest-service', 'zzz'), [])

    def test_divergences_list_cases(self):
        def result(impl, kinds):
            return {'impl': impl, 'cases': [{'name': 'c', 'method': 'GET', 'path': '/x', 'kinds': kinds}]}
        found = census.divergences([result('java', {'begin': 1, 'select': 1, 'commit': 1}), result('go', {'select': 1}),
                                    result('flint', {'begin': 1, 'select': 1, 'commit': 1})])
        self.assertEqual(found['flint'], [])
        self.assertEqual(found['go'][0]['transactions'], {'implementation': {}, 'java': {'begin': 1, 'commit': 1}})


if __name__ == '__main__':
    unittest.main()
