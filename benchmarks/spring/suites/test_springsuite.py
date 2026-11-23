"""Self-test of the suite's comparison rules: `python3 -m unittest discover -s benchmarks/spring/suites`."""
import json
import unittest

import springsuite
from springsuite import Case, compare, observe

ORIGIN = 'http://127.0.0.1:4242'
PROBLEM = Case('problem', 'GET', '/x', volatile={'timestamp': 'instant'})


def response(status=200, reason='', headers=(), body=b'', case=PROBLEM, mask=False):
    return observe(case, status, reason, list(headers), body, ORIGIN, mask)


class Comparison(unittest.TestCase):
    def setUp(self):
        self.headers = [('Content-Type', 'application/problem+json'), ('Transfer-Encoding', 'chunked'),
                        ('Vary', 'Origin'), ('Vary', 'Access-Control-Request-Method'), ('Date', 'Mon, 1 Jan')]
        self.body = json.dumps({'type': ORIGIN + '/x', 'status': 400, 'timestamp': '2026-11-23T04:29:30.66Z'},
                               separators=(',', ':')).encode()
        self.golden = response(400, '', self.headers, self.body, mask=True)

    def test_recording_masks_and_substitutes(self):
        self.assertEqual(self.golden['json'], {'type': '{origin}/x', 'status': 400, 'timestamp': {'$match': 'instant'}})
        self.assertNotIn('date', [name for name, _ in self.golden['headers']])

    def test_identical_passes_in_both_modes(self):
        actual = response(400, '', self.headers, self.body)
        self.assertEqual(compare(self.golden, actual, 'exact'), [])
        self.assertEqual(compare(self.golden, actual, 'semantic'), [])

    def test_status_header_and_body_values_fail(self):
        self.assertTrue(compare(self.golden, response(500, '', self.headers, self.body), 'semantic'))
        changed = [row for row in self.headers if row[0] != 'Vary'] + [('Vary', 'Origin')]
        self.assertTrue(compare(self.golden, response(400, '', changed, self.body), 'semantic'))
        wrong = self.body.replace(b'400', b'401')
        self.assertTrue(compare(self.golden, response(400, '', self.headers, wrong), 'semantic'))
        stale = self.body.replace(b'2026-11-23T04:29:30.66Z', b'yesterday')
        self.assertTrue(compare(self.golden, response(400, '', self.headers, stale), 'semantic'))

    def test_framing_reason_and_key_order_are_exact_only(self):
        framed = [row for row in self.headers if row[0] != 'Transfer-Encoding'] + [('Content-Length', '80')]
        reordered = json.dumps({'status': 400, 'type': ORIGIN + '/x', 'timestamp': '2026-11-23T04:29:30Z'}).encode()
        for actual in (response(400, '', framed, self.body), response(400, 'Bad Request', self.headers, self.body),
                       response(400, '', self.headers, reordered)):
            self.assertTrue(compare(self.golden, actual, 'exact'))
            self.assertEqual(compare(self.golden, actual, 'semantic'), [])

    def test_text_bodies_normalize(self):
        case = Case('page', 'GET', '/', normalize=[(r'<i>[^<]*</i>', '<i>*</i>')])
        golden = response(404, '', [('Content-Type', 'text/html')], b'at <i>noon</i>', case, mask=True)
        self.assertEqual(compare(golden, response(404, '', [('Content-Type', 'text/html')], b'at <i>dusk</i>', case),
                                 'exact'), [])
        self.assertTrue(compare(golden, response(404, '', [('Content-Type', 'text/html')], b'by <i>dusk</i>', case),
                                'exact'))

    def test_boot_error_timestamps_keep_three_digits(self):
        case = Case('error', 'GET', '/nope', volatile={'timestamp': 'instant-millis'})
        body = lambda stamp: json.dumps({'timestamp': stamp, 'status': 404}).encode()
        golden = response(404, '', [('Content-Type', 'application/json')], body('2026-11-23T04:21:32.396Z'), case, True)
        for stamp, ok in (('2026-11-23T15:01:50.000Z', True), ('2026-11-23T15:01:50Z', False),
                          ('2026-11-23T15:01:50.39Z', False)):
            problems = compare(golden, response(404, '', [('Content-Type', 'application/json')], body(stamp), case),
                               'semantic')
            self.assertEqual(problems == [], ok, stamp)

    def test_log_events(self):
        text = ('2026-11-23T04:21:58.353Z  INFO 17 --- [           main] c.e.r.App    : Creating tables\n'
                '2026-11-23T04:21:58.350Z  INFO 17 --- [           main] c.e.r.App    : Started App in 0.4 seconds\n'
                '2026-11-23T04:21:58.355Z  INFO 17 --- [           main] com.zaxxer.hikari.HikariDataSource : x\n')
        self.assertEqual(springsuite.log_events(text, 'c.e.r.App'),
                         [' INFO --- [           main] c.e.r.App    : Creating tables'])


if __name__ == '__main__':
    unittest.main()
