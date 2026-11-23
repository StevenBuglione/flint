"""Build measurements of the Spring side-by-side applications: `measure_builds.py --spring` (ADR-030 sections 5 and 8).

For each application of benchmarks/spring/apps.json this measures, with measure_builds' timing method (wall time
and process-tree peak RSS sampled every millisecond), nine trials of:

- **Go, the registered comparator** (pinned Go 1.27.4, `-trimpath -ldflags=-s -w`, CGO off, modules from the
  verified module cache with no network):
  - `go_std_cold_seconds`: a fresh copy of the source and a fresh clone of a GOCACHE primed with `go build std`;
  - `go_std_incremental_seconds`: the same tree rebuilt after appending a declaration to main.go;
  - `go_deps_cold_seconds`: as cold, but the cache is also primed with the comparator's third-party packages (the
    PostgreSQL or SQLite driver), the analogue of the native C libraries Flint's builds find prepared;
  - `go_scratch_seconds`: `go build -a` with an empty GOCACHE;
  - `binary_bytes` of the executable after GNU strip (built with -s -w, so strip takes little).
- **Flint, the port**, with the commands its `flint-spring.json` declares under `measure`:
  - `flint_cached_cold_seconds` and `flint_cached_incremental_seconds`: the development build with the platform
    cache (the pinned flint-framework and flint-boot analysis and archives, ADR-030 section 5), as built: the
    primary edit-build headline (owner decision 2, decisions.md);
  - `flint_static_cold_seconds` and `flint_static_incremental_seconds`: the same build linked fully static
    (`measure.cached_static`), the secondary edit-build headline;
  - `flint_scratch_seconds`: the same build with every module compiled from source and no platform cache;
  - `O3` and `Oz` binary sizes after GNU strip (flint's artifacts keep their symbol tables), as for Go.
- **Java, context only**: `mvn -o package` cold (no target/) and after a one-line edit, and the jar size; with
  --native-context, one Spring Boot native-image build with the pinned GraalVM, for its time and executable size.

The two headlines of ADR-030 section 5, each a median ratio with its bootstrap 99% interval and a 0.99 ceiling:
- primary: `flint_cached_cold_seconds` against `go_std_cold_seconds`;
- secondary: `flint_scratch_seconds` against `go_scratch_seconds`.
The incremental build and the Oz size against Go are verdicts too; `go_deps_cold_seconds` is published as the
stricter comparison and does not gate. A missing Flint port fails, unless --allow-missing-flint, which records the
Go and Java sides with status "incomplete"; such a record never passes a gate.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402
import vibe_bench  # noqa: E402

EXCLUDED = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native', '.native-sanitized', '.flint',
            '__pycache__'}


def copy_checkout(destination):
    def ignore(directory, names):
        excluded = set(EXCLUDED)
        if Path(directory).resolve() == ROOT:
            excluded |= {'artifacts', 'build'}
        return [name for name in names if name in excluded]
    shutil.copytree(ROOT, destination, ignore=ignore)


def go_env():
    env = vibe_bench.go_environment()
    env.update({'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOWORK': 'off', 'CGO_ENABLED': '0'})
    return env


def third_party_packages(go, directory, env):
    main = subprocess.run([go, 'list', '-m'], cwd=directory, env=env, capture_output=True, text=True,
                          check=True).stdout.strip()
    listed = subprocess.run([go, 'list', '-deps', '-f', '{{if not .Standard}}{{.ImportPath}}{{end}}', '.'],
                            cwd=directory, env=env, capture_output=True, text=True, check=True).stdout.split()
    return [path for path in listed if path != main and not path.startswith(main + '/')]


def measure_go(name, trials, timed, logs, temporary, result):
    go = vibe_bench.pinned_go()
    source = ROOT / spring_bench.app_row(name)['go']['directory']
    env = go_env()
    # The module cache must already hold every verified module; the measured builds never reach the network.
    subprocess.run([go, 'mod', 'download'], cwd=source, env=dict(vibe_bench.go_environment()), check=True,
                   capture_output=True)
    std, deps = temporary / f'{name}-prime-std', temporary / f'{name}-prime-deps'
    subprocess.run([go, 'build', '-buildvcs=false', '-trimpath', 'std'], cwd=source,
                   env=dict(env, GOCACHE=str(std)), check=True, capture_output=True)
    shutil.copytree(std, deps)
    packages = third_party_packages(go, source, env)
    if packages:
        subprocess.run([go, 'build', '-buildvcs=false', '-trimpath', *packages], cwd=source,
                       env=dict(env, GOCACHE=str(deps)), check=True, capture_output=True)
    build = [go, 'build', '-buildvcs=false', '-trimpath', '-ldflags=-s -w', '-o']
    row = {key: [] for key in ('go_std_cold_seconds', 'go_std_incremental_seconds', 'go_deps_cold_seconds',
                               'go_scratch_seconds')}
    row['third_party_packages'] = packages
    sizes = set()
    for trial in range(trials):
        for flavour in ('std', 'deps', 'scratch'):
            work = temporary / f'{name}-go-{flavour}-{trial}'
            shutil.copytree(source, work)
            cache = temporary / f'{name}-cache-{flavour}-{trial}'
            if flavour == 'scratch':
                cache.mkdir()
            else:
                shutil.copytree(std if flavour == 'std' else deps, cache, copy_function=os.link)
            command = build + [work / 'comparator'] + (['-a'] if flavour == 'scratch' else []) + ['.']
            states = ['cold', 'incremental'] if flavour == 'std' else ['cold']
            for state in states:
                if state == 'incremental':
                    with (work / 'main.go').open('a', encoding='utf-8') as output:
                        output.write(f'\nconst flintMeasureEdit{trial} = {trial}\n')
                log = logs / f'{name}-go-{flavour}-{state}-{trial}.log'
                observed = timed(command, work, dict(env, GOCACHE=str(cache)), log)
                key = 'go_scratch_seconds' if flavour == 'scratch' else f'go_{flavour}_{state}_seconds'
                row[key].append(observed['seconds'])
                result['trials'].append(dict(observed, app=name, implementation='go', flavour=flavour, state=state,
                                             trial=trial, log=str(log.relative_to(logs.parent))))
            sizes.add(stripped(work / 'comparator', temporary)['binary_bytes'])
            shutil.rmtree(work)
            shutil.rmtree(cache)
    if len(sizes) != 1:
        raise RuntimeError(f'{name}: the Go comparator built to different sizes {sorted(sizes)}; builds are not reproducible')
    row['binary_bytes'] = sizes.pop()
    return row


def measure_flint(name, trials, timed, logs, temporary, result):
    """The Flint port, built in place. flint.lock records where the platform packages are, so a copy of the checkout
    at another path resolves a different graph (FLINT-E0202); instead every cold trial starts from a project with no
    .flint state (no objects, no generated AOT code, no build cache), and the edited source is restored after each
    trial."""
    directory = ROOT / spring_bench.app_row(name)['flint']['directory']
    spec = json.loads((directory / 'flint-spring.json').read_text())['measure']
    row = {'flint_cached_cold_seconds': [], 'flint_cached_incremental_seconds': [], 'flint_scratch_seconds': []}
    # Owner decision 2 (decisions.md, 2026-11-23): edit builds report the dev profile as built (shared-object linking
    # of the platform cache) as the primary headline, and the same build linked fully static as the secondary. A
    # port declares the static command as measure.cached_static.
    flavours = ['cached', 'scratch'] + (['cached_static'] if spec.get('cached_static') else [])
    if 'cached_static' in flavours:
        row.update(flint_static_cold_seconds=[], flint_static_incremental_seconds=[])
    # A flint cache of this measurement's own (the platform archives and the digest log), primed by the first build.
    cache = temporary / f'{name}-flint-cache'
    env = dict(os.environ, FLINT_CACHE=str(cache))
    edit = directory / spec['edit_source']
    original = edit.read_bytes()

    def clean():
        shutil.rmtree(directory / '.flint', ignore_errors=True)
        # Cold means a cold digest log too: its entries are keyed by stat data, and an in-place port keeps its
        # files' stat data between trials, which Go's fresh source copies do not (decisions.md, 2026-11-23).
        (cache / 'digests.log').unlink(missing_ok=True)

    try:
        # The platform cache (ADR-030 section 5) lives outside the port, so clearing the port's .flint keeps it. One
        # unscored build primes it, as measure_builds primes the DMD compile server, and its time is recorded.
        clean()
        log = logs / f'{name}-flint-prime.log'
        observed = timed(spec['cached'], directory, env, log)
        row['flint_first_build_seconds'] = observed['seconds']
        row['dev_linker'] = dev_linker(env)
        row['flint_cache'] = {'platform_cache_primed': True, 'digest_log_cleared_before_cold_trials': True}
        for trial in range(trials):
            for flavour in flavours:
                clean()
                states = ['cold'] if flavour == 'scratch' else ['cold', 'incremental']
                for state in states:
                    if state == 'incremental':
                        with edit.open('a', encoding='utf-8') as output:
                            output.write(f'\nenum flintMeasureEdit{trial} = {trial};\n')
                    log = logs / f'{name}-flint-{flavour}-{state}-{trial}.log'
                    observed = timed(spec[flavour], directory, env, log)
                    key = {'scratch': 'flint_scratch_seconds', 'cached': f'flint_cached_{state}_seconds',
                           'cached_static': f'flint_static_{state}_seconds'}[flavour]
                    row[key].append(observed['seconds'])
                    result['trials'].append(dict(observed, app=name, implementation='flint', flavour=flavour,
                                                 state=state, trial=trial, log=str(log.relative_to(logs.parent))))
                edit.write_bytes(original)
        for profile in ('O3', 'Oz'):
            clean()
            log = logs / f'{name}-flint-{profile}.log'
            timed(spec[profile]['command'], directory, env, log)
            if spec[profile].get('binary'):
                binary = directory / spec[profile]['binary']
            else:
                # The profile's command ends in --json; ask the same build, now up to date, where its artifact is.
                reported = subprocess.run(spec[profile]['command'], cwd=directory, env=env, capture_output=True,
                                          text=True)
                binary = spring_bench.flint_artifact(reported.stdout, directory)
            row[profile] = dict(stripped(binary, temporary), sha256=spring_bench.sha256(binary))
    finally:
        edit.write_bytes(original)
    return row


def stripped(binary, temporary):
    """Sizes compare stripped against stripped: a copy of the executable goes through the same GNU strip for Flint
    and Go (flint's release and size artifacts keep their symbol tables; the Go comparator is built with
    -ldflags=-s -w, and strip takes little more from it)."""
    strip = shutil.which('strip')
    if not strip:
        raise RuntimeError('strip is required for size measurements')
    copy = Path(temporary) / ('stripped-' + Path(binary).name)
    shutil.copy2(binary, copy)
    subprocess.run([strip, str(copy)], check=True)
    version = subprocess.run([strip, '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    size = copy.stat().st_size
    copy.unlink()
    return {'binary_bytes': size, 'unstripped_bytes': Path(binary).stat().st_size, 'strip': version}


def dev_linker(env):
    """The ELF linker the dev-profile DMD on PATH links with: the -fuse-ld its dmd.conf sets, else the system
    default (ld.bfd)."""
    dmd = shutil.which('dmd', path=env.get('PATH'))
    if not dmd:
        return None
    config = Path(dmd).resolve().parent / 'dmd.conf'
    text = config.read_text() if config.is_file() else ''
    for linker in ('mold', 'lld'):
        if f'-fuse-ld={linker}' in text:
            return linker
    return 'system default (ld.bfd)'


def measure_java(name, trials, timed, logs, temporary, result, native=False):
    """Context only: Maven builds of the reference, offline from the verified repository."""
    source = spring_bench.fetch(name)
    spring_bench.build_java(name)  # resolves every artifact once, with --strict-checksums
    _, maven, env = vibe_bench.java_environment()
    repository = ROOT / '.flint' / 'peers' / 'm2'
    command = [maven, '-o', '-B', '-q', '-Dmaven.repo.local=' + str(repository), '-DskipTests', 'package']
    java_files = sorted((source / 'src' / 'main' / 'java').rglob('*Application.java'))
    row = {'java_cold_seconds': [], 'java_incremental_seconds': []}
    for trial in range(trials):
        work = temporary / f'{name}-java-{trial}'
        shutil.copytree(source, work, ignore=shutil.ignore_patterns('target'))
        for state in ('cold', 'incremental'):
            if state == 'incremental':
                with (work / java_files[0].relative_to(source)).open('a', encoding='utf-8') as output:
                    output.write(f'\n// flint measure edit {trial}\n')
            log = logs / f'{name}-java-{state}-{trial}.log'
            observed = timed(command, work, env, log)
            row[f'java_{state}_seconds'].append(observed['seconds'])
            result['trials'].append(dict(observed, app=name, implementation='java', state=state, trial=trial,
                                         log=str(log.relative_to(logs.parent))))
        jar = work / spring_bench.app_row(name)['java']['jar']
        row['jar_bytes'] = jar.stat().st_size
        shutil.rmtree(work)
    if native:
        # One native-image build, for its time and executable size: minutes per build, and context only.
        started = time.monotonic()
        try:
            binary = spring_bench.build_java_native(name)
            row['native'] = {'build_seconds_single': time.monotonic() - started, 'binary_bytes': binary.stat().st_size,
                             'sha256': spring_bench.sha256(binary), 'graalvm': json.loads(
                                 (ROOT / 'policy' / 'peer-lock.json').read_text())['peers']['graalvm']['version']}
        except SystemExit as exc:
            row['native'] = {'error': str(exc)[:1000]}
    return row


def verdicts(name, flint, go, ceiling):
    from perf_stats import median_ratio_interval
    pairs = {
        'primary: platform cache vs std-primed GOCACHE': ('flint_cached_cold_seconds', 'go_std_cold_seconds', True),
        'secondary: from scratch vs go build -a': ('flint_scratch_seconds', 'go_scratch_seconds', True),
        'incremental: dev profile as built': ('flint_cached_incremental_seconds', 'go_std_incremental_seconds', True),
        'incremental: fully static': ('flint_static_incremental_seconds', 'go_std_incremental_seconds', True),
        'stricter: platform cache vs deps-primed GOCACHE': ('flint_cached_cold_seconds', 'go_deps_cold_seconds', False),
    }
    out = {}
    for label, (mine, theirs, gating) in pairs.items():
        if mine not in flint:
            out[label] = {'gating': gating, 'pass': False,
                          'note': 'not measured: the port declares no measure.cached_static command'}
            continue
        median, lower, upper = median_ratio_interval(flint[mine], go[theirs])
        out[label] = {'median_ratio': median, 'lower_99': lower, 'upper_99': upper, 'gating': gating,
                      'pass': median <= ceiling and upper <= ceiling}
    size = flint['Oz']['binary_bytes'] / go['binary_bytes']
    out['Oz binary size'] = {'ratio': size, 'gating': True, 'pass': size <= ceiling}
    return out


def measure(args, timed):
    if args.trials < 9 and not args.smoke:
        raise SystemExit('production build evidence needs 9 trials; use --smoke for a shorter harness check')
    budgets = json.loads((ROOT / 'policy' / 'budgets.json').read_text())['go_relative']
    names = args.spring_app or list(spring_bench.registry()['apps'])
    problems = spring_bench.check_registry(names)
    if problems:
        raise SystemExit('Go comparators: ' + '; '.join(problems))
    missing = [n for n in names if not spring_bench.flint_port_ready(n)]
    if missing and not args.allow_missing_flint:
        raise SystemExit('the Flint port is missing for ' + ', '.join(missing) + '; a missing port fails its claim '
                         '(pass --allow-missing-flint to record the Go and Java sides as an incomplete record)')
    load = os.getloadavg()[0]
    if load >= 1.0 and not args.smoke:
        raise SystemExit(f'the runner is busy (1-minute load {load:.2f}); measure when it is otherwise quiet')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    logs = args.output.parent / (args.output.stem + '-logs')
    logs.mkdir(exist_ok=True)
    result = {'schema': 'flint.spring-builds/1', 'mode': 'smoke' if args.smoke else 'production', 'status': 'running',
              'commit': subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip(),
              'host': {'platform': sys.platform, 'cpus': os.cpu_count(), 'load_average_at_start': load},
              'trials_per_series': args.trials, 'comparators': {n: json.loads(spring_bench.REGISTRY.read_text())['comparators'][n] for n in names},
              'missing_flint': missing, 'apps': {}, 'trials': []}
    try:
        with tempfile.TemporaryDirectory(prefix='flint-spring-builds-') as temporary:
            temporary = Path(temporary)
            for name in names:
                print('Measuring', name, flush=True)
                row = {'go': measure_go(name, args.trials, timed, logs, temporary, result)}
                if name not in missing:
                    row['flint'] = measure_flint(name, args.trials, timed, logs, temporary, result)
                    if args.trials >= 9:
                        row['verdicts'] = verdicts(name, row['flint'], row['go'], budgets['rest_build_ratio_max'])
                    else:
                        row['verdicts'] = {}
                        row['note'] = 'fewer than 9 trials: no ratios or verdicts (a smoke run is never evidence)'
                if not args.no_context:
                    row['context'] = {'java': measure_java(name, args.trials, timed, logs, temporary, result,
                                                           native=args.native_context)}
                result['apps'][name] = row
        gating = [v['pass'] for row in result['apps'].values() for v in row.get('verdicts', {}).values() if v['gating']]
        result['status'] = 'incomplete' if missing else ('passed' if all(gating) else 'failed')
    except Exception as exc:
        result['status'] = 'failed'
        result['error'] = str(exc)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        raise
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for name, row in result['apps'].items():
        go = row['go']
        print(f"{name}: Go std-primed cold {min(go['go_std_cold_seconds']):.3f}s, -a {min(go['go_scratch_seconds']):.3f}s, "
              f"binary {go['binary_bytes']} bytes")
        for label, verdict in row.get('verdicts', {}).items():
            print(f"  {label}: {verdict.get('median_ratio', verdict.get('ratio')):.3f}", 'pass' if verdict['pass'] else 'FAIL')
    print('Wrote Spring build evidence', args.output, f"({result['status']})")
    return 0 if result['status'] == 'passed' or (result['status'] == 'incomplete' and args.allow_missing_flint) else 1
