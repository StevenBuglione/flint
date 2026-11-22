"""Oracle for rest-notes: a minimal Python solution that proves the acceptance test is sound. Not a benchmark entry."""
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MIGRATIONS = [
    'create table users (id integer primary key, username text unique not null, salt blob not null, hash blob not null)',
    'create table notes (id integer primary key, owner integer not null references users(id), title text not null, '
    'body text not null)',
    'create table secrets (key blob not null)',
]
USERNAME = re.compile(r'^[a-z0-9_]{3,32}$')
lock = threading.Lock()
database = sqlite3.connect(os.environ.get('DATABASE_PATH', 'notes.db'), check_same_thread=False)
database.execute('create table if not exists schema_version (version integer not null)')
current = database.execute('select coalesce(max(version), 0) from schema_version').fetchone()[0]
for version, statement in enumerate(MIGRATIONS[current:], current + 1):
    database.execute(statement)
    database.execute('insert into schema_version values (?)', (version,))
if not database.execute('select count(*) from secrets').fetchone()[0]:
    database.execute('insert into secrets values (?)', (secrets.token_bytes(32),))
database.commit()
KEY = database.execute('select key from secrets').fetchone()[0]


def token_for(user):
    signature = hmac.new(KEY, str(user).encode(), hashlib.sha256).hexdigest()
    return f'{user}.{signature}'


def user_of(header):
    if not header or not header.startswith('Bearer '):
        return None
    user, _, signature = header[7:].partition('.')
    if user.isdigit() and hmac.compare_digest(token_for(int(user)), header[7:]):
        return int(user)
    return None


def invalid(field, message):
    return 400, {'error': message, 'field': field}


def fields(body, rules):
    if not isinstance(body, dict):
        return None, invalid(None, 'malformed JSON')
    for name, check, message in rules:
        if not isinstance(body.get(name), str) or not check(body[name]):
            return None, invalid(name, message)
    return body, None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *arguments):
        pass

    def reply(self, status, body=None):
        data = b'' if body is None else json.dumps(body).encode()
        self.send_response(status)
        if body is not None:
            self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        try:
            return json.loads(self.rfile.read(int(self.headers.get('Content-Length') or 0)) or b'null')
        except ValueError:
            return None

    def route(self, method):
        with lock:
            status, body = self.dispatch(method, self.path)
        self.reply(status, body)

    def do_GET(self):  # noqa: N802
        self.route('GET')

    def do_POST(self):  # noqa: N802
        self.route('POST')

    def do_PUT(self):  # noqa: N802
        self.route('PUT')

    def do_DELETE(self):  # noqa: N802
        self.route('DELETE')

    def dispatch(self, method, path):
        credentials = [('username', USERNAME.match, 'username must be 3 to 32 of a-z, 0-9 and _'),
                       ('password', lambda p: len(p) >= 8, 'password must have at least 8 characters')]
        if (method, path) == ('POST', '/api/users'):
            body, error = fields(self.body(), credentials)
            if error:
                return error
            if database.execute('select 1 from users where username = ?', (body['username'],)).fetchone():
                return 409, {'error': 'username taken'}
            salt = secrets.token_bytes(16)
            digest = hashlib.pbkdf2_hmac('sha256', body['password'].encode(), salt, 100_000)
            cursor = database.execute('insert into users (username, salt, hash) values (?, ?, ?)',
                                      (body['username'], salt, digest))
            database.commit()
            return 201, {'id': cursor.lastrowid, 'username': body['username']}
        if (method, path) == ('POST', '/api/login'):
            body, error = fields(self.body(), [(n, lambda v: True, m) for n, _, m in credentials])
            if error:
                return error
            row = database.execute('select id, salt, hash from users where username = ?', (body['username'],)).fetchone()
            if not row or not hmac.compare_digest(row[2], hashlib.pbkdf2_hmac(
                    'sha256', body['password'].encode(), row[1], 100_000)):
                return 401, {'error': 'wrong credentials'}
            return 200, {'token': token_for(row[0])}
        if not path.startswith('/api/notes'):
            return 404, {'error': 'not found'}
        user = user_of(self.headers.get('Authorization'))
        if user is None:
            return 401, {'error': 'unauthorized'}
        note_rules = [('title', lambda t: 1 <= len(t) <= 100, 'title must have 1 to 100 characters'),
                      ('body', lambda b: len(b) <= 10000, 'body must have at most 10000 characters')]
        if path == '/api/notes':
            if method == 'GET':
                rows = database.execute('select id, title, body from notes where owner = ? order by id', (user,))
                return 200, [{'id': i, 'title': t, 'body': b} for i, t, b in rows]
            if method == 'POST':
                body, error = fields(self.body(), note_rules)
                if error:
                    return error
                cursor = database.execute('insert into notes (owner, title, body) values (?, ?, ?)',
                                          (user, body['title'], body['body']))
                database.commit()
                return 201, {'id': cursor.lastrowid, 'title': body['title'], 'body': body['body']}
        match = re.fullmatch(r'/api/notes/(\d+)', path)
        if not match:
            return 404, {'error': 'not found'}
        note = int(match[1])
        row = database.execute('select id, title, body from notes where id = ? and owner = ?', (note, user)).fetchone()
        if not row:
            return 404, {'error': 'not found'}
        if method == 'GET':
            return 200, {'id': row[0], 'title': row[1], 'body': row[2]}
        if method == 'PUT':
            body, error = fields(self.body(), note_rules)
            if error:
                return error
            database.execute('update notes set title = ?, body = ? where id = ?', (body['title'], body['body'], note))
            database.commit()
            return 200, {'id': note, 'title': body['title'], 'body': body['body']}
        if method == 'DELETE':
            database.execute('delete from notes where id = ?', (note,))
            database.commit()
            return 204, None
        return 405, {'error': 'method not allowed'}


ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('PORT', '8080'))), Handler).serve_forever()
