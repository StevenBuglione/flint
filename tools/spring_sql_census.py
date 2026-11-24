#!/usr/bin/env python3
"""The SQL each implementation sends per endpoint (owner decision 355068f5: every comparator must send the Spring
reference's SQL per request, or the benchmark is invalid). Diagnostic, never timing evidence.

    spring_sql_census.py [--app petclinic-rest] [--impl java --impl flint --impl go] [--flint-binary <path>]
                         --output <directory>

The black-box suite runs once per implementation, in order, against a PostgreSQL cluster that logs every statement
(log_min_duration_statement=0: the extended protocol's parse, bind and execute separately; log_connections; the
backend pid, database and a millisecond UTC timestamp on each line). Each case's request is timestamped, with a
30 ms gap on both sides, and every log line is assigned to the case whose request it falls inside: statements during
startup (schema, data, pool warm-up) are counted apart. Per case and implementation the census records parses
(named and unnamed), binds, executes, simple-protocol statements, transaction commands (BEGIN, COMMIT, ROLLBACK,
SET, SAVEPOINT), statements by kind, connections opened, and the ordered statement list. `table.md` compares the
implementations endpoint by endpoint against Java, the ground truth.

The log shows statements, not network messages: pgjdbc pipelines BEGIN with the first query in one message, and the
log records both statements with the same backend and millisecond.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402
import springsuite  # noqa: E402  (spring_bench puts the suites directory on the path)
from spring_diag import DURATION, statement_kind  # noqa: E402

LOG_OPTIONS = ("-c log_min_duration_statement=0 -c log_connections=on -c log_timezone=UTC "
               "-c log_line_prefix='%m [%p] db=%d '")
TRANSACTION_KINDS = ('begin', 'commit', 'rollback', 'set', 'savepoint', 'release')


def logging_cluster(copy_to):
    """spring_bench.postgres_cluster with statement logging on; the server log is copied out before teardown."""
    @contextlib.contextmanager
    def cluster(cpus=None):
        prefix = spring_bench.postgres_bin()
        with tempfile.TemporaryDirectory(prefix='flint-sql-census-') as directory:
            data, log = Path(directory) / 'data', Path(directory) / 'server.log'
            quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.STDOUT}
            subprocess.run([str(prefix / 'initdb'), '-D', str(data), '-U', 'petclinic', '--auth=trust',
                            '--encoding=UTF8', '--locale=C.UTF-8', '--no-sync'], check=True, **quiet)
            port = spring_bench.free_port()
            options = (f'-c listen_addresses=127.0.0.1 -p {port} -c unix_socket_directories= -c fsync=off '
                       f'-c max_connections=200 {LOG_OPTIONS}')
            subprocess.run([str(prefix / 'pg_ctl'), '-D', str(data), '-l', str(log), '-o', options, '-w', '-t', '60',
                            'start'], check=True, **quiet)
            counter = [0]

            def database():
                counter[0] += 1
                name = f'petclinic{counter[0]}'
                subprocess.run([str(prefix / 'createdb'), '-h', '127.0.0.1', '-p', str(port), '-U', 'petclinic', name],
                               check=True, **quiet)
                return {'POSTGRES_URL': f'jdbc:postgresql://127.0.0.1:{port}/{name}', 'POSTGRES_USER': 'petclinic',
                        'POSTGRES_PASS': 'petclinic'}
            try:
                yield database
            finally:
                subprocess.run([str(prefix / 'pg_ctl'), '-D', str(data), '-m', 'fast', '-w', 'stop'], check=False,
                               **quiet)
                shutil.copy2(log, copy_to)
    return cluster


def log_time(line):
    """Epoch seconds of a log line's '%m' prefix (YYYY-MM-DD HH:MM:SS.mmm UTC), or None for a continuation line."""
    try:
        stamp = datetime.datetime.strptime(line[:23], '%Y-%m-%d %H:%M:%S.%f')
    except ValueError:
        return None
    return stamp.replace(tzinfo=datetime.timezone.utc).timestamp()


def assign(lines, marks, slack=0.003):
    """{case index or 'startup' or 'between': [log line]} by each line's timestamp."""
    out = {}
    first = marks[0][3] if marks else float('inf')
    index = 0
    for line in lines:
        when = log_time(line)
        if when is None:
            continue
        while index < len(marks) and when > marks[index][4] + slack:
            index += 1
        if when < first - slack:
            key = 'startup'
        elif index < len(marks) and marks[index][3] - slack <= when <= marks[index][4] + slack:
            key = index
        else:
            key = 'between'
        out.setdefault(key, []).append(line)
    return out


