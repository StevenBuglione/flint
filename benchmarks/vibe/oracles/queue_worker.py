"""Oracle for queue-worker: a minimal Python solution that proves the acceptance test is sound. Not a benchmark
entry."""
import argparse
import hashlib
import json
import os
import re
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--spool', required=True)
parser.add_argument('--concurrency', default='4')
arguments = parser.parse_args()
if not arguments.concurrency.isdigit() or not 1 <= int(arguments.concurrency) <= 64:
    sys.exit(2)
spool = Path(arguments.spool)
incoming, done, failed = spool / 'incoming', spool / 'done', spool / 'failed'
for directory in (incoming, done, failed):
    directory.mkdir(parents=True, exist_ok=True)
stopping = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stopping.set())
signal.signal(signal.SIGINT, lambda *_: stopping.set())
taken = set()
lock = threading.Lock()


def publish(path, record):
    temporary = path.with_name('.' + path.name + '.tmp')
    temporary.write_text(json.dumps(record))
    os.replace(temporary, path)


def result_of(job):
    if not isinstance(job, dict) or not isinstance(job.get('id'), str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',
                                                                                          job['id']):
        raise ValueError('invalid id')
    op, value = job.get('op'), job.get('input')
    if op == 'sha256' and isinstance(value, str):
        return hashlib.sha256(value.encode()).hexdigest()
    if op == 'wordcount' and isinstance(value, str):
        return len(value.split())
    if op == 'sleep' and isinstance(value, (int, float)) and not isinstance(value, bool) and 0 <= value <= 10000:
        time.sleep(value / 1000)
        return None
    raise ValueError('unknown op or invalid input')


def process(path):
    started = time.monotonic()
    try:
        job = json.loads(path.read_text())
        result = result_of(job)
        publish(done / f"{job['id']}.json", {'id': job['id'], 'result': result})
        line = f"done {job['id']} {int((time.monotonic() - started) * 1000)}ms"
    except (ValueError, KeyError) as error:
        publish(failed / path.name, {'file': path.name, 'error': str(error) or 'invalid job'})
        line = f'failed {path.stem}: {error}'
    path.unlink()
    print(line, flush=True)
    with lock:
        taken.discard(path.name)


with ThreadPoolExecutor(int(arguments.concurrency)) as pool:
    slots = threading.Semaphore(int(arguments.concurrency))
    while not stopping.is_set():
        for path in sorted(incoming.glob('*.json')):
            if path.name.startswith('.') or stopping.is_set():
                continue
            with lock:
                if path.name in taken:
                    continue
                taken.add(path.name)
            slots.acquire()
            pool.submit(lambda p=path: (process(p), slots.release()))
        stopping.wait(0.05)
sys.exit(0)
