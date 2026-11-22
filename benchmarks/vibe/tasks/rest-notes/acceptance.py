"""Acceptance test for the notes REST API (TASK.md)."""
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from vibelib import Recorder, free_port, http, stop, wait_for_port


def start(program, directory, port):
    log = open(Path(directory) / 'service.log', 'ab')  # noqa: SIM115 - closed with the process
    process = subprocess.Popen(program.command(), cwd=directory, stdout=log, stderr=log,
                               env=program.environment(PORT=port, DATABASE_PATH=Path(directory) / 'data' / 'notes.db'))
    log.close()
    return process, wait_for_port(port, process)


def log_tail(directory):
    path = Path(directory) / 'service.log'
    return path.read_text(errors='replace')[-2000:] if path.is_file() else ''


def checks(program):
    r = Recorder()
    STATE.clear()
    with tempfile.TemporaryDirectory(prefix='vibe-rest-') as directory:
        (Path(directory) / 'data').mkdir()
        port = free_port()
        process, ready = start(program, directory, port)
        if not r.check('starts and listens on PORT', ready, log_tail(directory)):
            stop(process)
            return r.results
        try:
            first_run(r, port)
        except Exception as error:  # noqa: BLE001 - a crash fails the remaining checks, not the harness
            r.crashed('first run', error)
        code, _ = stop(process)
        database = Path(directory) / 'data' / 'notes.db'
        r.check('creates the SQLite database at DATABASE_PATH', database.is_file())
        if database.is_file():
            content = database.read_bytes()
            r.check('stores no plain-text password', b'correct horse battery' not in content)
            try:
                with sqlite3.connect(database) as connection:
                    tables = {row[0] for row in connection.execute("select name from sqlite_master where type='table'")}
                r.check('the database holds tables', len(tables) >= 2, tables)
            except sqlite3.Error as error:
                r.crashed('the database is SQLite', error)
        process, ready = start(program, directory, port)
        if r.check('restarts against its own database', ready, log_tail(directory)):
            try:
                second_run(r, port)
            except Exception as error:  # noqa: BLE001
                r.crashed('second run', error)
        stop(process)
    return r.results


STATE = {}


