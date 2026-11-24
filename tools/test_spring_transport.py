#!/usr/bin/env python3
import socket
import threading
import unittest

import spring_transport as st

CHUNKED = (b'HTTP/1.1 404 \r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n'
           b'Date: Tue, 24 Nov 2026 22:00:00 GMT\r\n\r\n5\r\nhello\r\n3\r\n!!!\r\n0\r\n\r\n')
LENGTH = b'HTTP/1.1 400 Bad Request\r\nContent-Type: application/problem+json\r\nContent-Length: 4\r\n\r\n{}{}'
SPEC = {'path': '/nope', 'expected': {'request': {'method': 'POST', 'headers': {'Accept': '*/*'}, 'body': '{"a":1}'}}}


def serve(responses, close_after):
    """A loopback server answering each request on one connection with the next response; it closes after
    `close_after` responses. Returns the port."""
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)

    def run():
        conn, _ = listener.accept()
        with listener, conn:
            for index, response in enumerate(responses):
                data = b''
                while b'\r\n\r\n' not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        return
                    data += chunk
                conn.sendall(response)
                if index + 1 == close_after:
                    return
    threading.Thread(target=run, daemon=True).start()
    return listener.getsockname()[1]


class Hook(unittest.TestCase):
    def test_inserted_before_the_status_line(self):
        source = ('package main\n\nfunc other() {\n\tw.WriteHeader(status)\n}\n\n'
                  'func writeJSON(w http.ResponseWriter, status int) {\n\tw.Header().Set("A", "b")\n'
                  '\tw.WriteHeader(status)\n}\n')
        out = st.insert_hook(source)
        self.assertIn('\ttransportVariant(w, status)\n\tw.WriteHeader(status)\n}', out)
        self.assertEqual(out.count('transportVariant'), 1)
        self.assertIsNone(st.insert_hook('package main\n'))

    def test_hook_without_write_header_is_refused(self):
        with self.assertRaises(SystemExit):
            st.insert_hook('func writeJSON(w http.ResponseWriter) {\n\treturn\n}\n')


class Exchange(unittest.TestCase):
    def test_request_has_no_connection_header(self):
        request = st.request_bytes(SPEC, 8080).decode()
        self.assertTrue(request.startswith('POST /nope HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n'))
        self.assertIn('Content-Length: 7\r\n\r\n{"a":1}', request)
        self.assertNotIn('Connection', request)

    def test_chunked_and_kept(self):
        result = st.exchange(serve([CHUNKED, CHUNKED], 2), SPEC)
        first = result['first']
        self.assertEqual((first['status'], first['reason'], first['framing']), (404, '', 'chunked'))
        self.assertEqual((first['chunks'], first['body']), ([5, 3], 'hello!!!'))
        self.assertEqual(first['raw'].encode('latin-1'), CHUNKED)
        self.assertEqual(result['after_first'], 'open')
        self.assertTrue(result['reused'])

    def test_closed_after_the_response(self):
        result = st.exchange(serve([LENGTH], 1), SPEC)
        self.assertEqual((result['first']['framing'], result['first']['body_bytes']), ('content-length', 4))
        self.assertIn(result['after_first'], ('closed', 'reset'))
        self.assertFalse(result['reused'])
        self.assertEqual(result['second_request']['outcome'], 'refused')


class Accepts(unittest.TestCase):
    def row(self, marks, latency_count, probes):
        return {'observations': [{'event': e, 'data': v} for e, v in marks.items()],
                'latency': {'count': latency_count, 'process': {'correctness_probes': probes}},
                'capacity': {'count': 1000, 'process': {'correctness_probes': 20}}}

    def test_harness_connections_are_subtracted(self):
        marks = {'ready': 0, 'after-warmup': 100, 'after-latency': 100 + 64 + 31, 'after-capacity': 100 + 95 + 1021}
        accepts = st.accepts_per_phase(self.row(marks, 150000, 30))
        self.assertEqual(accepts['latency']['passive_opens'], 95)
        self.assertAlmostEqual(accepts['latency']['accepts_per_request'], 64 / 150000)
        self.assertAlmostEqual(accepts['capacity']['accepts_per_request'], 1000 / 1000)


