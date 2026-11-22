"""Acceptance test for the spool-directory worker (TASK.md)."""
import hashlib
import json
import subprocess
import tempfile
import time
from pathlib import Path

from vibelib import Recorder, stop, write_atomically


def wait_until(condition, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.05)
    return condition()


def start(program, spool, *extra):
    return subprocess.Popen(program.command('--spool', spool, *extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, env=program.environment())


def checks(program):
    r = Recorder()
    with tempfile.TemporaryDirectory(prefix='vibe-worker-') as directory:
        try:
            run_checks(r, program, Path(directory))
        except Exception as error:  # noqa: BLE001 - a crash fails the remaining checks, not the harness
            r.crashed('run', error)
    return r.results


def run_checks(r, program, root):
    for value in ('0', '65', 'many'):
        result = subprocess.run(program.command('--spool', root / 'x', '--concurrency', value), capture_output=True,
                                timeout=10, env=program.environment())
        r.equal(f'--concurrency {value} is exit 2', result.returncode, 2)

    spool = root / 'spool'
    incoming = spool / 'incoming'
    incoming.mkdir(parents=True)
    texts = {f'job-{i}': f'payload number {i} ' * (i % 7 + 1) for i in range(40)}
    ops = {name: 'sha256' if i % 2 == 0 else 'wordcount' for i, name in enumerate(texts)}
    for name, text in texts.items():
        write_atomically(incoming / f'{name}.json', json.dumps({'id': name, 'op': ops[name], 'input': text}))
    (incoming / '.partial.json').write_text('{"id": "partial", "op": "sha2')
    worker = start(program, spool)
    done = spool / 'done'
    finished = wait_until(lambda: done.is_dir() and len(list(done.glob('*.json'))) >= 40, 30)
    r.check('processes the jobs already queued at start', finished, len(list(done.glob('*.json'))) if done.is_dir()
            else 'no done directory')
    correct = 0
    for name, text in texts.items():
        path = done / f'{name}.json'
        try:
            result = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        expected = hashlib.sha256(text.encode()).hexdigest() if ops[name] == 'sha256' else len(text.split())
        correct += result == {'id': name, 'result': expected}
    r.equal('results are correct', correct, 40)
    r.check('incoming files are deleted after processing',
            sorted(p.name for p in incoming.iterdir()) == ['.partial.json'], sorted(p.name for p in incoming.iterdir()))
    r.check('files starting with `.` are never read', not (done / 'partial.json').exists()
            and not (spool / 'failed' / '.partial.json').exists())

    bad = {'broken': '{"id": ', 'no-op': '{"id": "a1", "input": "x"}', 'bad-id': '{"id": "a b", "op": "sha256", '
           '"input": "x"}', 'unknown': '{"id": "u1", "op": "upload", "input": "x"}',
           'bad-sleep': '{"id": "s1", "op": "sleep", "input": "forever"}'}
    for name, text in bad.items():
        write_atomically(incoming / f'{name}.json', text)
    failed = spool / 'failed'
    r.check('invalid jobs fail', wait_until(lambda: failed.is_dir() and len(list(failed.glob('*.json'))) >= 5, 15),
            sorted(p.name for p in failed.glob('*')) if failed.is_dir() else 'no failed directory')
    shaped = 0
    for name in bad:
        try:
            record = json.loads((failed / f'{name}.json').read_text())
            shaped += record.get('file') == f'{name}.json' and isinstance(record.get('error'), str) and record['error']
        except (OSError, ValueError, AttributeError):
            pass
    r.equal('failed records name the file and the error', shaped, 5)

    started = time.monotonic()
    for i in range(8):
        write_atomically(incoming / f'nap-{i}.json', json.dumps({'id': f'nap-{i}', 'op': 'sleep', 'input': 600}))
    naps = wait_until(lambda: all((done / f'nap-{i}.json').exists() for i in range(8)), 15)
    elapsed = time.monotonic() - started
    r.check('runs 4 jobs at a time by default (8 x 600 ms in about 1.2 s)', naps and elapsed < 2.2, f'{elapsed:.2f}s')
    try:
        nap = json.loads((done / 'nap-0.json').read_text())
    except (OSError, ValueError):
        nap = None
    r.equal('sleep result is null', nap, {'id': 'nap-0', 'result': None})

    write_atomically(incoming / 'last.json', json.dumps({'id': 'last', 'op': 'sleep', 'input': 1500}))
    wait_until(lambda: not (incoming / 'last.json').exists() or (done / 'last.json').exists(), 5)
    time.sleep(0.3)
    code, seconds = stop(worker)
    output = worker.stdout.read()
    r.check('SIGTERM: exits 0 within 5 s', code == 0 and seconds < 5, (code, f'{seconds:.2f}s'))
    r.check('SIGTERM: finishes the job in flight', (done / 'last.json').exists())
    r.check('logs one line per finished job', len([line for line in output.splitlines() if line.strip()]) >= 50,
            output[-500:])

    before = {p.name: p.stat().st_mtime_ns for p in done.iterdir()}
    write_atomically(incoming / 'after.json', json.dumps({'id': 'after', 'op': 'wordcount', 'input': 'a b c'}))
    worker = start(program, spool, '--concurrency', '1')
    resumed = wait_until(lambda: (done / 'after.json').exists(), 15)
    stop(worker)
    r.check('restart: processes jobs left in incoming', resumed)
    unchanged = all((done / name).stat().st_mtime_ns == mtime for name, mtime in before.items())
    r.check('restart: never processes a job twice', unchanged)
    leftovers = [p.name for p in list(done.iterdir()) + list(failed.iterdir()) if p.name.startswith('.')]
    r.check('results are written atomically (no temporary files left)', not leftovers, leftovers)
