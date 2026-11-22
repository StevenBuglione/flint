#!/usr/bin/env python3
"""Render the milestone report's measured tables from one collected evidence file.

The tables are derived only from `current.json` (and the policy caps), so the report cannot drift from the
evidence it cites. Ratios and their 99% bounds use the same paired bootstrap as `tools/gates.py`.
"""
import argparse
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from perf_stats import median_ratio_interval  # noqa: E402

PACKAGES = json.loads((ROOT / 'policy/packages.json').read_text())['packages']
BUDGETS = json.loads((ROOT / 'policy/budgets.json').read_text())


def median(values):
    return statistics.median(values)


def ratio(new, old):
    med, _, hi = median_ratio_interval(new, old)
    return f'{med:.3f} ({hi:.3f})'


def seconds(values):
    return f'{median(values):.3f}'


def number(value):
    return f'{value:,}'


def apps(evidence):
    lines = ['| App | Flint DMD cold s | Go cold s | Ratio (99% upper) | Flint first build s | DMD edit s | Flint Oz bytes | Go bytes | Size ratio |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for name in ['bench-cli', 'bench-rest']:
        flint = evidence['apps'][name]
        go = evidence['go']['apps'][name]
        first = flint.get('dmd_first_build_seconds')
        lines.append(f"| {name} | {seconds(flint['dmd_cold_seconds'])} | {seconds(go['cold_seconds'])} | "
                     f"{ratio(flint['dmd_cold_seconds'], go['cold_seconds'])} | "
                     f"{'' if first is None else f'{first:.3f}'} | {seconds(flint['dmd_incremental_seconds'])} | "
                     f"{number(flint['Oz']['binary_bytes'])} | {number(go['binary_bytes'])} | "
                     f"{flint['Oz']['binary_bytes'] / go['binary_bytes']:.3f} |")
    return '\n'.join(lines)


def rest(evidence):
    flint = evidence['rest']
    go = evidence['go']['rest']
    rows = [('Requests per second', 'requests_per_second', '{:,.0f}'), ('p50 latency ms', 'p50_ms', '{:.3f}'),
            ('p99 latency ms', 'p99_ms', '{:.3f}'), ('p99.9 latency ms', 'p999_ms', '{:.3f}'),
            ('Peak RSS bytes', 'peak_rss_bytes', '{:,.0f}'), ('CPU ns per request', 'cpu_ns_per_request', '{:,.0f}')]
    lines = ['| Median of 9 | Flint | Go | Flint/Go (99% upper) |', '| --- | ---: | ---: | ---: |']
    for label, key, fmt in rows:
        if key == 'requests_per_second':
            interval = ratio([1 / x for x in go[key]], [1 / x for x in flint[key]])
        else:
            interval = ratio(flint[key], go[key])
        lines.append(f'| {label} | {fmt.format(median(flint[key]))} | {fmt.format(median(go[key]))} | {interval} |')
    return '\n'.join(lines)


def packages(evidence):
    lines = ['| Package | DMD cold s | DMD edit s | LDC cold s | LDC edit s | Compiler RSS MB | Templates (closure) | Size delta bytes |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    worst = {}
    for name in sorted(evidence['packages']):
        row = evidence['packages'][name]
        budget = PACKAGES[name]['budget']
        cells = []
        for key in ['dmd_cold_seconds', 'dmd_incremental_seconds', 'ldc_cold_seconds', 'ldc_incremental_seconds']:
            share = median(row[key]) / budget[key]
            worst[key] = max(worst.get(key, (0, '')), (share, name))
            cells.append(f'{median(row[key]):.2f}')
        for key in ['compiler_peak_rss_bytes', 'template_instances', 'incremental_linked_bytes']:
            worst[key] = max(worst.get(key, (0, '')), (row[key] / budget[key], name))
        cells.append(f"{row['compiler_peak_rss_bytes'] / 1e6:.0f}")
        cells.append(f"{number(row['template_instances'])} ({number(row['template_instances_closure'])})")
        cells.append(number(row['incremental_linked_bytes']))
        lines.append(f'| {name} | ' + ' | '.join(cells) + ' |')
    summary = ['', 'Highest share of any package cap, by metric:', '']
    for key, (share, name) in worst.items():
        summary.append(f'- `{key}`: {share:.0%} ({name})')
    return '\n'.join(lines + summary)


def micro(evidence):
    lines = ['| Microbenchmark | Median ns/op (21 trials) |', '| --- | ---: |']
    for name, values in evidence['micro'].items():
        lines.append(f'| {name} | {median(values):,.1f} |')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    gc = evidence['gc']
    print(f"Evidence commit `{evidence['commit']}`, runner `{evidence['environment']['runner_label']}`, "
          f"ephemeral: {evidence['environment'].get('runner_ephemeral')}.\n")
    print('## Builds against Go\n\n' + apps(evidence) + '\n')
    print('## REST load against Go\n\n' + rest(evidence) + '\n')
    print(f"Hot-path GC: {gc['requests_completed']:,} requests on {gc['worker_count']} workers, "
          f"allocated bytes per worker {gc['allocated_bytes_per_worker']}, collection delta {gc['collection_delta']}.\n")
    print('## Microbenchmarks\n\n' + micro(evidence) + '\n')
    print('## Packages\n\n' + packages(evidence) + '\n')
    print('## Platforms\n\n' + '\n'.join(f'- {k}: {"pass" if v else "not run"}'
                                         for k, v in evidence['platforms'].items()))


if __name__ == '__main__':
    main()
