#!/usr/bin/env python3
"""`flint budget`: what each endpoint of a Phase 1 app costs per request, against budgets committed in the repo.

    python3 tools/flint_budget.py [--app NAME]... [--json FILE]          measure and compare (exit 0, 1 or 2)
    python3 tools/flint_budget.py --update [--app NAME]... [--allow-raise DECISION-ID]
    python3 tools/flint_budget.py --repeat 5 --app NAME                  the noise floor: spread over repeated runs

Design: coordination/notes/flint-budget.md (owner decision 087f28a3: Phase 2 runs behind CI guardrails).

An endpoint is one case of the app's side-by-side suite (benchmarks/spring/suites/requests/<app>.json), the cases
the acceptance golden files and the request-allocation gate already name. Per endpoint:

- instructions per request: the release binary (O3, ThinLTO O3) serves the suite over the wire under callgrind, with one
  reactor and collections disabled (`--DRT-gcopt=disable:1`), so no collection lands in a measured window; the GC's
  cost shows in bytes instead. The whole suite runs twice to warm up, then each case in suite order is sent N times
  between `callgrind_control -z` and `-d`, once in each of three passes over the suite; the case keeps its cheapest
  window. A periodic event (the date-header refresh, pool housekeeping) otherwise lands in a window now and then, and
  one that runs for seconds would cover back-to-back windows of neighbouring cases. One server start serves every
  case.
- allocations and bytes per request: the app's in-process request-allocation test in record mode (its fenced windows,
  the minimum of three), as `flint test` runs it; their budgets stay in policy/request-allocations.json, under its
  only-down ratchet (tools/request_allocation_ratchet.py).

Instruction budgets live in benchmarks/spring/flint/<app>/budgets.json with the runner class they were measured on
(CPU model, glibc, valgrind), an app-wide tolerance of 0.5%, and, for an endpoint whose own spread over repeated
runs is wider, that endpoint's tolerance of 3 x its spread (`--update --repeat 5` measures it). A run on another
runner class fails closed. Exit codes: 0 within budget; 1 a regression, a missing or a stale budget, each named;
2 the measurement itself failed. `--update` rewrites the instruction budgets: lowering is always allowed; a raise
beyond the tolerance needs `--allow-raise <decision id>`, recorded next to the value, and CI refuses a commit that
raises a budget without a `Budget-Raise-Approved: <decision id>` trailer (tools/budget_raise_check.py).
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402
import spring_instr  # noqa: E402

SCHEMA = 'flint.budget/1'
APPS = ('gs-rest-service', 'petclinic-rest')
ALLOCATION_BUDGETS = ROOT / 'policy' / 'request-allocations.json'
WARMUP_ROUNDS = 2
MEASURED = 8
# Each case is measured in this many windows, one per pass over the suite, and keeps the cheapest: a once-a-second
# event (the Date header's refresh, a reactor housekeeping timer) that lands in one window adds ~1,300 instructions
# per request there.
WINDOWS = 3
MIN_TOLERANCE = 0.005
# An app's floor is wider where rebuilding it shifts some endpoints by more than 0.5% with no change of theirs (code
# layout from unrelated commits, run-to-run state): petclinic-rest's builds across commits spread p90 1.09%, a
# rebuild of one commit p95 0.46% (posidon, 2026-11-26, coordination/notes/flint-budget.md).
FLOORS = {'petclinic-rest': 0.01}


def floor(app):
    return max(MIN_TOLERANCE, FLOORS.get(app, 0.0))


class Failure(Exception):
    """The measurement could not be made (exit 2)."""


def budgets_path(app):
    return ROOT / 'benchmarks' / 'spring' / 'flint' / app / 'budgets.json'


def suite_requests(app):
    document = json.loads((ROOT / 'benchmarks' / 'spring' / 'suites' / 'requests' / f'{app}.json').read_text())
    return [{'name': row['name'], 'method': row['method'], 'path': row['path'],
             'headers': {name: value for name, value in row['headers']}, 'body': row['body']}
            for row in document['requests']]


def runner_class():
    """The machine facts instruction counts depend on: the CPU (glibc picks string routines by it), glibc, valgrind."""
    model = next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                  if line.startswith('model name')), 'unknown CPU')
    glibc = subprocess.run(['ldd', '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    found = re.match(r'^ldd \((.*)\) ', glibc)  # 'ldd (Ubuntu GLIBC 2.39-0ubuntu8.12) 2.39'
    glibc = found.group(1) if found else glibc.strip()
    valgrind = subprocess.run(['valgrind', '--version'], capture_output=True, text=True).stdout.strip()
    return f'{model} / {glibc} / {valgrind}'


# ---------------------------------------------------------------------------------------------------------------
# Measuring


def measure_instructions(app, binary, requests, database, pins, work):
    """{case: instructions per request} over the wire, plus GC allocation calls per request as a cross-check."""
    port = spring_bench.free_port()
    argv, env, cwd = spring_bench.launch(app, 'flint', port, database=database, binary=binary,
                                         extra_args=['--DRT-gcopt=disable:1'])
    env['SERVER_FLINT_THREADS'] = '1'
    out = work / 'callgrind.out'
    command = ['taskset', '--cpu-list', str(pins['server']), 'valgrind', '--tool=callgrind', '--dump-instr=no',
               '--demangle=no', '--compress-strings=no', '--compress-pos=no', f'--callgrind-out-file={out}', *argv]
    results = {}
    with spring_instr.started(command, env, cwd, work / 'callgrind-server.log') as server:
        spring_instr.wait_port(port, server, 600)
        for _ in range(WARMUP_ROUNDS):
            for request in requests:
                spring_instr.send(port, request, 1)
        # Each case's windows come from separate passes over the whole suite, a minute or more apart, not back to
        # back: a periodic task that runs for seconds (pool housekeeping, timers) can otherwise cover every window of
        # the cases in flight, which read a percent or more high together in one run and not the next.
        cheapest = {}
        for _ in range(WINDOWS):
            for request in requests:
                totals = measure_window(server, port, request, work, app)
                best = cheapest.get(request['name'])
                if best is None or totals['total'] < best['total']:
                    cheapest[request['name']] = totals
        for request in requests:
            totals = cheapest[request['name']]
            results[request['name']] = {'instructions': totals['total'] / MEASURED,
                                        'gc_calls': totals['gc_calls'] / MEASURED}
    return results


def measure_window(server, port, request, work, app):
    """The callgrind totals of MEASURED copies of `request`, between a zero and a dump."""
    before = set(work.glob('callgrind.out.*'))
    spring_instr.control(server.pid, '-z')
    spring_instr.send(port, request, MEASURED)
    spring_instr.control(server.pid, '-d')
    fresh = sorted(set(work.glob('callgrind.out.*')) - before, key=lambda path: path.stat().st_mtime)
    if not fresh:
        raise Failure(f'{app}: callgrind wrote no dump for {request["name"]!r}')
    totals = spring_instr.parse_callgrind(fresh[-1])
    for path in fresh:
        path.unlink()
    return totals


def measure_allocations(app, compiler='ldc2'):
    """{case: {allocations, bytes}} from the app's request-allocation test in record mode."""
    flint = ROOT / '.flint' / 'bin' / 'flint'
    with tempfile.TemporaryDirectory(prefix='flint-budget-alloc-') as directory:
        out = Path(directory) / 'measured.json'
        env = dict(os.environ, FLINT_REQUEST_ALLOCATIONS='record', FLINT_REQUEST_ALLOCATIONS_OUT=str(out))
        with (spring_bench.postgres_cluster() if app == 'petclinic-rest' else contextlib.nullcontext()) as database:
            if database is not None:
                env.update(database())
            done = subprocess.run([str(flint), 'test', '-C', str(ROOT / 'benchmarks' / 'spring' / 'flint' / app),
                                   '--compiler', compiler], env=env, capture_output=True, text=True)
        if done.returncode != 0 or not out.is_file():
            raise Failure(f'{app}: the request-allocation test failed in record mode:\n{done.stdout[-2000:]}'
                          f'{done.stderr[-2000:]}')
        return json.loads(out.read_text())


