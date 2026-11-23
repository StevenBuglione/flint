#!/usr/bin/env python3
"""Export each HTTP side-by-side suite's requests, exactly as springsuite.exchange sends them, for tests that are not
Python: the per-request allocation gate (policy/request-allocations.json) replays them against the app in-process.

    python3 tools/spring_requests.py            write benchmarks/spring/suites/requests/<app>.json
    python3 tools/spring_requests.py --check    fail when an export differs from its suite
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUITES = ROOT / 'benchmarks' / 'spring' / 'suites'
OUT = SUITES / 'requests'
sys.path.insert(0, str(SUITES))


def requests_of(app, row):
    """The suite's cases as springsuite.exchange sends them: its default headers, the case's, and the JSON body."""
    import importlib

    suite = importlib.import_module(row['suite'])
    exported = []
    for case in suite.CASES:
        headers = {'Accept': '*/*', 'User-Agent': 'flint-spring-suite/1'}
        headers.update(case.headers)
        body = case.request_body()
        if body is not None and 'Content-Type' not in headers:
            headers['Content-Type'] = 'application/json'
        exported.append({'name': case.name, 'method': case.method, 'path': case.path,
                         'headers': [[key, value] for key, value in headers.items()],
                         'body': None if body is None else body.decode('utf-8')})
    return {'schema': 'flint.spring-requests/1', 'app': app,
            'generated_by': 'tools/spring_requests.py from benchmarks/spring/suites/' + row['suite'] + '.py',
            'requests': exported}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    apps = json.loads((ROOT / 'benchmarks' / 'spring' / 'apps.json').read_text())['apps']
    stale = []
    for app, row in apps.items():
        if row.get('kind') != 'http':
            continue
        text = json.dumps(requests_of(app, row), indent=1, ensure_ascii=False) + '\n'
        path = OUT / f'{app}.json'
        if args.check:
            if not path.is_file() or path.read_text() != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            print(path.relative_to(ROOT))
    if stale:
        raise SystemExit('stale request exports (run python3 tools/spring_requests.py): ' + ', '.join(stale))


if __name__ == '__main__':
    main()