def summarize(lines):
    counts = {'parse': 0, 'parse_unnamed': 0, 'bind': 0, 'execute': 0, 'simple': 0, 'connections': 0}
    kinds, statements = {}, []
    for line in lines:
        if 'connection authorized' in line:
            counts['connections'] += 1
            continue
        if ' STATEMENT:  ' in line:
            # A statement that failed is logged as ERROR, DETAIL and STATEMENT, never as a duration line: it is
            # counted as sent, with its kind marked failed.
            sql = line.split(' STATEMENT:  ', 1)[1]
            kind = 'failed ' + statement_kind(sql)
            kinds[kind] = kinds.get(kind, 0) + 1
            statements.append('FAILED ' + ' '.join(sql.split())[:300])
            counts['failed'] = counts.get('failed', 0) + 1
            continue
        match = DURATION.search(line)
        if not match:
            continue
        phase, name, sql = match.groups()
        if phase == 'parse':
            counts['parse'] += 1
            counts['parse_unnamed'] += name == '<unnamed>'
        elif phase == 'bind':
            counts['bind'] += 1
        else:
            counts['execute' if phase == 'execute' else 'simple'] += 1
            kind = statement_kind(sql)
            kind = 'savepoint' if sql.lstrip().upper().startswith('SAVEPOINT') else kind
            kind = 'release' if sql.lstrip().upper().startswith('RELEASE') else kind
            kinds[kind] = kinds.get(kind, 0) + 1
            statements.append(' '.join(sql.split())[:300])
    counts['transaction_commands'] = sum(kinds.get(k, 0) for k in TRANSACTION_KINDS)
    counts['data_statements'] = sum(v for k, v in kinds.items() if k not in TRANSACTION_KINDS)
    return {'counts': counts, 'kinds': kinds, 'statements': statements}


def census_one(app, impl, output, binary=None):
    marks = []
    original = springsuite.exchange

    def exchange(origin, case, timeout=10):
        time.sleep(0.03)
        started = time.time()
        try:
            return original(origin, case, timeout)
        finally:
            marks.append((case.name, case.method, case.path, started, time.time()))
            time.sleep(0.03)
    log = output / f'{impl}-postgres.log'
    springsuite.exchange = exchange
    real_cluster = spring_bench.postgres_cluster
    spring_bench.postgres_cluster = logging_cluster(log)
    try:
        observed, _ = spring_bench.observe(app, impl, logs=output, mask=False, binary=binary)
    finally:
        springsuite.exchange = original
        spring_bench.postgres_cluster = real_cluster
    groups = assign(log.read_text(errors='replace').splitlines(), marks)
    cases = [dict(name=name, method=method, path=path, status=(row['response'] or {}).get('status'),
                  **summarize(groups.get(index, [])))
             for index, ((name, method, path, _, _), row) in enumerate(zip(marks, observed))]
    return {'impl': impl, 'startup': summarize(groups.get('startup', [])), 'between': summarize(groups.get('between', [])),
            'cases': cases}


def divergences(results, reference='java'):
    """Per implementation, the cases whose data statements by kind or transaction commands differ from Java's."""
    by = {r['impl']: r for r in results}
    out = {}
    for impl in by:
        if impl == reference:
            continue
        rows = []
        for index, want in enumerate(by[reference]['cases']):
            got = by[impl]['cases'][index]
            parts = {}
            for label, keep in (('data', lambda k: k not in TRANSACTION_KINDS), ('transactions', lambda k: k in TRANSACTION_KINDS)):
                mine = {k: v for k, v in got['kinds'].items() if keep(k)}
                theirs = {k: v for k, v in want['kinds'].items() if keep(k)}
                if mine != theirs:
                    parts[label] = {'implementation': mine, 'java': theirs}
            if parts:
                rows.append(dict(case=want['name'], method=want['method'], path=want['path'], **parts))
        out[impl] = rows
    return out


