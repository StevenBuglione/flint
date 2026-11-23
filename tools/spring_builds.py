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
  - `flint_cached_cold_digests_cleared_seconds`: the cached cold build with flint's digest log cleared too, published
    as non-gating context beside the primary (coordinator, decisions.md 2026-11-23, condition 3);
  - every measured command matches Go's -s -w (`flint build --no-debug`: no debug information, no symbol table;
    owner decision 4b27d207); `flint_debug_*` repeats the cached, static and scratch series with debug information
    (`measure.context_debug`, the commands without --no-debug), published as non-gating context;
  - `phase_medians_ms` per series: the median wall time of each build phase (total, flint, aot, plan, compile,
    link; -1 means absent) from flint's build receipt (phases_ms, d2a929cd), beside the coordinator's budget (`phase_budget_ms`);
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
import re
import statistics
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


# Project-keyed entries of a flint cache (flint-aot's 64b85d08: the project's AOT models, their annotation sets and
# generated output under projects/<root hash>/aot). The rest is platform and toolchain state, including the digest
# log, whose entries under the port are pruned (coordinator, decisions.md 2026-11-23, confirming 1235dc4b).
PROJECT_CACHE_ENTRIES = ('projects',)
DIGEST_LOG = 'digests.log'
AOT_SUMMARY = re.compile(r'Generated \d+ Flint AOT modules for \S+ \((\d+) extracted in \d+ ms, (\d+) from the shared cache')


def platform_only_cache(cache, platform, port):
    """`platform`: a hard-link copy of the primed `cache` without its project-keyed entries, the analogue of Go's
    std-only GOCACHE. Refuses a cache in which the port's path still appears outside them (a project-keyed entry in
    an unexpected place): every text file is searched, archives and objects excepted."""
    shutil.copytree(cache, platform, copy_function=os.link, symlinks=True)
    for name in PROJECT_CACHE_ENTRIES:
        path = platform / name
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)
    pruned = 0
    log = platform / DIGEST_LOG
    if log.is_file():
        # A copy of its own, without the port's entries: an in-place port keeps its files' stat data between
        # trials, which Go's fresh source copies do not.
        prefixes = tuple({str(port) + os.sep, str(Path(port).resolve()) + os.sep})
        lines = log.read_text().splitlines(keepends=True)
        kept = [line for line in lines if not line.startswith(prefixes)]
        pruned = len(lines) - len(kept)
        log.unlink()
        log.write_text(''.join(kept))
    needles = {str(port).encode(), str(Path(port).resolve()).encode()}
    found = []
    for path in platform.rglob('*'):
        if not path.is_file() or path.is_symlink() or path.suffix in ('.a', '.o', '.so', '.lib', '.obj'):
            continue
        if path.stat().st_size > 16 << 20:
            continue
        data = path.read_bytes()
        if b'\0' in data[:4096]:
            continue
        if any(needle in data for needle in needles):
            found.append(str(path.relative_to(platform)))
    if found:
        raise RuntimeError(f'the platform-only flint cache still names the port ({port}) in: {", ".join(found[:8])}; '
                           'a project-keyed entry is outside projects/')
    return pruned


def cache_snapshot(directory):
    """Path, size, mtime and inode of every file: a hard-link clone shares inodes, so a build that wrote a platform
    entry in place would change the master the next trial is cloned from."""
    return {str(p.relative_to(directory)): (st.st_size, st.st_mtime_ns, st.st_ino)
            for p in directory.rglob('*') if p.is_file() and not p.is_symlink() for st in [p.stat()]}


def aot_counts(log):
    """(extracted, from the shared cache) of the AOT step in a build log, or None when it reported nothing."""
    match = AOT_SUMMARY.search(Path(log).read_text(errors='replace'))
    return (int(match.group(1)), int(match.group(2))) if match else None


