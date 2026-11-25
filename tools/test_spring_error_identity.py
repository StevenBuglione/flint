"""Unit tests of the error-identity check's wire handling: `python3 tools/test_spring_error_identity.py`."""
import socket
import threading
import unittest

import spring_error_identity as identity
from gs_rest_service_errors import Request, Run


class Masking(unittest.TestCase):
    def test_masks_the_clock_and_keeps_every_length(self):
        wire = (b'HTTP/1.1 404 \r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n'
                b'Date: Wed, 25 Nov 2026 07:12:34 GMT\r\n\r\n'
                b'4f\r\n{"timestamp":"2026-11-25T07:12:34.567Z","status":404,"error":"Not Found","path":"/nope"}\r\n'
                b'0\r\n\r\n')
        masked = identity.masked(wire)
        self.assertEqual(len(masked), len(wire))
        self.assertIn(b'Date: ' + b'0' * 29 + b'\r\n', masked)  # the whole value: the weekday changes too
        self.assertIn(b'"timestamp":"0000-00-00T00:00:00.000Z"', masked)
        self.assertIn(b'4f\r\n', masked)  # chunk sizes are compared, not masked
        later = wire.replace(b'07:12:34.567', b'09:59:01.002')
        later = later.replace(b'Wed, 25 Nov 2026 07:12:34', b'Thu, 26 Nov 2026 09:59:01')
        self.assertEqual(identity.masked(later), masked)
        self.assertNotEqual(identity.masked(wire.replace(b'"/nope"', b'"/nopf"')), masked)

    def test_masks_the_whitelabel_date(self):
        page = b"<div id='created'>Wed Nov 25 07:12:34 UTC 2026</div>"
        self.assertEqual(identity.masked(page), b"<div id='created'>Wed Nov 00 00:00:00 UTC 0000</div>")


class Requests(unittest.TestCase):
    def test_fields_are_sent_as_written(self):
        request = Request('two', 'GET', '/café', [('Accept', 'application/json'), ('Accept', '*/*')])
        self.assertEqual(identity.request_bytes('http://127.0.0.1:8080', request),
                         'GET /café HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nAccept: application/json\r\n'
                         'Accept: */*\r\n\r\n'.encode())

    def test_a_body_gets_its_length_unless_the_case_gives_one(self):
        posted = identity.request_bytes('http://h:1', Request('p', 'POST', '/x', [], b'{}'))
        self.assertTrue(posted.endswith(b'Content-Length: 2\r\n\r\n{}'))
        given = identity.request_bytes('http://h:1', Request('p', 'PATCH', '/x', [('Content-Length', '0')]))
        self.assertEqual(given.count(b'Content-Length'), 1)

    def test_run_arguments_follow_each_implementation_prefix(self):
        run = Run('r', {'web.error.include-path': 'never'}, [])
        self.assertEqual(run.args('java'), ['--spring.web.error.include-path=never'])
        self.assertEqual(run.args('flint'), ['--flint.web.error.include-path=never'])


class Exchange(unittest.TestCase):
    """exchange() against a one-connection server: the response's exact bytes and the connection's lifetime."""

    RESPONSE = b'HTTP/1.1 404 \r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n'

    def serve(self, keep):
        listener = socket.create_server(('127.0.0.1', 0))
        port = listener.getsockname()[1]

        def answer():
            connection, _ = listener.accept()
            with connection:
                connection.recv(65536)
                connection.sendall(self.RESPONSE)
                if keep:
                    connection.recv(65536)
                    connection.sendall(b'HTTP/1.1 404 \r\nContent-Length: 0\r\n\r\n')
            listener.close()

        thread = threading.Thread(target=answer)
        thread.start()
        return f'http://127.0.0.1:{port}', thread

    def test_wire_bytes_and_a_kept_connection(self):
        origin, thread = self.serve(keep=True)
        status, _, _, body, wire, lifetime = identity.exchange(origin, Request('n', 'GET', '/nope'))
        thread.join()
        self.assertEqual((status, body, wire, lifetime), (404, b'{}', self.RESPONSE, 'keep'))

    def test_a_closed_connection(self):
        origin, thread = self.serve(keep=False)
        *_, wire, lifetime = identity.exchange(origin, Request('n', 'GET', '/nope'))
        thread.join()
        self.assertEqual((wire, lifetime), (self.RESPONSE, 'close'))


if __name__ == '__main__':
    unittest.main()