def record(app, output, results):
    """benchmarks/spring/census/<app>.json: what `spring_bench.py register` and `check-registry` require of a
    database app's comparator (ADR-032 section 4): the census of the comparator's current source, with its
    per-request divergences from the reference."""
    found = divergences(results)
    summary = {'schema': 'flint.spring-sql-census-record/1', 'app': app,
               'comparator_sha256': spring_bench.comparator_digest(app),
               'golden_sha256': spring_bench.sha256(spring_bench.golden_path(app)),
               'divergences': {impl: len(rows) for impl, rows in found.items()},
               'go_divergent_cases': [row['case'] for row in found.get('go', [])],
               'evidence': str(output.resolve().relative_to(ROOT)) if output.resolve().is_relative_to(ROOT) else str(output),
               'recorded': time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}
    path = spring_bench.CENSUS / f'{app}.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + '\n')
    return path


def table(results, reference='java'):
    """Markdown: per case, each implementation's statements against the reference; a row is marked when the data
    statements by kind or the transaction commands differ from Java's."""
    impls = [r['impl'] for r in results]
    by = {r['impl']: r for r in results}
    head = '| case | ' + ' | '.join(f'{i}: data / txn / parse (unnamed) / exec' for i in impls) + ' | differs from Java |'
    rows = [head, '|' + '---|' * (len(impls) + 2)]
    differing = 0
    for index, case in enumerate(by[reference]['cases']):
        cells, diff = [], []
        want = by[reference]['cases'][index]
        for impl in impls:
            got = by[impl]['cases'][index]
            c = got['counts']
            cells.append(f"{c['data_statements']} / {c['transaction_commands']} / {c['parse']} ({c['parse_unnamed']}) / "
                         f"{c['execute'] + c['simple']}")
            if impl != reference:
                data = {k: v for k, v in got['kinds'].items() if k not in TRANSACTION_KINDS}
                data_want = {k: v for k, v in want['kinds'].items() if k not in TRANSACTION_KINDS}
                txn = {k: v for k, v in got['kinds'].items() if k in TRANSACTION_KINDS}
                txn_want = {k: v for k, v in want['kinds'].items() if k in TRANSACTION_KINDS}
                if data != data_want:
                    diff.append(f'{impl}: data {data} vs {data_want}')
                if txn != txn_want:
                    diff.append(f'{impl}: txn {txn} vs {txn_want}')
        differing += bool(diff)
        rows.append(f"| {case['method']} {case['path']} ({case['name']}) | " + ' | '.join(cells) + ' | '
                    + ('; '.join(diff) or '') + ' |')
    return '\n'.join(rows) + '\n', differing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', default='petclinic-rest')
    parser.add_argument('--impl', action='append', choices=['java', 'flint', 'go'])
    parser.add_argument('--flint-binary', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true',
                        help='write benchmarks/spring/census/<app>.json for registration (needs java and go)')
    args = parser.parse_args(argv)
    if spring_bench.app_row(args.app).get('database') != 'postgres':
        raise SystemExit(f'{args.app} does not use PostgreSQL; its statements are not in a server log')
    lock = ROOT / '.flint' / 'measure' / 'MEASURING'
    if lock.exists():
        raise SystemExit(f'a timed measurement is in progress ({lock}); the Java reference would void it')
    args.output.mkdir(parents=True, exist_ok=True)
    impls = args.impl or ['java', 'flint', 'go']
    results = []
    for impl in impls:
        binary = args.flint_binary.resolve() if (impl == 'flint' and args.flint_binary) else None
        results.append(census_one(args.app, impl, args.output, binary))
        print(json.dumps({'impl': impl, 'cases': len(results[-1]['cases']),
                          'startup_statements': results[-1]['startup']['counts']}), flush=True)
    (args.output / 'census.json').write_text(json.dumps({
        'schema': 'flint.spring-sql-census/1', 'app': args.app, 'comparator_sha256': spring_bench.comparator_digest(args.app),
        'divergences': divergences(results), 'results': results}, indent=1) + '\n')
    text, differing = table(results)
    (args.output / 'table.md').write_text(text)
    print(f'{differing} of {len(results[0]["cases"])} cases differ from Java; see {args.output / "table.md"}')
    if args.record:
        if not {'java', 'go'} <= set(impls):
            raise SystemExit('--record needs the java and go censuses')
        print('recorded', record(args.app, args.output, results))
    return 0


if __name__ == '__main__':
    sys.exit(main())