def first_run(r, port):
    status, body, _ = http(port, 'POST', '/api/users', {'username': 'ada_l', 'password': 'correct horse battery'})
    r.equal('register: 201', status, 201)
    r.check('register: returns id and username', isinstance(body, dict) and isinstance(body.get('id'), int)
            and body.get('username') == 'ada_l', body)
    status, _, _ = http(port, 'POST', '/api/users', {'username': 'ada_l', 'password': 'another password'})
    r.equal('register: duplicate is 409', status, 409)
    for name, payload, invalid in [
            ('short username', {'username': 'ab', 'password': 'long enough'}, 'username'),
            ('bad characters', {'username': 'Ada!', 'password': 'long enough'}, 'username'),
            ('short password', {'username': 'grace', 'password': 'short'}, 'password'),
            ('missing password', {'username': 'grace'}, 'password'),
            ('wrong type', {'username': 42, 'password': 'long enough'}, 'username')]:
        status, body, _ = http(port, 'POST', '/api/users', payload)
        r.check(f'register: {name} is 400 naming {invalid}', status == 400 and isinstance(body, dict)
                and body.get('field') == invalid and isinstance(body.get('error'), str), (status, body))
    status, body, _ = http(port, 'POST', '/api/users', raw=b'{"username": ')
    r.check('register: malformed JSON is 400 with field null', status == 400 and isinstance(body, dict)
            and 'field' in body and body['field'] is None, (status, body))
    http(port, 'POST', '/api/users', {'username': 'grace', 'password': 'hopper hopper'})

    status, _, _ = http(port, 'POST', '/api/login', {'username': 'ada_l', 'password': 'wrong password'})
    r.equal('login: wrong password is 401', status, 401)
    status, _, _ = http(port, 'POST', '/api/login', {'username': 'nobody', 'password': 'whatever123'})
    r.equal('login: unknown user is 401', status, 401)
    status, body, _ = http(port, 'POST', '/api/login', {'username': 'ada_l', 'password': 'correct horse battery'})
    token = body.get('token') if isinstance(body, dict) else None
    if not r.check('login: 200 with a token', status == 200 and isinstance(token, str) and token, (status, body)):
        return
    _, other, _ = http(port, 'POST', '/api/login', {'username': 'grace', 'password': 'hopper hopper'})
    other_token = other.get('token') if isinstance(other, dict) else None
    STATE.update(token=token, other=other_token)

    status, _, _ = http(port, 'GET', '/api/notes')
    r.equal('notes: no token is 401', status, 401)
    status, _, _ = http(port, 'GET', '/api/notes', token='not-a-token')
    r.equal('notes: invalid token is 401', status, 401)
    status, body, _ = http(port, 'GET', '/api/notes', token=token)
    r.check('notes: empty list at first', status == 200 and body == [], (status, body))

    created = []
    for title, text in [('First', 'one'), ('Second', ''), ('Third', 'x' * 10000)]:
        status, body, _ = http(port, 'POST', '/api/notes', {'title': title, 'body': text}, token=token)
        ok = status == 201 and isinstance(body, dict) and body.get('title') == title and body.get('body') == text
        r.check(f'create note {title!r}: 201 with the note', ok and isinstance(body.get('id'), int), (status, body))
        if ok:
            created.append(body)
    for name, payload, invalid in [('empty title', {'title': '', 'body': 'b'}, 'title'),
                                   ('long title', {'title': 't' * 101, 'body': 'b'}, 'title'),
                                   ('long body', {'title': 't', 'body': 'b' * 10001}, 'body'),
                                   ('missing body', {'title': 't'}, 'body')]:
        status, body, _ = http(port, 'POST', '/api/notes', payload, token=token)
        r.check(f'create note: {name} is 400 naming {invalid}', status == 400 and isinstance(body, dict)
                and body.get('field') == invalid, (status, body))
    status, body, _ = http(port, 'GET', '/api/notes', token=token)
    r.check('list: the caller\'s notes, oldest first', status == 200 and isinstance(body, list)
            and [n.get('title') for n in body] == ['First', 'Second', 'Third'], (status, body and str(body)[:200]))
    if len(created) < 2:
        return
    first, second = created[0], created[1]
    STATE['first'] = first['id']
    status, body, _ = http(port, 'GET', f"/api/notes/{first['id']}", token=token)
    r.check('get: 200 with the note', status == 200 and body == first, (status, body))
    status, body, _ = http(port, 'PUT', f"/api/notes/{first['id']}", {'title': 'First!', 'body': 'edited'}, token=token)
    r.check('update: 200 with the new note', status == 200 and isinstance(body, dict) and body.get('title') == 'First!'
            and body.get('body') == 'edited' and body.get('id') == first['id'], (status, body))
    status, body, _ = http(port, 'PUT', f"/api/notes/{first['id']}", {'title': '', 'body': 'x'}, token=token)
    r.check('update: invalid is 400', status == 400 and isinstance(body, dict) and body.get('field') == 'title',
            (status, body))
    status, body, text = http(port, 'DELETE', f"/api/notes/{second['id']}", token=token)
    r.check('delete: 204 with an empty body', status == 204 and not text.strip(), (status, text))
    status, _, _ = http(port, 'GET', f"/api/notes/{second['id']}", token=token)
    r.equal('delete: then 404', status, 404)
    status, _, _ = http(port, 'DELETE', f"/api/notes/{second['id']}", token=token)
    r.equal('delete: twice is 404', status, 404)
    status, _, _ = http(port, 'GET', '/api/notes/999999', token=token)
    r.equal('get: unknown id is 404', status, 404)
    if other_token:
        status, body, _ = http(port, 'GET', f"/api/notes/{first['id']}", token=other_token)
        r.equal('isolation: another user\'s note is 404', status, 404)
        status, _, _ = http(port, 'PUT', f"/api/notes/{first['id']}", {'title': 'mine', 'body': ''}, token=other_token)
        r.equal('isolation: updating another user\'s note is 404', status, 404)
        status, _, _ = http(port, 'DELETE', f"/api/notes/{first['id']}", token=other_token)
        r.equal('isolation: deleting another user\'s note is 404', status, 404)
        status, body, _ = http(port, 'GET', '/api/notes', token=other_token)
        r.check('isolation: the other user lists no notes', status == 200 and body == [], (status, body))


def second_run(r, port):
    token = STATE.get('token')
    status, body, _ = http(port, 'GET', '/api/notes', token=token)
    r.check('restart: the token is still valid and the notes survive', status == 200 and isinstance(body, list)
            and [n.get('title') for n in body] == ['First!', 'Third'], (status, str(body)[:200]))
    status, body, _ = http(port, 'POST', '/api/login', {'username': 'ada_l', 'password': 'correct horse battery'})
    r.check('restart: login still works', status == 200 and isinstance(body, dict) and body.get('token'), (status, body))
    status, body, _ = http(port, 'POST', '/api/notes', {'title': 'Fourth', 'body': ''}, token=token)
    r.check('restart: new ids do not collide', status == 201 and isinstance(body, dict)
            and body.get('id') not in (STATE.get('first'), None), (status, body))
