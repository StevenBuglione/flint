"""Milestone 10 (ADR-028): compile-time conditional registration driven by config/application.toml, starters
and `flint add`."""
import json
import signal
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from test_flint_cli import FLINT, ROOT, codes, environment, flint_json, setUpModule  # noqa: F401

CONDITIONAL_APP = '''module shop.app;

import flint.di : AppContext, AutoConfiguration, ConditionalOnConfig, Service;
import std.stdio : writeln;

@safe:

@ConditionalOnConfig("database") @Service final class Database
{
}

@ConditionalOnConfig("cache") @Service final class Cache
{
}

alias Defaults = AutoConfiguration!(Database, Cache);

int main()
{
    AppContext!(Defaults) context;
    if (context.initialize().code != 0)
        return 1;
    scope (exit)
        context.shutdown();
    writeln("database ", __traits(compiles, context.get!Database()), " cache ", __traits(compiles, context.get!Cache()));
    return 0;
}
'''


class ConditionalConfigTests(unittest.TestCase):
    def test_sections_of_application_toml_switch_beans_at_compile_time(self):
        with tempfile.TemporaryDirectory(prefix='flint-starters-') as temporary:
            status, document = flint_json('new', 'shop', cwd=temporary)
            self.assertEqual(status, 0, document)
            project = Path(temporary) / 'shop'
            manifest = project / 'flint.toml'
            manifest.write_text(manifest.read_text().replace('[dependencies]\n', '[dependencies]\n"flint:di" = {}\n'))
            for stale in (project / 'src' / 'shop').glob('*.d'):
                stale.unlink()
            (project / 'src' / 'shop' / 'app.d').write_text(CONDITIONAL_APP)
            for test in (project / 'test').rglob('*.d'):
                test.unlink()
            (project / 'config' / 'application.toml').write_text('[app]\ngreeting = "Hello"\n\n[database]\nurl = "x"\n')
            self.assertEqual(flint_json('lock', cwd=project)[0], 0)
            result = subprocess.run([str(FLINT), 'run'], cwd=project, capture_output=True, text=True,
                                    env=environment())
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('database true cache false', result.stdout)
            (project / 'config' / 'application.toml').write_text('[cache]\nsize = 1\n')
            result = subprocess.run([str(FLINT), 'run'], cwd=project, capture_output=True, text=True,
                                    env=environment())
            self.assertIn('database false cache true', result.stdout, result.stderr)



def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


class StarterWebTests(unittest.TestCase):
    def test_flint_add_wires_the_dependency_the_configuration_and_the_lock(self):
        with tempfile.TemporaryDirectory(prefix='flint-add-') as temporary:
            self.assertEqual(flint_json('new', 'shop', cwd=temporary)[0], 0)
            project = Path(temporary) / 'shop'
            status, document = flint_json('add', 'web', cwd=project)
            self.assertEqual(status, 0, document)
            self.assertEqual(document['added'], ['flint:starter-web'])
            self.assertEqual(document['sections'], ['server'])
            self.assertIn('"flint:starter-web" = {}', (project / 'flint.toml').read_text())
            self.assertIn('[server]\naddress = "127.0.0.1"', (project / 'config/application.toml').read_text())
            self.assertIn('name = "flint:starter-web"', (project / 'flint.lock').read_text())
            status, document = flint_json('add', 'starter-web', cwd=project)
            self.assertEqual((status, document['added'], document['present']), (0, [], ['flint:starter-web']))
            status, document = flint_json('add', 'webb', cwd=project)
            self.assertEqual((status, codes(document)), (4, ['FLINT-E0009']))

    def test_the_example_serves_an_ordinary_handler_with_configuration(self):
        # Built in place: the example's lock is a workspace lock.
        project = ROOT / 'starters/web/example'
        built = subprocess.run([str(FLINT), 'build', '--json'], cwd=project, capture_output=True, text=True,
                               env=environment())
        self.assertEqual(built.returncode, 0, built.stdout[-3000:])
        port = free_port()
        process = subprocess.Popen([str(project / '.flint/build/dev/shop'), f'--set=server.port={port}'],
                                   cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            body = None
            for _ in range(100):
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/greetings/Ada', timeout=2) as r:
                        body = json.loads(r.read())
                        break
                except OSError:
                    time.sleep(0.05)
            self.assertEqual(body, {'text': 'Hello, Ada!'})
            # The front end: files, client-side routes, and /api/ left to the controllers.
            for path, status, media in [('/', 200, 'text/html'), ('/app.js', 200, 'text/javascript'),
                                        ('/orders/42', 200, 'text/html'), ('/api/nothing', 404, 'application/json')]:
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}', timeout=5) as r:
                        got = (r.status, r.headers.get('Content-Type', ''))
                except urllib.error.HTTPError as error:
                    got = (error.code, error.headers.get('Content-Type', ''))
                self.assertEqual(got[0], status, path)
                self.assertTrue(got[1].startswith(media), (path, got))
        finally:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        misspelt = subprocess.run([str(project / '.flint/build/dev/shop'), '--set=server.prot=1'], cwd=project,
                                  capture_output=True, text=True, timeout=10)
        self.assertEqual(misspelt.returncode, 3, misspelt.stderr)
        self.assertIn('server.prot', misspelt.stderr)


