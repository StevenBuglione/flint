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



class Parity(unittest.TestCase):
    """ADR-033: `parity` is `semantic` plus the golden's reason phrase, framing and connection lifetime."""

    PLAIN = Case('plain', 'GET', '/x')

    def setUp(self):
        self.headers = [('Content-Type', 'application/json'), ('Transfer-Encoding', 'chunked')]
        self.body = b'{"status":400,"type":"x"}'
        self.golden = response(400, '', self.headers + [('Connection', 'close')], self.body, case=self.PLAIN, mask=True)

    def actual(self, reason='', headers=None, body=None, lifetime='close'):
        observed = response(400, reason, self.headers + [('Connection', 'close')] if headers is None else headers,
                            self.body if body is None else body, case=self.PLAIN)
        observed['lifetime'] = lifetime
        return observed

    def test_matching_transport_passes_with_semantic_freedoms(self):
        self.assertEqual(compare(self.golden, self.actual(), 'parity'), [])
        reordered = self.actual(body=b'{"type": "x", "status": 400}\n')
        self.assertEqual(compare(self.golden, reordered, 'parity'), [])

    def test_reason_framing_and_lifetime_fail(self):
        self.assertTrue(compare(self.golden, self.actual(reason='Bad Request'), 'parity'))
        length = [('Content-Type', 'application/json'), ('Content-Length', '25'), ('Connection', 'close')]
        self.assertTrue(compare(self.golden, self.actual(headers=length), 'parity'))
        unannounced = self.headers
        self.assertTrue(compare(self.golden, self.actual(headers=unannounced), 'parity'))
        self.assertIn("connection lifetime 'keep', expected 'close'",
                      compare(self.golden, self.actual(lifetime='keep'), 'parity'))
        self.assertTrue(compare(self.golden, self.actual(lifetime=None), 'parity'))

    def test_content_length_value_is_free(self):
        golden = response(200, '', [('Content-Type', 'application/json'), ('Content-Length', '25')], self.body, case=self.PLAIN, mask=True)
        actual = response(200, '', [('Content-Type', 'application/json'), ('Content-Length', '26')], self.body + b'\n', case=self.PLAIN)
        actual['lifetime'] = 'keep'
        self.assertEqual(compare(golden, actual, 'parity'), [])
        self.assertTrue(compare(golden, actual, 'exact'))


class LifetimeExchange(unittest.TestCase):
    """The raw exchange the `parity` mode runs: one case, then PROBE on the same socket."""

    def serve(self, responses, close_after):
        import socket
        import threading
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        seen = []

        def run():
            conn, _ = listener.accept()
            with listener, conn:
                data = b''
                for index, payload in enumerate(responses):
                    while b'\r\n\r\n' not in data:
                        chunk = conn.recv(4096)
                        if not chunk:
                            return
                        data += chunk
                    head, _, data = data.partition(b'\r\n\r\n')
                    length = [int(line.split(b':')[1]) for line in head.split(b'\r\n')
                              if line.lower().startswith(b'content-length:')]
                    while length and len(data) < length[0]:
                        data += conn.recv(4096)
                    if length:
                        data = data[length[0]:]
                    seen.append(head.split(b'\r\n')[0].decode())
                    conn.sendall(payload)
                    if index + 1 == close_after:
                        return
        threading.Thread(target=run, daemon=True).start()
        return f'http://127.0.0.1:{listener.getsockname()[1]}', seen

    def test_kept_connection_answers_the_probe(self):
        chunked = (b'HTTP/1.1 200 \r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n'
                   b'4\r\n{"a"\r\n3\r\n:1}\r\n0\r\n\r\n')
        probe = b'HTTP/1.1 404 \r\nContent-Length: 0\r\n\r\n'
        origin, seen = self.serve([chunked, probe], 2)
        status, reason, headers, raw, lifetime = springsuite.lifetime_exchange(
            origin, Case('post', 'POST', '/owners', body={'x': 1}))
        self.assertEqual((status, reason, raw, lifetime), (200, '', b'{"a":1}', 'keep'))
        self.assertEqual(seen, ['POST /owners HTTP/1.1', 'GET /flint-parity-probe HTTP/1.1'])

    def test_closed_connection_and_bodiless_responses(self):
        origin, _ = self.serve([b'HTTP/1.1 204 \r\nConnection: close\r\n\r\n'], 1)
        status, reason, headers, raw, lifetime = springsuite.lifetime_exchange(origin, Case('put', 'PUT', '/x'))
        self.assertEqual((status, raw, lifetime), (204, b'', 'close'))

    def test_request_matches_http_client(self):
        request = springsuite.raw_request('http://127.0.0.1:9', 'POST', '/p', {'Accept': '*/*'}, None)
        self.assertEqual(request, b'POST /p HTTP/1.1\r\nHost: 127.0.0.1:9\r\nAccept-Encoding: identity\r\n'
                                  b'Accept: */*\r\nContent-Length: 0\r\n\r\n')


if __name__ == '__main__':
    unittest.main()