def measure_flint(name, trials, timed, logs, temporary, result):
    """The Flint port, built in place. flint.lock records where the platform packages are, so a copy of the checkout
    at another path resolves a different graph (FLINT-E0202); instead every cold trial starts from a project with no
    .flint state (no objects, no generated AOT code, no build cache) and a fresh hard-link clone of the platform-only
    cache, deleted after the trial, as Go's cold trials start from a clone of a std-only GOCACHE (coordinator,
    2026-11-23). The edited source is restored after each trial."""
    directory = ROOT / spring_bench.app_row(name)['flint']['directory']
    spec = json.loads((directory / 'flint-spring.json').read_text())['measure']
    # Owner decision 2 (decisions.md, 2026-11-23): edit builds report the dev profile as built (shared-object linking
    # of the platform cache) as the primary headline, and the same build linked fully static as the secondary. A
    # port declares the static command as measure.cached_static. Owner decision 4b27d207: the measured commands match
    # Go's -s -w (flint build --no-debug); the same builds with debug information (measure.context_debug) are
    # published beside them as non-gating context.
    debug = spec.get('context_debug', {})
    # flavour: (command, states, digest log, series key with {state})
    table = {
        'cached': (spec['cached'], ('cold', 'incremental'), 'keep', 'flint_cached_{state}_seconds'),
        'cached_cleared': (spec['cached'], ('cold',), 'clear', 'flint_cached_cold_digests_cleared_seconds'),
        'scratch': (spec['scratch'], ('cold',), 'clear', 'flint_scratch_seconds'),
        'cached_static': (spec.get('cached_static'), ('cold', 'incremental'), 'keep', 'flint_static_{state}_seconds'),
        'debug_cached': (debug.get('cached'), ('cold', 'incremental'), 'keep', 'flint_debug_cached_{state}_seconds'),
        'debug_static': (debug.get('cached_static'), ('cold', 'incremental'), 'keep',
                         'flint_debug_static_{state}_seconds'),
        'debug_scratch': (debug.get('scratch'), ('cold',), 'clear', 'flint_debug_scratch_seconds'),
    }
    flavours = [name for name, (command, *_rest) in table.items() if command]
    row = {table[f][3].format(state=state): [] for f in flavours for state in table[f][1]}
    # A flint cache of this measurement's own, primed by the first build; the trials use clones of its platform part.
    cache = temporary / f'{name}-flint-cache'
    platform = temporary / f'{name}-flint-platform-cache'
    trial_cache = temporary / f'{name}-flint-trial-cache'
    env = dict(os.environ, FLINT_CACHE=str(cache))
    edit = directory / spec['edit_source']
    original = edit.read_bytes()

    def clean(digests='keep'):
        """A cold project (no .flint) and a fresh clone of the platform-only cache. Its digest log is a real copy, as
        flint appends to it; scratch trials and the context series start without one."""
        shutil.rmtree(directory / '.flint', ignore_errors=True)
        shutil.rmtree(trial_cache, ignore_errors=True)
        if platform.is_dir():
            shutil.copytree(platform, trial_cache, copy_function=os.link, symlinks=True,
                            ignore=lambda path, names: [DIGEST_LOG] if Path(path) == platform else [])
            if digests == 'keep' and (platform / DIGEST_LOG).is_file():
                shutil.copyfile(platform / DIGEST_LOG, trial_cache / DIGEST_LOG)

    phases = {}
    try:
        # The platform cache (ADR-030 section 5) lives outside the port, so clearing the port's .flint keeps it. One
        # unscored build per cached command primes it (debug and no-debug archives have different keys, and a static
        # build records its commands), as measure_builds primes the DMD compile server; the times are recorded.
        primes = [f for f in ('cached', 'cached_static', 'debug_cached', 'debug_static') if f in flavours]
        row['flint_prime_seconds'] = {}
        for flavour in primes:
            clean()
            observed = timed(table[flavour][0], directory, env, logs / f'{name}-flint-prime-{flavour}.log')
            row['flint_prime_seconds'][flavour] = observed['seconds']
        row['flint_first_build_seconds'] = row['flint_prime_seconds']['cached']
        row['dev_linker'] = dev_linker(env)
        # A port without @FlintApplication has no AOT step to check.
        has_aot = aot_counts(logs / f'{name}-flint-prime-cached.log') is not None
        pruned = platform_only_cache(cache, platform, directory)
        master = cache_snapshot(platform)
        env = dict(os.environ, FLINT_CACHE=str(trial_cache))
        aot = {}
        row['flint_cache'] = {'platform_cache_primed': True,
                              'cold_trials': 'a fresh hard-link clone of the primed cache without '
                                             + ' and '.join(PROJECT_CACHE_ENTRIES) + ', deleted after the trial',
                              'platform_cache_files': len(master),
                              'digest_log': 'kept (a copy per trial), its entries under the port pruned; absent in '
                                            'scratch trials and the digests-cleared context series',
                              'port_entries_pruned': pruned}
        for trial in range(trials):
            for flavour in flavours:
                command, states, digests, series = table[flavour]
                clean(digests)
                for state in states:
                    if state == 'incremental':
                        with edit.open('a', encoding='utf-8') as output:
                            output.write(f'\nenum flintMeasureEdit{trial} = {trial};\n')
                    log = logs / f'{name}-flint-{flavour}-{state}-{trial}.log'
                    began = time.time() - 1
                    observed = timed(command, directory, env, log)
                    key = series.format(state=state)
                    row[key].append(observed['seconds'])
                    phases.setdefault(key, []).append(build_phases(directory, began))
                    if state == 'cold' and has_aot:
                        counts = aot_counts(log)
                        aot.setdefault(key, []).append(counts)
                        # A cold trial extracts the project's own models: none of them may come from a cache.
                        if counts is None or counts[0] == 0:
                            raise RuntimeError(f'{name}: cold trial {trial} ({flavour}) reused project-keyed AOT '
                                               f'state (AOT step {counts}); see {log}')
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
        if cache_snapshot(platform) != master:
            raise RuntimeError(f'{name}: a build changed the platform-only cache in place through a hard link')
        row['flint_cache']['aot_extracted_and_shared_per_cold_trial'] = aot
    finally:
        edit.write_bytes(original)
        shutil.rmtree(trial_cache, ignore_errors=True)
    # Per-phase medians (flint, AOT, plan, compile, link) per series, beside the build-time budget.
    row['phase_medians_ms'] = {key: phase_medians(trials) for key, trials in phases.items() if any(trials)}
    row['phase_budget_ms'] = PHASE_BUDGET_MS
    row['phase_trials_ms'] = phases
    return row


