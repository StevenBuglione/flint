"""flint lsp: diagnostics from the pinned compiler and its compile server, hover, definition and completion from
the API index (Milestone 9, ADR-027)."""
import json
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from test_flint_cli import FLINT, ROOT, environment, flint_json, setUpModule  # noqa: F401


class LspClient:
    def __init__(self, root):
        self.process = subprocess.Popen([str(FLINT), 'lsp'], cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, env=environment())
        self.next = 0

    def send(self, message):
        body = json.dumps(message).encode()
        self.process.stdin.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
        self.process.stdin.flush()

    def receive(self):
        length = 0
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise EOFError('flint lsp closed its output')
            if line in (b'\r\n', b'\n'):
                break
            if line.lower().startswith(b'content-length:'):
                length = int(line.split(b':')[1])
        return json.loads(self.process.stdout.read(length))

    def request(self, method, params):
        self.next += 1
        self.send({'jsonrpc': '2.0', 'id': self.next, 'method': method, 'params': params})
        while True:
            message = self.receive()
            if message.get('id') == self.next:
                return message

    def notify(self, method, params):
        self.send({'jsonrpc': '2.0', 'method': method, 'params': params})

    def diagnostics(self, uri):
        while True:
            message = self.receive()
            if message.get('method') == 'textDocument/publishDiagnostics' and message['params']['uri'] == uri:
                return message['params']['diagnostics']


class LspTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-lsp-')
        status, document = flint_json('new', 'shop', cwd=cls.temporary.name)
        assert status == 0, document
        cls.project = Path(cls.temporary.name) / 'shop'
        cls.client = LspClient(cls.project)
        cls.initialized = cls.client.request('initialize', {'processId': None,
                                                           'rootUri': cls.project.as_uri(), 'capabilities': {}})
        cls.client.notify('initialized', {})
        cls.app = cls.project / 'src/shop/app.d'
        cls.uri = cls.app.as_uri()

    @classmethod
    def tearDownClass(cls):
        cls.client.request('shutdown', None)
        cls.client.notify('exit', None)
        cls.client.process.wait(timeout=30)
        cls.temporary.cleanup()

    def open(self, text):
        self.client.notify('textDocument/didOpen', {'textDocument': {'uri': self.uri, 'languageId': 'd',
                                                                     'version': 1, 'text': text}})
        return self.client.diagnostics(self.uri)

    def test_1_capabilities(self):
        capabilities = self.initialized['result']['capabilities']
        self.assertEqual(capabilities['textDocumentSync'], 1)
        self.assertTrue(capabilities['hoverProvider'] and capabilities['definitionProvider'])

    def test_2_diagnostics_follow_the_unsaved_buffer(self):
        text = self.app.read_text()
        self.assertEqual(self.open(text), [])
        broken = text.replace('    writeln(greet(', '    int lsp = undefinedName;\n    writeln(greet(')
        started = time.monotonic()
        self.client.notify('textDocument/didChange', {'textDocument': {'uri': self.uri, 'version': 2},
                                                      'contentChanges': [{'text': broken}]})
        found = self.client.diagnostics(self.uri)
        elapsed = time.monotonic() - started
        self.assertEqual(len(found), 1, found)
        line = broken.splitlines().index('    int lsp = undefinedName;')
        self.assertEqual(found[0]['range']['start']['line'], line)
        self.assertIn('undefinedName', found[0]['message'])
        self.assertEqual(found[0]['severity'], 1)
        self.assertLess(elapsed, 30)
        self.assertEqual(self.app.read_text(), text)  # the file on disk is untouched
        unsafe = text.replace('@safe:\n', '', 1)
        self.client.notify('textDocument/didChange', {'textDocument': {'uri': self.uri, 'version': 3},
                                                      'contentChanges': [{'text': unsafe}]})
        codes = [d['code'] for d in self.client.diagnostics(self.uri)]
        self.assertIn('FLINT-E0501', codes)
        self.client.notify('textDocument/didChange', {'textDocument': {'uri': self.uri, 'version': 4},
                                                      'contentChanges': [{'text': text}]})
        self.assertEqual(self.client.diagnostics(self.uri), [])

    def test_3_hover_definition_and_completion_answer_from_the_pinned_api(self):
        text = self.app.read_text()
        self.open(text)
        line = next(i for i, l in enumerate(text.splitlines()) if 'import flint.config' in l)
        column = text.splitlines()[line].index(' load') + 2
        position = {'textDocument': {'uri': self.uri}, 'position': {'line': line, 'character': column}}
        hover = self.client.request('textDocument/hover', position)['result']
        self.assertIn('load(T)(ref scope const ConfigOptions options)', hover['contents']['value'])
        definition = self.client.request('textDocument/definition', position)['result']
        self.assertTrue(definition['uri'].endswith('packages/config/source/flint/config/package.d'))
        self.assertTrue(Path(definition['uri'][len('file://'):]).is_file())
        typing = text.replace('    ConfigOptions config;', '    ConfigOptions config;\n    ConfigurationPro', 1)
        self.client.notify('textDocument/didChange', {'textDocument': {'uri': self.uri, 'version': 9},
                                                      'contentChanges': [{'text': typing}]})
        self.client.diagnostics(self.uri)
        row = typing.splitlines().index('    ConfigurationPro')
        items = self.client.request('textDocument/completion', {'textDocument': {'uri': self.uri},
                                                                'position': {'line': row, 'character': 20}})
        self.assertIn('ConfigurationProperties', [item['label'] for item in items['result']['items']])


if __name__ == '__main__':
    unittest.main()
