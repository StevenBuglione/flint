"""A reproducible local load recipe for profiling the Spring workloads: `spring_bench.py profile` (never evidence).

    spring_bench.py profile gs-rest-service [--flint-binary <path>] [--runs 3] [--seconds 15]
    spring_bench.py profile gs-rest-service:not-found --manifest policy/spring-error-paths-benchmark.json

It drives the same code as the evidence run: load_bench's Spring measurement, with the workload's request, the pinned
oha and its flags, the manifest's server, load and database CPU sets, the same response checks, and Flint interleaved
with the registered Go comparator in every run. Only the phases are shorter (`--warmup`, `--seconds`) and there are
fewer runs, so before-and-after numbers taken on one machine with this recipe are comparable with each other, though
not with evidence. It refuses to run while the measurement queue holds .flint/measure/MEASURING, so profiling never
spoils a timed run, and it does not check that the machine is quiet: run both sides of a comparison back to back.
"""
from __future__ import annotations

import contextlib
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import measure_queue  # noqa: E402
import spring_bench  # noqa: E402


def cpus(text):
    return sorted(load_bench.cpu_list(text)) if text else None


def main(args):
    lock = measure_queue.LOCK
    for root in measure_queue.checkout_roots():
        candidate = root / '.flint' / 'measure' / 'MEASURING'
        if candidate.is_file() or lock.is_file():
            raise SystemExit(f'a timed run is in progress ({candidate if candidate.is_file() else lock}); profile '
                             'when it has finished')
    manifest_path = ROOT / args.manifest
    manifest = json.loads(manifest_path.read_text())
    if args.workload not in manifest['apps']:
        raise SystemExit(f"{args.workload} is not a workload of {args.manifest}: {', '.join(manifest['apps'])}")
    spec = manifest['apps'][args.workload]
    app = spec.get('app', args.workload)
    workload = dict(manifest['workload'], runs=args.runs, duration_seconds=args.seconds, capacity_seconds=args.seconds,
                    warmup_seconds=args.warmup)
    for key, override in (('server_cpus', cpus(args.server_cpus)), ('load_cpus', cpus(args.load_cpus)),
                          ('database_cpus', cpus(args.database_cpus))):
        if override:
            workload[key] = override
    if args.rate:
        spec = dict(spec, fixed_rate_qps=args.rate)
    oha = Path(args.oha) if args.oha else next(
        (p for p in [*(r / '.tools' / 'oha-1.16.0' / 'oha' for r in measure_queue.checkout_roots())] if p.is_file()), None)
    if oha is None or load_bench.file_hash(oha) != load_bench.OHA_SHA256:
        raise SystemExit('the pinned oha is missing; tools/install_toolchains.py --compiler oha')
    targets = args.impl or ['flint', 'go']
    binaries = {'flint': args.flint_binary, 'go': args.go_binary}
    if 'go' in targets and not binaries['go']:
        spring_bench.build_go(app)
    if 'flint' in targets and not binaries['flint']:
        spring_bench.build_flint(app)
    outdir = Path(args.output or ROOT / 'build' / 'spring' / 'profile' / args.workload.replace(':', '-'))
    outdir.mkdir(parents=True, exist_ok=True)
    series = {target: {key: [] for key in load_bench.FIELDS} for target in targets}
    database_context = (spring_bench.postgres_cluster(workload['database_cpus'])
                        if spring_bench.app_row(app).get('database') == 'postgres' else contextlib.nullcontext())
    with database_context as database:
        for run in range(args.runs):
            for target in (targets if run % 2 == 0 else list(reversed(targets))):
                row = load_bench.spring_measure(spring_bench, app, spec, target, workload, oha, run, outdir,
                                                manifest.get('environment', {}), database, True,
                                                binary=binaries[target])
                for key in load_bench.FIELDS:
                    series[target][key].append(row['capacity' if key == 'requests_per_second' else 'latency'][key])
                print(json.dumps({'workload': args.workload, 'run': run, 'target': target, 'status': 'measured'}),
                      flush=True)
    medians = {t: {k: statistics.median(v) for k, v in s.items()} for t, s in series.items()}
    summary = {'schema': 'flint.spring-profile/1', 'note': 'a local profiling recipe; never evidence',
               'workload': args.workload, 'manifest': args.manifest, 'effective_workload': workload,
               'binaries': {t: binaries[t] for t in targets}, 'series': series, 'medians': medians}
    (outdir / 'profile.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f"{'metric':22} " + ' '.join(f'{t:>14}' for t in targets) + ('   flint/go' if set(targets) == {'flint', 'go'} else ''))
    for key in load_bench.FIELDS:
        cells = ' '.join(f'{medians[t][key]:14.3f}' for t in targets)
        ratio = f"   {medians['flint'][key] / medians['go'][key]:8.3f}" if set(targets) == {'flint', 'go'} else ''
        print(f'{key:22} {cells}{ratio}')
    print('Wrote', outdir / 'profile.json')
    return 0