def measure(app, binary, compiler):
    requests = suite_requests(app)
    pins = spring_instr.cpus()
    with tempfile.TemporaryDirectory(prefix='flint-budget-') as directory:
        work = Path(directory)
        with (spring_instr.postgres(pins['database']) if app == 'petclinic-rest'
              else contextlib.nullcontext()) as database:
            instructions = measure_instructions(app, binary, requests, database, pins, work)
    allocations = measure_allocations(app, compiler)
    return {name: dict(instructions[name], **allocations.get(name, {})) for name in instructions}


# ---------------------------------------------------------------------------------------------------------------
# Comparing


def compare(app, measured, budgets, allocation_budgets, runner):
    """Problems (regressions, missing and stale budgets) and notices (improvements worth an --update)."""
    problems, notices = [], []
    if budgets.get('runner') != runner:
        problems.append(f'{app}: budgets recorded on {budgets.get("runner")!r}; this runner is {runner!r}')
        return problems, notices
    endpoints = budgets['endpoints']
    for name, got in measured.items():
        if name not in endpoints:
            problems.append(f'{app}: {name!r} has no instruction budget in {budgets_path(app).relative_to(ROOT)}')
            continue
        budget = endpoints[name]['instructions']
        tolerance = endpoints[name].get('tolerance', budgets['tolerance']['instructions'])
        change = (got['instructions'] - budget) / budget
        if change > tolerance:
            problems.append(f'{app}: {name!r}: instructions {budget:,.0f} -> {got["instructions"]:,.0f} '
                            f'({change:+.2%}, tolerance +{tolerance:.2%})')
        elif change < -tolerance:
            notices.append(f'{app}: {name!r}: instructions {budget:,.0f} -> {got["instructions"]:,.0f} ({change:+.2%}); '
                           'run flint budget --update to lock it in')
        allocation = allocation_budgets.get(name)
        if allocation is not None and 'allocations' in got:
            for key in ('allocations', 'bytes'):
                if got[key] > allocation[key]:
                    problems.append(f'{app}: {name!r}: {key} {got[key]:,} over the budget of {allocation[key]:,} '
                                    f'({ALLOCATION_BUDGETS.relative_to(ROOT)})')
    for name in endpoints:
        if name not in measured:
            problems.append(f'{app}: {name!r} has a budget but is no longer a suite case')
    return problems, notices


