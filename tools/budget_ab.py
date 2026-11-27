#!/usr/bin/env python3
"""Interleaved flint budget A/B: is a candidate within each endpoint's tolerance of a base, measured in one session?

Instruction counts per request include the reactor's idle polling between requests, which shifts from one session
to the next (posidon, 2026-11-26/27: +0.4%, then +0.8%, on unchanged code), so a candidate compared with stored
numbers can miss by the session alone. This alternates the two builds' prebuilt release binaries in one session with
flint budget's own method (tools/flint_budget.measure_instructions: callgrind over the wire, one reactor,
collections disabled, the cheapest of three windows per case), for `--repeat` rounds each, the order alternating, and
judges the candidate's median against the base's median with each endpoint's tolerance from its budgets.json.
Coordinator decision 2026-11-27 08:21Z: the merge train's tie-breaker before returning a lane that failed only flint
budget.

    python3 tools/budget_ab.py --base DIR --candidate DIR [--app NAME ...] [--repeat 5] [--json OUT]

DIR holds the release binaries named after the apps. Exit 0: within tolerance; 1: the candidate regresses past
tolerance on some endpoint (each printed); 2: the measurement failed.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import statistics
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path.cwd() / 'tools'))  # the merge train runs a copy of this file in the candidate's checkout
import flint_budget  # noqa: E402
import spring_instr  # noqa: E402


def judge(base_runs, candidate_runs, endpoints, floor):
    """{endpoint: row} comparing the candidate's median with the base's, each endpoint's own tolerance."""
    report = {}
    for name, entry in endpoints.items():
        if name not in base_runs[0] or name not in candidate_runs[0]:
            continue
        base = statistics.median(run[name] for run in base_runs)
        candidate = statistics.median(run[name] for run in candidate_runs)
        tolerance = entry.get('tolerance', floor)
        report[name] = {'base': base, 'candidate': candidate, 'delta': candidate / base - 1, 'tolerance': tolerance,
                        'over': candidate > base * (1 + tolerance)}
    return report


def measure(app, binary, requests, pins):
    with tempfile.TemporaryDirectory(prefix='budget-ab-') as directory:
        work = Path(directory)
        with (spring_instr.postgres(pins['database']) if app == 'petclinic-rest'
              else contextlib.nullcontext()) as database:
            got = flint_budget.measure_instructions(app, binary, requests, database, pins, work)
    return {name: row['instructions'] for name, row in got.items()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--base', type=Path, required=True, help='directory of the base release binaries')
    parser.add_argument('--candidate', type=Path, required=True, help='directory of the candidate release binaries')
    parser.add_argument('--app', action='append', choices=flint_budget.APPS)
    parser.add_argument('--repeat', type=int, default=5)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args(argv)
    spring_instr.rerun_under_hold(Path(__file__).resolve())
    apps = args.app or list(flint_budget.APPS)
    pins = spring_instr.cpus()
    out, failed = {'schema': 'flint.budget-ab/1', 'repeat': args.repeat, 'apps': {}}, False
    for app in apps:
        budgets = json.loads(flint_budget.budgets_path(app).read_text())
        requests = flint_budget.suite_requests(app)
        runs = {'base': [], 'candidate': []}
        try:
            for trial in range(args.repeat):
                for label in (('base', 'candidate') if trial % 2 == 0 else ('candidate', 'base')):
                    directory = args.base if label == 'base' else args.candidate
                    runs[label].append(measure(app, directory / app, requests, pins))
        except Exception as error:  # a server that cannot start is no verdict
            print(f'{app}: interleaved measurement failed: {error}', file=sys.stderr)
            return 2
        floor = budgets.get('tolerance', {}).get('instructions', flint_budget.floor(app))
        report = judge(runs['base'], runs['candidate'], budgets['endpoints'], floor)
        out['apps'][app] = {'report': report, 'runs': runs}
        for name, row in report.items():
            if row['over']:
                failed = True
                print(f"budget-ab: {app}: '{name}': instructions {row['base']:,.0f} -> {row['candidate']:,.0f} "
                      f"({row['delta']:+.2%}, tolerance +{row['tolerance']:.2%}) interleaved")
        worst = max(report.values(), key=lambda row: row['delta'])
        print(f"{app}: interleaved over {args.repeat} rounds each: worst delta {worst['delta']:+.2%}; "
              + ('OVER' if any(r['over'] for r in report.values()) else 'within tolerance'))
    text = json.dumps(out, indent=1)
    if args.json:
        args.json.write_text(text + '\n')
    print(text)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