class StarterObservabilityTests(unittest.TestCase):
    def test_health_readiness_and_an_application_counter_are_served(self):
        project = ROOT / 'starters/observability/example'
        built = subprocess.run([str(FLINT), 'build', '--json'], cwd=project, capture_output=True, text=True,
                               env=environment())
        self.assertEqual(built.returncode, 0, built.stdout[-3000:])
        port = free_port()
        process = subprocess.Popen([str(project / '.flint/build/dev/status'), f'--set=server.port={port}'],
                                   cwd=project, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def call(path, method='GET'):
            request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', method=method,
                                             data=b'' if method == 'POST' else None)
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, response.read().decode()

        try:
            for _ in range(100):
                try:
                    call('/actuator/health/live')
                    break
                except OSError:
                    time.sleep(0.05)
            self.assertEqual(call('/actuator/health/live'), (200, '{"status":"UP"}'))
            self.assertEqual(call('/actuator/health/ready'), (200, '{"status":"UP"}'))
            self.assertEqual(call('/api/jobs', 'POST'), (201, '{"total":1}'))
            self.assertEqual(call('/api/jobs', 'POST'), (201, '{"total":2}'))
            status, metrics = call('/actuator/metrics')
            self.assertEqual(status, 200)
            self.assertIn('# TYPE jobs_accepted_total counter\njobs_accepted_total 2\n', metrics)
        finally:
            process.kill()
            process.wait()


class StarterDataTests(unittest.TestCase):
    def test_the_notes_example_migrates_validates_and_keeps_data_across_restarts(self):
        project = ROOT / 'starters/data/example'
        built = subprocess.run([str(FLINT), 'build', '--json'], cwd=project, capture_output=True, text=True,
                               env=environment())
        self.assertEqual(built.returncode, 0, built.stdout[-3000:])
        with tempfile.TemporaryDirectory(prefix='flint-notes-') as temporary:
            port = free_port()
            command = [str(project / '.flint/build/dev/notes'), f'--set=server.port={port}',
                       f'--set=database.url=file:{temporary}/notes.db']

            def call(path, method='GET', body=None):
                data = json.dumps(body).encode() if body is not None else None
                request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', method=method, data=data,
                                                 headers={'Content-Type': 'application/json'} if data else {})
                try:
                    with urllib.request.urlopen(request, timeout=5) as response:
                        return response.status, json.loads(response.read() or b'null')
                except urllib.error.HTTPError as error:
                    return error.code, json.loads(error.read() or b'null')

            def started():
                process = subprocess.Popen(command, cwd=project, stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL)
                for _ in range(100):
                    try:
                        call('/api/notes/0')
                        return process
                    except OSError:
                        time.sleep(0.05)
                process.kill()
                self.fail('the notes example did not start')

            process = started()
            try:
                self.assertEqual(call('/api/notes', 'POST', {'title': 'First', 'body': 'hello'}),
                                 (201, {'id': 1, 'title': 'First', 'body': 'hello'}))
                status, body = call('/api/notes', 'POST', {'title': '', 'body': 'x'})
                self.assertEqual((status, body['field']), (400, 'title'))
                self.assertEqual(call('/api/notes/1')[0], 200)
                self.assertEqual(call('/api/notes/99')[0], 404)
            finally:
                process.kill()
                process.wait()
            process = started()
            try:
                self.assertEqual(call('/api/notes/1'), (200, {'id': 1, 'title': 'First', 'body': 'hello'}))
                self.assertEqual(call('/api/notes/1', 'DELETE')[0], 204)
                self.assertEqual(call('/api/notes/1')[0], 404)
            finally:
                process.kill()
                process.wait()