def update(app, measured, budgets, runner, allow_raise, noise=None):
    """New budgets from `measured`; a raise beyond the tolerance needs a decision id (`allow_raise`). `noise` maps each
    endpoint to its spread over repeated runs: its tolerance is max(0.5%, 3 x that spread), so a stable endpoint stays
    tight while a noisy one is visible in the file."""
    tolerance = budgets.get('tolerance', {}).get('instructions', floor(app))
    old = budgets.get('endpoints', {}) if budgets.get('runner') == runner else {}
    endpoints, raises = {}, []
    for name, got in measured.items():
        value = round(got['instructions'])
        entry = {'instructions': value}
        own = (noise or {}).get(name)
        if own is not None and 3 * own > floor(app):
            entry['tolerance'] = round(3 * own, 4)
        elif name in old and 'tolerance' in old[name] and own is None:
            entry['tolerance'] = old[name]['tolerance']
        previous = old.get(name)
        limit = previous.get('tolerance', tolerance) if previous is not None else tolerance
        if previous is not None and value > previous['instructions'] * (1 + limit):
            if not allow_raise:
                raises.append(f'{app}: {name!r}: {previous["instructions"]:,} -> {value:,}')
                entry = previous
            else:
                entry['raised'] = allow_raise
        if previous is not None and 'note' in previous and entry is not previous:
            entry['note'] = previous['note']  # a recorded reason (a seeded trade-off) stays until a person removes it
        endpoints[name] = entry
    document = {'schema': SCHEMA, 'app': app, 'runner': runner, 'profile': 'release',
                'measure': {'warmup_rounds': WARMUP_ROUNDS, 'requests': MEASURED, 'windows': WINDOWS},
                'tolerance': {'instructions': floor(app) if noise is not None else tolerance}, 'endpoints': endpoints}
    return document, raises