PHASES = ('total', 'flint', 'aot', 'plan', 'compile', 'link')
# The coordinator's build-time budget for gs-rest-service (2026-11-23), reported beside the phase medians, not gated.
PHASE_BUDGET_MS = {'total': 100, 'flint': 20, 'compile': 60, 'link': 20}


def build_phases(directory, since):
    """The phases_ms of the flint build receipt written during this trial (m7-flint-cli's receipt spec:
    <port>/.flint/build/<profile>/<executable>.receipt.json, integer wall-time milliseconds; compile and link are
    absent when DUB does not report them). None when no receipt from this trial carries phases_ms."""
    receipts = [path for path in Path(directory).glob('.flint/build/*/*.receipt.json') if path.stat().st_mtime >= since]
    for path in sorted(receipts, key=lambda p: p.stat().st_mtime, reverse=True):
        phases = json.loads(path.read_text()).get('phases_ms')
        if isinstance(phases, dict):
            # compile and link are -1 when DUB reported neither (plan then holds the whole DUB process): absent.
            return {key: value for key, value in phases.items()
                    if key in PHASES and isinstance(value, int) and value >= 0}
    return None


def phase_medians(trials):
    """Median milliseconds per phase over the trials that reported it."""
    out = {}
    for phase in PHASES:
        values = [trial[phase] for trial in trials if trial and phase in trial]
        if values:
            out[phase] = statistics.median(values)
    return out


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
        'context: primary with the digest log cleared': ('flint_cached_cold_digests_cleared_seconds',
                                                         'go_std_cold_seconds', False),
        'context: primary with debug information': ('flint_debug_cached_cold_seconds', 'go_std_cold_seconds', False),
        'context: secondary with debug information': ('flint_debug_scratch_seconds', 'go_scratch_seconds', False),
        'context: edit build, dev profile, with debug information': ('flint_debug_cached_incremental_seconds',
                                                                     'go_std_incremental_seconds', False),
        'context: edit build, fully static, with debug information': ('flint_debug_static_incremental_seconds',
                                                                      'go_std_incremental_seconds', False),
    }
    out = {}
    for label, (mine, theirs, gating) in pairs.items():
        if mine not in flint:
            if gating:
                out[label] = {'gating': gating, 'pass': False,
                              'note': 'not measured: the port declares no measure.cached_static command'}
            continue
        median, lower, upper = median_ratio_interval(flint[mine], go[theirs])
        out[label] = {'median_ratio': median, 'lower_99': lower, 'upper_99': upper, 'gating': gating,
                      'pass': median <= ceiling and upper <= ceiling}
    size = flint['Oz']['binary_bytes'] / go['binary_bytes']
    out['Oz binary size'] = {'ratio': size, 'gating': True, 'pass': size <= ceiling}
    third_party_context(out, go)
    return out