class OpenApiTests(unittest.TestCase):
    def test_flint_openapi_documents_the_controllers_and_writes_a_typescript_client(self):
        with tempfile.TemporaryDirectory(prefix='flint-openapi-') as temporary:
            document_path = Path(temporary) / 'openapi.json'
            client_path = Path(temporary) / 'client.ts'
            result = subprocess.run([str(FLINT), 'openapi', '-C', str(ROOT / 'starters/web/example'), '-o',
                                     str(document_path), '--typescript', str(client_path)], capture_output=True,
                                    text=True, env=environment())
            self.assertEqual(result.returncode, 0, result.stderr[-3000:])
            document = json.loads(document_path.read_text())
            self.assertEqual(document['info'], {'title': 'shop', 'version': '0.1.0'})
            get = document['paths']['/api/greetings/{name}']['get']
            self.assertEqual(get['operationId'], 'GreetingController.get')
            self.assertEqual(get['parameters'][0]['in'], 'path')
            schema = get['responses']['200']['content']['application/json']['schema']
            self.assertEqual((schema['title'], schema['properties']['text']['type']), ('Message', 'string'))
            client = client_path.read_text()
            self.assertIn('export interface Message {\n  text: string;\n}', client)
            self.assertIn('greetingGet(name: string): Promise<Message>', client)
            refused = flint_json('openapi', cwd=ROOT / 'benchmarks/vibe/reference/flint/cli-todo')
            self.assertEqual(codes(refused[1]), ['FLINT-E0004'])


UNNEEDED = '''module shop.orders;

import flint.starter_web : Get, PathVariable, Post, RequestContext, RestController, Result, Service;

@safe:

@Service final class Orders
{
}

@Service final class Audit
{
    Orders orders;
}

@RestController("/api/orders")
struct OrderController
{
    private Orders orders;

    this(Orders orders)
    {
        this.orders = orders;
    }

    @Get("/:id")
    Result!string get(@PathVariable("id") scope string id) nothrow @nogc
    {
        return Result!string(id);
    }

    @Post("")
    Result!string post(ref scope RequestContext context)
    {
        return Result!string("created");
    }
}
'''


class ConventionTests(unittest.TestCase):
    def test_the_starter_example_has_no_handler_attributes(self):
        status, document = flint_json('check', cwd=ROOT / 'starters/web/example')
        self.assertEqual(status, 0, document)
        self.assertEqual((document['handlers'], document['handler_attributes']), (1, 0))

    def test_unneeded_attributes_and_nullable_class_fields_are_flagged(self):
        with tempfile.TemporaryDirectory(prefix='flint-conventions-') as temporary:
            self.assertEqual(flint_json('new', 'shop', cwd=temporary)[0], 0)
            project = Path(temporary) / 'shop'
            self.assertEqual(flint_json('add', 'web', cwd=project)[0], 0)
            (project / 'src/shop/orders.d').write_text(UNNEEDED)
            status, document = flint_json('check', cwd=project)
            self.assertEqual(status, 1)
            messages = sorted(item['code'] + ' ' + item['message'] for item in document['diagnostics']
                              if item['severity'] == 'error' and item['code'] in ('FLINT-E0530', 'FLINT-E0531'))
            self.assertEqual(messages, [
                'FLINT-E0530 field `orders` of class type `Orders` in Audit may be null',
                'FLINT-E0531 OrderController.get: `nothrow`/`@nogc` changes nothing here: another handler of '
                'OrderController may throw or allocate, so the controller runs on a worker thread',
                'FLINT-E0531 OrderController.get: `scope` is unneeded: the framework passes this argument as an '
                'owned value'])
            self.assertEqual((document['handlers'], document['handler_attributes']), (2, 4))


if __name__ == '__main__':
    unittest.main()