# ---------------------------------------------------------------------------------------------------------------


def built_binary(app, directory):
    if directory:
        return Path(directory) / app
    spring_bench.build_flint(app)
    return spring_bench.flint_binary(app)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--app', action='append', choices=APPS, help='an app (default: every Phase 1 HTTP app)')
    parser.add_argument('--update', action='store_true', help='rewrite the instruction budgets from this run')
    parser.add_argument('--allow-raise', metavar='DECISION', help='a decisions.md entry approving a raise')
    parser.add_argument('--repeat', type=int, default=1, help='measure N times; report the spread (noise floor)')
    parser.add_argument('--binaries', help='a directory of prebuilt release binaries named after the apps')
    parser.add_argument('--compiler', default='ldc2', help="the request-allocation test's compiler")
    parser.add_argument('--json', type=Path, help='write the report here too')
    args = parser.parse_args()
    spring_instr.rerun_under_hold(Path(__file__).resolve())  # re-runs this script, not spring_instr's
    apps = args.app or list(APPS)
    runner = runner_class()
    allocation_budgets = json.loads(ALLOCATION_BUDGETS.read_text())['apps']
    report = {'schema': SCHEMA + '-report', 'runner': runner, 'apps': {}}
    problems, notices, failed = [], [], False
    for app in apps:
        try:
            binary = built_binary(app, args.binaries)
            runs = [measure(app, binary, args.compiler) for _ in range(max(1, args.repeat))]
        except (Failure, SystemExit, subprocess.SubprocessError, OSError) as error:
            print(f'{app}: measurement failed: {error}', file=sys.stderr)
            failed = True
            continue
        measured = {name: {key: statistics.median(run[name][key] for run in runs) for key in runs[0][name]}
                    for name in runs[0]}
        noise = {name: (max(run[name]['instructions'] for run in runs) - min(run[name]['instructions'] for run in runs))
                 / measured[name]['instructions'] for name in measured} if len(runs) > 1 else None
        path = budgets_path(app)
        budgets = json.loads(path.read_text()) if path.is_file() else {}
        report['apps'][app] = {'measured': measured, 'noise': noise,
                               'runs': {name: [run[name]['instructions'] for run in runs] for name in runs[0]}}
        if args.update:
            document, raises = update(app, measured, budgets, runner, args.allow_raise, noise)
            path.write_text(json.dumps(document, indent=1, sort_keys=False) + '\n')
            problems += [f'{line}: a raise needs --allow-raise <decision id>' for line in raises]
            noisy = sorted(((spread, name) for name, spread in (noise or {}).items() if 3 * spread > floor(app)),
                           reverse=True)
            print(f'{app}: wrote {path.relative_to(ROOT)} ({len(document["endpoints"])} endpoints; '
                  f'{len(noisy)} with their own tolerance' + (f', noisiest {noisy[0][1]!r} {noisy[0][0]:.2%}' if noisy else '') + ')')
            continue
        if not budgets:
            problems.append(f'{app}: no budgets yet ({path.relative_to(ROOT)}); run flint budget --update')
            continue
        found, notes = compare(app, measured, budgets, allocation_budgets.get(app, {}).get('requests', {}), runner)
        problems += found
        notices += notes
        if noise is not None:
            worst = max(noise.items(), key=lambda item: item[1])
            print(f'{app}: noise over {len(runs)} runs: worst {worst[0]!r} {worst[1]:.3%}')
    for line in notices:
        print('notice: ' + line)
    for line in problems:
        print('budget: ' + line, file=sys.stderr)
    report.update({'problems': problems, 'notices': notices, 'failed': failed})
    if args.json:
        args.json.write_text(json.dumps(report, indent=1) + '\n')
    sys.exit(2 if failed else 1 if problems else 0)


if __name__ == '__main__':
    main()