def third_party_context(out, go):
    """For a comparator with third-party packages, the deps-primed ratio stands beside the primary (coordinator,
    2026-11-23): Go's std-primed cold build compiles them from source while Flint links its native libraries and
    platform archives prebuilt, so the primary alone overstates Flint's lead. The gating definitions are unchanged."""
    packages = go.get('third_party_packages') or []
    primary = out.get('primary: platform cache vs std-primed GOCACHE')
    stricter = out.get('stricter: platform cache vs deps-primed GOCACHE')
    if not packages or not primary or not stricter:
        return
    primary['third_party_context'] = {
        'deps_primed_ratio': stricter['median_ratio'], 'deps_primed_lower_99': stricter['lower_99'],
        'deps_primed_upper_99': stricter['upper_99'], 'packages': len(packages),
        'note': f"Go's std-primed cold build compiles its {len(packages)} third-party package(s) from source, while "
                "Flint links its native libraries and platform archives prebuilt; the deps-primed ratio is the "
                "like-for-like comparison."}
    secondary = out.get('secondary: from scratch vs go build -a')
    if secondary:
        secondary['third_party_context'] = {
            'note': "No deps-primed equivalent exists: go build -a recompiles every package, the third-party ones "
                    "included, while Flint's --no-platform-cache rebuilds the D modules but links the native C "
                    "libraries prebuilt."}


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
    # Under tools/measure_queue.py the queue certifies the window (see load_bench.spring_quiet).
    if load >= 1.0 and not args.smoke and os.environ.get('FLINT_MEASURE_WINDOW_CERTIFIED') != '1':
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
        for series, medians in row.get('flint', {}).get('phase_medians_ms', {}).items():
            print(f'{name} {series} phase medians (ms):',
                  ', '.join(f'{phase} {medians[phase]:g}' + (f' (budget {PHASE_BUDGET_MS[phase]})'
                                                                if phase in PHASE_BUDGET_MS else '')
                            for phase in PHASES if phase in medians))
        go = row['go']
        print(f"{name}: Go std-primed cold {min(go['go_std_cold_seconds']):.3f}s, -a {min(go['go_scratch_seconds']):.3f}s, "
              f"binary {go['binary_bytes']} bytes")
        for label, verdict in row.get('verdicts', {}).items():
            print(f"  {label}: {verdict.get('median_ratio', verdict.get('ratio')):.3f}", 'pass' if verdict['pass'] else 'FAIL')
            context = verdict.get('third_party_context')
            if context and 'deps_primed_ratio' in context:
                print(f"    deps-primed: {context['deps_primed_ratio']:.3f} ({context['deps_primed_lower_99']:.3f}-"
                      f"{context['deps_primed_upper_99']:.3f}); {context['note']}")
            elif context:
                print(f"    {context['note']}")
    print('Wrote Spring build evidence', args.output, f"({result['status']})")
    return 0 if result['status'] == 'passed' or (result['status'] == 'incomplete' and args.allow_missing_flint) else 1