class Summary(unittest.TestCase):
    def test_ratios_against_registered_go(self):
        def row(arm, p99):
            return {'arm': arm, 'latency': {'p50_ms': .1, 'p99_ms': p99, 'p999_ms': 1, 'cpu_ns_per_request': 10000},
                    'capacity': {'requests_per_second': 20000},
                    'accepts': {'latency': {'accepts_per_request': 0}, 'capacity': {'accepts_per_request': 0}}}
        rows = [row('go', .1), row('go', .12), row('go-chunked-close', .2), row('go-chunked-close', .22), row('flint', .5)]
        summary = st.summarize(rows)
        self.assertEqual(set(summary['ratios']), {'go-chunked-close / go'})
        self.assertAlmostEqual(summary['ratios']['go-chunked-close / go']['p99_us'][0], .21 / .11)
        self.assertAlmostEqual(summary['medians']['flint']['p99_us'], 500)


GOLDEN = {'observations': [
    {'name': 'json 404', 'request': {'method': 'GET', 'path': '/nope'},
     'response': {'status': 404, 'reason': '', 'headers': [['content-type', 'application/json'],
                                                           ['transfer-encoding', 'chunked']]}},
    {'name': 'html 404', 'request': {'method': 'GET', 'path': '/nope'},
     'response': {'status': 404, 'reason': '', 'headers': [['content-type', 'text/html;charset=UTF-8'],
                                                           ['content-length', '275']]}},
    {'name': 'bad owner', 'request': {'method': 'POST', 'path': '/owners'},
     'response': {'status': 400, 'reason': '', 'headers': [['content-type', 'application/problem+json'],
                                                           ['transfer-encoding', 'chunked'], ['connection', 'close']]}}]}
NOT_FOUND = {'path': '/nope', 'expected': {'status': 404, 'content_type': 'application/json',
                                           'request': {'method': 'GET'}}}
INVALID = {'path': '/owners', 'expected': {'status': 400, 'content_type': 'application/problem+json',
                                           'request': {'method': 'POST'}}}


class Parity(unittest.TestCase):
    def test_golden_transport_by_method_path_status_and_media_type(self):
        self.assertEqual(st.golden_transport(GOLDEN, NOT_FOUND),
                         ({'reason': '', 'framing': 'chunked', 'connection': 'keep'}, ['json 404']))
        self.assertEqual(st.golden_transport(GOLDEN, INVALID)[0],
                         {'reason': '', 'framing': 'chunked', 'connection': 'close'})
        with self.assertRaises(SystemExit):
            st.golden_transport(GOLDEN, {**INVALID, 'path': '/elsewhere'})

    def test_lifetime_needs_header_and_behaviour_to_agree(self):
        def result(connection, reused):
            return {'first': {'reason': '', 'framing': 'chunked', 'connection': connection}, 'reused': reused,
                    'second_request': {'outcome': 'answered' if reused else 'refused'}}
        self.assertEqual(st.observed_transport(result('close', False))['connection'], 'close')
        self.assertEqual(st.observed_transport(result(None, True))['connection'], 'keep')
        self.assertTrue(st.observed_transport(result(None, False))['connection'].startswith('inconsistent'))
        self.assertTrue(st.observed_transport(result('close', True))['connection'].startswith('inconsistent'))

    def test_go_today_fails_the_400(self):
        expected = st.golden_transport(GOLDEN, INVALID)[0]
        today = {'reason': 'Bad Request', 'framing': 'content-length', 'connection': 'keep'}
        self.assertEqual(len(st.parity_problems(expected, today)), 3)
        self.assertEqual(st.parity_problems(expected, dict(expected)), [])

    def test_go_parity_server_end_to_end(self):
        port = serve([LENGTH.replace(b'400 Bad Request', b'400 ').replace(b'Content-Length: 4', b'Connection: close\r\n'
                      b'Transfer-Encoding: chunked').replace(b'{}{}', b'4\r\n{}{}\r\n0\r\n\r\n')], 1)
        seen = st.observed_transport(st.exchange(port, SPEC))
        self.assertEqual(st.parity_problems(st.golden_transport(GOLDEN, INVALID)[0], seen), [])


if __name__ == '__main__':
    unittest.main()
