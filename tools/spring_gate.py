"""The Spring side-by-side gate: `gates.py --gate spring --evidence <directory>` (ADR-030 section 8, Phase 1 exit).

The directory holds the evidence the harness writes; anything missing fails, and nothing a record states about
itself is trusted where it can be recomputed:

- `acceptance-java.json`, `acceptance-go.json`, `acceptance-flint.json`: `spring_bench.py accept --impl <impl>
  --json`, one record per application, every case passing in the implementation's wire mode (exact for Java and
  Flint, semantic for the Go comparators), against the golden files as they are now;
- `builds.json`: `measure_builds.py --spring`, production, nine trials per series; the two headlines, the
  incremental build and the Oz size are recomputed from the samples against the go_relative ceilings of
  policy/budgets.json;
- `http.json`: `load_bench.py --manifest policy/spring-http-benchmark.json`, production; p99, peak RSS and CPU per
  request at most 0.99 of Go's and throughput at least 1.01 times Go's, each a median ratio whose bootstrap 99%
  upper bound must also hold;
- `http-error-paths.json`: `load_bench.py --manifest policy/spring-error-paths-benchmark.json`, production; the
  404 and validation-error paths' p99 at most 0.99 of Go's (ADR-030 section 4);
- `gc-matrix-<app>.json`: `spring_bench.py gc-matrix`, production, every setting of benchmarks/spring/gc-matrix.json
  measured with its suite passing, for each application the matrix lists.

The Go comparators must match their registration (benchmarks/spring/comparators.json), and each evidence file must
name the same registration.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402
from perf_stats import median_ratio_interval  # noqa: E402


def load(directory, name, failures):
    path = Path(directory) / name
    if not path.is_file():
        failures.append(f'{name}: missing; missing evidence never passes')
        return None
    return json.loads(path.read_text(encoding='utf-8'))


def ratio(new, old, ceiling, label, failures, minimum=9):
    if len(new) < minimum or len(old) < minimum:
        failures.append(f'{label}: {len(new)} and {len(old)} samples; {minimum} required')
        return None
    median, lower, upper = median_ratio_interval(new, old)
    if not (median <= ceiling and upper <= ceiling):
        failures.append(f'{label}: median ratio {median:.4f}, 99% upper {upper:.4f} exceeds {ceiling}')
    return {'median': median, 'lower_99': lower, 'upper_99': upper, 'ceiling': ceiling}


def check_comparators(record, label, registered, failures):
    named = {name: row['sha256'] for name, row in record.get('comparators', {}).items()}
    for name, sha in named.items():
        if registered.get(name, {}).get('sha256') != sha:
            failures.append(f'{label}: measured a {name} comparator that differs from its registration')


def spring_gate(directory):
    failures, report = [], {}
    apps = list(spring_bench.registry()['apps'])
    failures += spring_bench.check_registry(apps)
    registered = json.loads(spring_bench.REGISTRY.read_text())['comparators'] if spring_bench.REGISTRY.is_file() else {}
    budgets = json.loads((ROOT / 'policy' / 'budgets.json').read_text())['go_relative']

    for impl in spring_bench.IMPLEMENTATIONS:
        records = load(directory, f'acceptance-{impl}.json', failures)
        if records is None:
            continue
        records = records if isinstance(records, list) else [records]
        by_app = {row['app']: row for row in records if row.get('implementation') == impl}
        for app in apps:
            row = by_app.get(app)
            label = f'acceptance {app} [{impl}]'
            if row is None:
                failures.append(f'{label}: no record')
                continue
            golden = spring_bench.golden_path(app)
            if row['golden_sha256'] != spring_bench.sha256(golden):
                failures.append(f'{label}: scored against an older golden file')
            if row['wire'] != spring_bench.WIRE_DEFAULT[impl]:
                failures.append(f"{label}: wire mode {row['wire']}, required {spring_bench.WIRE_DEFAULT[impl]}")
            failing = [case['name'] for case in row['cases'] if case['problems']]
            if failing or not row['cases']:
                failures.append(f"{label}: {len(failing)} of {len(row['cases'])} cases fail")
            report[label] = f"{len(row['cases']) - len(failing)}/{len(row['cases'])}"

    builds = load(directory, 'builds.json', failures)
    if builds is not None:
        if builds.get('mode') != 'production' or builds.get('status') != 'passed' or builds.get('trials_per_series') != 9:
            failures.append(f"builds.json: mode {builds.get('mode')}, status {builds.get('status')}, "
                            f"{builds.get('trials_per_series')} trials; production, passed and 9 required")
        check_comparators(builds, 'builds.json', registered, failures)
        ceiling = budgets['rest_build_ratio_max']
        for app in apps:
            row = builds.get('apps', {}).get(app)
            if not row or 'flint' not in row:
                failures.append(f'builds.json: {app} has no Flint measurement')
                continue
            flint, go = row['flint'], row['go']
            report[f'build {app}'] = {
                'primary': ratio(flint['flint_cached_cold_seconds'], go['go_std_cold_seconds'], ceiling,
                                 f'build {app} primary (platform cache vs std-primed GOCACHE)', failures),
                'secondary': ratio(flint['flint_scratch_seconds'], go['go_scratch_seconds'], ceiling,
                                   f'build {app} secondary (scratch vs go build -a)', failures),
                'incremental': ratio(flint['flint_cached_incremental_seconds'], go['go_std_incremental_seconds'], ceiling,
                                     f'build {app} incremental (dev profile as built)', failures)}
            # Beside the primary, with equal prominence, for a comparator with third-party packages (coordinator,
            # 2026-11-23): Go's std-primed cold build compiles them from source while Flint links prebuilt libraries.
            # Context only; the gating definitions are the owner's.
            if go.get('third_party_packages') and 'go_deps_cold_seconds' in go:
                report[f'build {app}']['primary, deps-primed GOCACHE (context)'] = ratio(
                    flint['flint_cached_cold_seconds'], go['go_deps_cold_seconds'], ceiling,
                    f'build {app} primary against a deps-primed GOCACHE (context)', [])
                report[f'build {app}']['third-party note'] = (
                    f"Go's std-primed cold build compiles {len(go['third_party_packages'])} third-party package(s) from "
                    "source while Flint links its native libraries prebuilt; the deps-primed ratio is the like-for-like "
                    "comparison. The secondary has no deps-primed equivalent (go build -a recompiles everything).")
            # Owner decision 2: edit builds also report the fully static build, as the secondary headline.
            if 'flint_static_incremental_seconds' in flint:
                report[f'build {app}']['incremental static'] = ratio(
                    flint['flint_static_incremental_seconds'], go['go_std_incremental_seconds'], ceiling,
                    f'build {app} incremental (fully static)', failures)
            else:
                failures.append(f'builds.json: {app} has no fully static edit build (measure.cached_static)')
            size = flint['Oz']['binary_bytes'] / go['binary_bytes']
            report[f'build {app}']['Oz size'] = size
            if size > budgets['binary_ratio_max']:
                failures.append(f"build {app}: Oz binary {size:.3f} of Go's exceeds {budgets['binary_ratio_max']}")

    http = load(directory, 'http.json', failures)
    if http is not None:
        if http.get('schema') != 2 or http.get('mode') != 'production' or http.get('status') != 'passed':
            failures.append(f"http.json: schema {http.get('schema')}, mode {http.get('mode')}, status {http.get('status')}; "
                            'the production Spring workload with status passed is required')
        check_comparators(http, 'http.json', registered, failures)
        for record in http.get('acceptance', []):
            if not record['success'] and record['implementation'] != 'java':
                failures.append(f"http.json: {record['app']} [{record['implementation']}] was loaded without passing its suite")
        for app in [a for a in apps if a in json.loads((ROOT / 'policy' / 'spring-http-benchmark.json').read_text())['apps']]:
            measured = http.get('apps', {}).get(app, {}).get('measured', {})
            if 'flint' not in measured or 'go' not in measured:
                failures.append(f'http.json: {app} lacks Flint or Go series')
                continue
            flint, go = measured['flint'], measured['go']
            report[f'http {app}'] = {
                metric: ratio(flint[metric], go[metric], budgets[key], f'http {app} {metric}', failures)
                for metric, key in (('p99_ms', 'p99_ratio_max'), ('peak_rss_bytes', 'peak_rss_ratio_max'),
                                    ('cpu_ns_per_request', 'p99_ratio_max'))}
            report[f'http {app}']['throughput'] = ratio(
                [1 / x for x in flint['requests_per_second']], [1 / x for x in go['requests_per_second']],
                1 / budgets['throughput_ratio_min'], f'http {app} throughput', failures)

    # ADR-030 section 4: the 404 and validation-error paths get their own p99 tests.
    errors = load(directory, 'http-error-paths.json', failures)
    if errors is not None:
        if errors.get('schema') != 2 or errors.get('mode') != 'production' or errors.get('status') != 'passed':
            failures.append(f"http-error-paths.json: schema {errors.get('schema')}, mode {errors.get('mode')}, "
                            f"status {errors.get('status')}; the production error-path workload is required")
        check_comparators(errors, 'http-error-paths.json', registered, failures)
        listed = json.loads((ROOT / 'policy' / 'spring-error-paths-benchmark.json').read_text())['apps']
        for key in listed:
            measured = errors.get('apps', {}).get(key, {}).get('measured', {})
            if 'flint' not in measured or 'go' not in measured:
                failures.append(f'http-error-paths.json: {key} lacks Flint or Go series')
                continue
            report[f'http {key}'] = {'p99_ms': ratio(measured['flint']['p99_ms'], measured['go']['p99_ms'],
                                                     budgets['p99_ratio_max'], f'http {key} p99_ms', failures)}

    matrix = json.loads((ROOT / 'benchmarks' / 'spring' / 'gc-matrix.json').read_text())
    for app in matrix['apps']:
        record = load(directory, f'gc-matrix-{app}.json', failures)
        if record is None:
            continue
        if record.get('mode') != 'production' or record.get('status') != 'passed':
            failures.append(f"gc-matrix-{app}.json: mode {record.get('mode')}, status {record.get('status')}")
        missing = set(matrix['settings']) - set(record.get('settings', {}))
        if missing:
            failures.append(f"gc-matrix-{app}.json: settings not measured: {', '.join(sorted(missing))}")
        for name, row in record.get('settings', {}).items():
            if row['suite']['passed'] != row['suite']['total']:
                failures.append(f'gc-matrix-{app}.json: the suite fails under {name}')
        report[f'gc matrix {app}'] = {name: row.get('against_go') for name, row in record.get('settings', {}).items()}
    return report, failures


if __name__ == '__main__':
    result, problems = spring_gate(sys.argv[1])
    print(json.dumps({'spring': result, 'failures': problems}, indent=2))
    sys.exit(1 if problems else 0)
