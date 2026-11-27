#!/usr/bin/env python3
"""The mechanical porter's correctness gate (docs/spring/phase2/porter-plan.md), run as gates.py --gate porter.

  (a) determinism: the corpus is ported twice under different locales, time zones and job orders, and every
      committed generated region is regenerated at its recorded request; any byte difference fails;
  (b) corpus reproduction: every hand-ported public top-level type whose type row maps to a D symbol is offered to
      `flint port-spring`. An accepted declaration must be API-identical to the hand port: no mapping difference,
      and the same compile-time description (tools/port-spring/gate/porter_describe.d) on DMD and LDC once spliced
      into a copy of the hand module. The owning package's unit tests then run against the spliced tree on both
      compilers. A divergence fails unless api/porter-baseline.json lists it with a reason, and that list only
      shrinks; the reproduced count per shape only grows;
  (d) generated regions stay generated: each `// port:generated` region's digest must match its text outside the
      `// port:body` regions, and no `// port:body` region anywhere may still hold its `assert(0)` placeholder: a
      lane fills the body or emits with --strip-pending before landing (coordinator, 2026-11-27).

The Java Beans shape (tools/port-spring/beans.py) derives boot's `@ConfigurationProperties` spec from the pinned
sources. Each hand-spec field it reproduces exactly counts toward the `configuration-properties-field` shape, whose
floor only grows; the derivation runs twice, in opposite class orders, and must agree.

The R6 accessor shape (tools/port-spring/accessors.py) is measured per element: every trivial getter and setter of
a hand-ported class is derived, spliced over the hand member and described on DMD and LDC, and its row compared. Its
reproduced count is the `r6-accessor` floor, and its divergences are listed per element under
"accessorDivergences", which only shrinks.

The pure-bean shape (tools/port-spring/bean_types.py) derives whole classes made of fields, trivial accessors and
mechanical constructors, splices each over the hand class, compares its non-private API on DMD and LDC and its rows,
and runs the owning package's tests. Its reproduced count is the `bean-class` floor, and its divergences are listed
per type under "beanDivergences", which only shrinks.

Committed skeleton regions (`port-skeleton/N`, skeletons.py --emit) are regenerated from the tree with the bodies
their file holds, under (a).

Skeleton mode (tools/port-spring/skeletons.py) declares every member of each hand-ported class and interface,
derives the mechanical bodies and marks the rest, splices the skeleton over the hand type and compares each member's
description on DMD and LDC and its row. Its reproduced element count is the `skeleton` floor; "skeletonDivergences"
lists, per type, how many of its elements diverge, and neither a new type nor a larger count is accepted.

Missing inputs (flint, the native helper, a pinned source cache, a compiler) are errors, never passes. Run it under
tools/measure_queue.py hold on venus: it compiles.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from api_differences import Classifier  # noqa: E402
sys.path.insert(0, str(ROOT / 'tools' / 'port-spring'))
import accessors  # noqa: E402
import bean_types  # noqa: E402
import beans  # noqa: E402
import skeletons  # noqa: E402

MARKER, END, BODY, BODY_END = '// port:generated ', '// port:end', '// port:body ', '// port:end-body'
BASELINE = ROOT / 'api' / 'porter-baseline.json'
DESCRIBER = ROOT / 'tools' / 'port-spring' / 'gate'
COMPILERS = ('dmd', 'ldc2')
KEYWORDS = {'struct', 'class', 'interface', 'enum', 'union'}


class EnvironmentProblem(Exception):
    """An input the gate needs is missing: exit 2, never a pass."""


# ---- (d) generated regions ----

def digest_text(body):
    """A region's text as its digest covers it; mirrors flint_tool.api.portspring.regionDigestText."""
    out, inside = [], False
    for line in body.splitlines():
        trimmed = line.strip()
        if trimmed.startswith(BODY):
            inside = True
        elif trimmed == BODY_END:
            inside = False
        elif not inside:
            out.append(line + '\n')
    return ''.join(out)


def regions(text):
    """(line number, version, upstream, type, digest, body) for every generated region; raises on a malformed one."""
    lines = text.splitlines(keepends=True)
    found, i = [], 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith(MARKER.strip() + ' '):
            parts = stripped[len(MARKER):].split(' ')
            if len(parts) != 4 or not parts[3].startswith('sha256:'):
                raise ValueError(f'line {i + 1}: malformed generated-region marker')
            j = i + 1
            while j < len(lines) and lines[j].strip() != END:
                if lines[j].strip().startswith(MARKER.strip() + ' '):
                    raise ValueError(f'line {j + 1}: generated region opened inside another')
                j += 1
            if j == len(lines):
                raise ValueError(f'line {i + 1}: generated region has no {END}')
            found.append((i + 1, parts[0], parts[1], parts[2], parts[3][len('sha256:'):], ''.join(lines[i + 1:j])))
            i = j
        i += 1
    return found


def tracked_d_files():
    out = subprocess.run(['git', 'ls-files', '-z', '*.d'], cwd=ROOT, capture_output=True, check=True).stdout
    return [ROOT / p for p in out.decode().split('\0') if p]


def check_digests(files):
    failures, found = [], []
    for path in files:
        text = path.read_text(encoding='utf-8', errors='replace')
        if MARKER.strip() not in text:
            continue
        rel = path.relative_to(ROOT)
        try:
            for line, version, upstream, type_id, digest, body in regions(text):
                found.append((rel, line, version, upstream, type_id, body))
                actual = hashlib.sha256(digest_text(body).encode()).hexdigest()
                if actual != digest:
                    failures.append(f'{rel}:{line}: generated region for {type_id} was edited outside its '
                                    'port:body regions; change the porter rule or the port plan and regenerate')
        except ValueError as problem:
            failures.append(f'{rel}: {problem}')
    return found, failures


def check_placeholders(files):
    """Every `// port:body` region still holding its placeholder: none may land on main."""
    failures = []
    for path in files:
        text = path.read_text(encoding='utf-8', errors='replace')
        if BODY.strip() not in text:
            continue
        for element in skeletons.placeholders(text):
            failures.append(f'{path.relative_to(ROOT)}: the port:body region of {element} still holds its '
                            'placeholder; write the body, or emit with --strip-pending to leave the member out')
    return failures


# ---- the corpus ----

def load_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def corpus(only=None):
    """Every public top-level type whose exact type row is ported or adapted with a D symbol by hand: a row with
    porter provenance (`generated`) is the porter's own output, not evidence it reproduces a lane."""
    pins = {(u['project'], u['version']): u for u in load_json(ROOT / 'api' / 'upstreams.json')['upstreams']}
    classifiers = {p.parent.name: Classifier(load_json(p)['elements']) for p in (ROOT / 'api').glob('*/mapping.json')}
    jobs = []
    for path in sorted((ROOT / 'api' / 'upstream').glob('*.json')):
        manifest = load_json(path)
        pin = pins.get((manifest['project'], manifest['version']))
        if pin is None or pin.get('repo') not in classifiers or pin.get('signatures_only'):
            continue
        classifier = classifiers[pin['repo']]
        for t in manifest['types']:
            if t.get('visibility') != 'public' or t['kind'] == 'record' or (only and t['id'] not in only):
                continue
            found = classifier.classify(t['id'])
            if not found or found[0] != t['id'] or found[1]['status'] not in ('ported', 'adapted') \
                    or found[1].get('generated'):
                continue
            symbol = found[1].get('d')
            if not symbol or '.' not in symbol:
                continue
            rows = 1
            for member in t.get('members', ()):
                hit = classifier.classify(t['id'] + '#' + member.get('signature', member['name']))
                rows += bool(hit and hit[1]['status'] in ('ported', 'adapted'))
            jobs.append({'project': manifest['project'], 'tag': manifest['version'], 'type': t['id'],
                         'kind': t['kind'], 'module': symbol.rsplit('.', 1)[0], 'symbol': symbol, 'rows': rows})
    return jobs


def port(flint, helper, cache, job, env=None, replace=False):
    args = [str(flint), 'port-spring', '--project', job['project'], '--tag', job['tag'], '--type', job['type'],
            '--module', job['module'], '--cache', str(cache), '--helper', str(helper), '--json']
    if replace:
        args.append('--replace-ported')
    # flint's GC static-data audit aborts about one run in a thousand here (reported to data-access, 2026-11-27);
    # keeping the static roots untrimmed is the remedy gc.md section 3c gives, and it doesn't change the output.
    env = dict(env or os.environ, FLINT_GC_STATIC_TRIM='0')
    result = subprocess.run(args, cwd=ROOT, capture_output=True, env=env, check=False)
    if not result.stdout.strip():
        raise EnvironmentProblem(f'port-spring exited {result.returncode} with no JSON for {job["type"]}: '
                                 + result.stderr.decode(errors='replace')[-600:])
    return result.stdout


def parse_port(stdout):
    try:
        output = json.loads(stdout)
    except ValueError as problem:
        raise EnvironmentProblem(f'port-spring did not reply with JSON: {stdout[:200]!r}') from problem
    if output.get('ok'):
        return output, None
    message = output['diagnostics'][0]['message'] if output.get('diagnostics') else 'no diagnostic'
    if 'checksum stamp' in message or 'cannot run' in message:
        raise EnvironmentProblem(message)
    return output, message


def port_all(flint, helper, cache, jobs, env, workers):
    with concurrent.futures.ThreadPoolExecutor(workers) as pool:
        return dict(zip((j['type'] for j in jobs),
                        pool.map(lambda j: port(flint, helper, cache, j, env), jobs)))


def normalise(message):
    message = re.sub(r'^\S+\.java: ', '', message)
    message = re.sub(r'^[\w.$]+: ', '', message)
    message = re.sub(r'mapping conflict at .*', 'mapping conflict', message)
    return re.sub(r'(: [^:]{40,})$', '', message)[:120]


# ---- splicing a generated declaration into the hand module ----

SCAN = re.compile(r'''//[^\n]*|/\*.*?\*/|"(?:[^"\\]|\\.)*"|`[^`]*`|r"[^"]*"|'(?:[^'\\]|\\.)*'|[A-Za-z_]\w*|\S''',
                  re.S)


def scan(source):
    """(text, offset) for the identifiers and punctuation outside comments; literals stay one token."""
    tokens, i, n = [], 0, len(source)
    while i < n:
        if source.startswith('/+', i):
            depth, i = 1, i + 2
            while i < n and depth:
                if source.startswith('/+', i):
                    depth, i = depth + 1, i + 2
                elif source.startswith('+/', i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            continue
        if source[i].isspace():
            i += 1
            continue
        match = SCAN.match(source, i)
        text = match.group()
        if not (text.startswith('//') or text.startswith('/*')):
            tokens.append((text, i))
        i = match.end()
    return tokens


def line_start(source, offset):
    return source.rfind('\n', 0, offset) + 1


def matching(tokens, index):
    pairs = {'{': '}', '(': ')', '[': ']'}
    opening, depth = tokens[index][0], 0
    for j in range(index, len(tokens)):
        if tokens[j][0] == opening:
            depth += 1
        elif tokens[j][0] == pairs[opening]:
            depth -= 1
            if depth == 0:
                return j
    raise ValueError('unbalanced ' + opening)


def declarations(source):
    """{name: (start, end)} for the declarations at brace depth 0, with leading attribute lines."""
    tokens, found, depth, i = scan(source), {}, 0, 0
    while i < len(tokens):
        text = tokens[i][0]
        if text == '{':
            depth += 1
        elif text == '}':
            depth -= 1
        elif depth == 0 and text in KEYWORDS and i + 1 < len(tokens) and re.match(r'[A-Za-z_]\w*$', tokens[i + 1][0]):
            k = i + 2
            while k < len(tokens) and tokens[k][0] not in ('{', ';'):
                k = matching(tokens, k) + 1 if tokens[k][0] in '([' else k + 1
            if k < len(tokens):
                end = matching(tokens, k) if tokens[k][0] == '{' else k
                found.setdefault(tokens[i + 1][0], (attribute_start(source, tokens[i][1]), tokens[end][1] + 1))
                i = end + 1
                continue
        elif (depth == 0 and text == '(' and i > 1 and re.match(r'[A-Za-z_]\w*$', tokens[i - 1][0])
              and re.match(r'[A-Za-z_]\w*$|[\])*]$', tokens[i - 2][0]) and tokens[i - 2][0] not in ('import', 'module')):
            close = matching(tokens, i)
            k = close + 1
            while k < len(tokens) and tokens[k][0] not in ('{', ';'):
                k = matching(tokens, k) + 1 if tokens[k][0] in '([' else k + 1
            if k < len(tokens) and tokens[k][0] == '{':
                end = matching(tokens, k)
                found.setdefault(tokens[i - 1][0], (attribute_start(source, tokens[i - 1][1]), tokens[end][1] + 1))
                i = end + 1
                continue
        i += 1
    return found


ATTRIBUTE_LINE = re.compile(r'\s*(?:(?:@[\w.]+(?:\(.*\))?|deprecated(?:\(.*\))?|final|abstract|static|extern\(\w+\))\s*)+$')


def attribute_start(source, offset):
    start = line_start(source, offset)
    while start > 0:
        previous = line_start(source, start - 1)
        if not ATTRIBUTE_LINE.fullmatch(source[previous:start - 1]):
            break
        start = previous
    return start


def generated_body(port_source):
    found = regions(port_source)
    if len(found) != 1:
        raise ValueError('port-spring output has no single generated region')
    return found[0][5]


def splice_one(hand, name, text):
    """The hand module with its top-level declaration `name` replaced by `text`."""
    existing = declarations(hand)
    if name not in existing:
        raise ValueError(f'the hand module declares no top-level {name}')
    start, end = existing[name]
    return hand[:start] + text + hand[end:]


# ---- the D side: roots, modules, the describe probe and package tests ----

def sub_packages():
    text = (ROOT / 'dub.sdl').read_text(encoding='utf-8')
    return [ROOT / d for d in re.findall(r'^subPackage "([^"]+)"', text, re.M)]


def import_roots():
    return [p / 'source' for p in sub_packages() if (p / 'source').is_dir()]


def module_index(roots):
    """{module: [(root, path), ...]}: two packages may declare the same module (Boot's legacy flint.boot)."""
    index = collections.defaultdict(list)
    for root in roots:
        for path in sorted(root.rglob('*.d')):
            head = path.read_text(encoding='utf-8', errors='replace')[:8192]
            match = re.search(r'^\s*module\s+([\w.]+)\s*;', head, re.M)
            if match:
                index[match.group(1)].append((root, path))
    return index


IMPORT_PATHS = {}


def import_paths(package):
    """The package's import paths in DUB's order, so a duplicated module resolves as the package's build does."""
    if package not in IMPORT_PATHS:
        result = subprocess.run(['dub', 'describe', ':' + package, '--import-paths'], cwd=ROOT, capture_output=True,
                                text=True, env=compiler_env(), check=False)
        paths = [Path(line.strip()) for line in result.stdout.splitlines() if line.strip().startswith('/')]
        if result.returncode or not paths:
            raise EnvironmentProblem(f'dub describe :{package} failed: {result.stderr.strip()[-400:]}')
        IMPORT_PATHS[package] = paths
    return IMPORT_PATHS[package]


def compiler_env():
    env = dict(os.environ, FLINT_DMD_SERVER='0')
    env.pop('FLINT_DMD_SERVER_PRELUDE', None)
    env.pop('DFLAGS', None)
    return env


def describe(compiler, overlay, roots, symbols, scratch):
    """{symbol: description} from one probe compile, or raise with the compiler's diagnostics."""
    probe = scratch / f'porter_probe_{compiler}.d'
    lines = ['module porter_probe;', 'import porter_describe : describe;']
    for module in sorted({s.rsplit('.', 1)[0] for s in symbols}):
        lines.append(f'static import {module};')
    for symbol in symbols:
        lines.append(f'pragma(msg, "PORTER-BEGIN {symbol}\\n" ~ describe!({symbol}) ~ "PORTER-END");')
    probe.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    includes = ([f'-I{overlay}'] if overlay else []) + [f'-I{r}' for r in roots] + [f'-I{DESCRIBER}']
    result = subprocess.run([compiler, '-o-', '-d', '-preview=dip1000', *includes, str(probe)], cwd=scratch,
                            capture_output=True, text=True, env=compiler_env(), check=False)
    if result.returncode:
        raise ValueError(result.stderr.strip()[-1500:])
    found = dict(re.findall(r'PORTER-BEGIN (\S+)\n(.*?)PORTER-END', result.stderr + result.stdout, re.S))
    missing = [s for s in symbols if s not in found]
    if missing:
        raise ValueError('probe printed no description for ' + ', '.join(missing))
    return found


def locate(roots, symbols, scratch):
    """{symbol: declaring module}: a mapped symbol may name a package module that only re-exports it."""
    def probe(batch):
        path = scratch / 'porter_locate.d'
        lines = ['module porter_locate;', 'import std.traits : moduleName;']
        lines += [f'static import {m};' for m in sorted({s.rsplit('.', 1)[0] for s in batch})]
        lines += [f'pragma(msg, "PORTER-LOCATE {s} " ~ moduleName!({s}));' for s in batch]
        path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        result = subprocess.run(['dmd', '-o-', '-d', '-preview=dip1000', *(f'-I{r}' for r in roots), f'-I{DESCRIBER}',
                                 str(path)],
                                cwd=scratch, capture_output=True, text=True, env=compiler_env(), check=False)
        return result.returncode == 0, dict(re.findall(r'PORTER-LOCATE (\S+) (\S+)', result.stderr + result.stdout))
    ok, found = probe(symbols)
    if not ok:
        found = {}
        for symbol in symbols:
            found.update(probe([symbol])[1])
    return found


def first_difference(left, right):
    a, b = left.splitlines(), right.splitlines()
    for x, y in zip(a, b):
        if x != y:
            return f'hand `{x}` / generated `{y}`'
    return f'hand has {len(a)} lines, generated {len(b)}'


def hardlink_tree(destination):
    out = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True, check=True).stdout
    for rel in out.decode().split('\0'):
        if not rel:
            continue
        source, target = ROOT / rel, destination / rel
        if source.is_symlink() or not source.is_file():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        os.link(source, target)
    native = ROOT / '.native'
    if native.exists():
        os.symlink(native.resolve(), destination / '.native')


def package_of(path):
    best = None
    for directory in sub_packages():
        try:
            path.relative_to(directory)
        except ValueError:
            continue
        if best is None or len(directory.parts) > len(best.parts):
            best = directory
    if best is None:
        return None
    match = re.search(r'^name "([^"]+)"', (best / 'dub.sdl').read_text(encoding='utf-8'), re.M) \
        if (best / 'dub.sdl').is_file() else None
    return match.group(1) if match else best.name


def run_package_tests(tree, package, compiler):
    env = compiler_env()
    env['DUB_HOME'] = str(tree / '.dub-home' / compiler)
    result = subprocess.run(['dub', 'test', ':' + package, '--compiler=' + compiler, '--build=unittest', '--force'],
                            cwd=tree, capture_output=True, text=True, env=env, check=False)
    return result.returncode == 0, (result.stdout + result.stderr)[-1500:]


# ---- the gate ----

def check_tools(flint, helper, cache):
    for label, path in (('flint', flint), ('the port-spring helper', helper)):
        if not Path(path).is_file():
            raise EnvironmentProblem(f'{label} is missing at {path}; see tools/port-spring/README.md')
    if not Path(cache).is_dir():
        raise EnvironmentProblem(f'the pinned source cache {cache} is missing; run flint api fetch --cache {cache}')
    for compiler in COMPILERS + ('dub',):
        if shutil.which(compiler) is None:
            raise EnvironmentProblem(f'{compiler} is not on PATH')


def determinism(flint, helper, cache, jobs, workers, first):
    """Byte differences between the first run and one under another locale, time zone and job order."""
    env = dict(os.environ, TZ='Pacific/Chatham', LANG='tr_TR.UTF-8', LC_ALL='tr_TR.UTF-8')
    second = port_all(flint, helper, cache, list(reversed(jobs)), env, workers)
    return [f'{t}: port-spring output differs between two runs' for t in first if first[t] != second.get(t)]


def regenerate(flint, helper, cache, found, index_by_path):
    failures = []
    for rel, line, version, upstream, type_id, body in found:
        project, _, tag = upstream.partition('@')
        # The type row's module first: a package module may re-export the file that holds the region.
        module = index_by_path.get(type_id) or index_by_path.get(ROOT / rel)
        if module is None:
            failures.append(f'{rel}:{line}: no module declaration to regenerate {type_id} into')
            continue
        output, problem = parse_port(port(flint, helper, cache, {'project': project, 'tag': tag, 'type': type_id,
                                                                  'module': module}, replace=True))
        if problem:
            failures.append(f'{rel}:{line}: {type_id} no longer ports: {problem}')
            continue
        regenerated = regions(output['source'])
        if (len(regenerated) != 1 or regenerated[0][1] != version
                or digest_text(regenerated[0][5]) != digest_text(body)):
            failures.append(f'{rel}:{line}: regenerating {type_id} with {output["porter"]} differs from the '
                            'committed region; regenerate it in the same commit as the porter change')
    return failures


def reproduce(jobs, outputs, flint, helper, cache, tests, scratch):
    """Per job: reproduced, rejected (with reason) or diverged (with kind and reason)."""
    results = {}
    accepted = {}
    for job in jobs:
        output, problem = parse_port(outputs[job['type']])
        if problem and 'mapping conflict' in problem:
            replaced, again = parse_port(port(flint, helper, cache, job, replace=True))
            if again:
                results[job['type']] = {'result': 'rejected', 'reason': normalise(again)}
                continue
            accepted[job['type']] = replaced
            results[job['type']] = {'result': 'diverged', 'shape': replaced['shape'], 'kind': 'mapping',
                                    'reason': re.sub(r'^.*?mapping conflict', 'mapping conflict', problem)[:400]}
            continue
        if problem:
            results[job['type']] = {'result': 'rejected', 'reason': normalise(problem)}
            continue
        accepted[job['type']] = output
        extra = json.loads(output['mapping'])['elements']
        if extra:
            results[job['type']] = {'result': 'diverged', 'shape': output['shape'], 'kind': 'mapping',
                                    'reason': 'proposes rows the hand port leaves deferred: ' + ', '.join(sorted(extra))[:300]}
        else:
            results[job['type']] = {'result': 'reproduced', 'shape': output['shape']}

    index = module_index(import_roots())
    packages = collections.defaultdict(list)
    names = {}
    for job in jobs:
        if job['type'] not in accepted:
            continue
        try:
            body = generated_body(accepted[job['type']]['source'])
            names[job['type']] = {name: body[start:end] for name, (start, end) in declarations(body).items()}
        except ValueError as problem:
            diverge(results, job, 'api', f'unreadable generated region: {problem}')
            continue
        owners = [package_of(path) for _, path in index.get(job['module'], ())]
        if not owners or None in owners:
            diverge(results, job, 'api', f'no registered package declares the hand module {job["module"]}')
            continue
        packages[owners[0]].append(job)
    spliced_files = {}
    for package, group in sorted(packages.items()):
        roots = import_paths(package)
        symbols = {job['type']: [job['module'] + '.' + n for n in names[job['type']]] for job in group}
        declaring = locate(roots, sorted({s for every in symbols.values() for s in every}), scratch)
        edits = collections.defaultdict(list)
        for job in group:
            missing = [s for s in symbols[job['type']] if s not in declaring]
            if missing:
                diverge(results, job, 'api', 'the hand port declares no ' + ', '.join(missing))
                continue
            for symbol in symbols[job['type']]:
                files = [(r, p) for r, p in index.get(declaring[symbol], ()) if r in roots]
                edits[files[0] if files else None].append((job, symbol.rsplit('.', 1)[1]))
        overlay = scratch / 'overlay' / package
        compared = []
        for target, changes in edits.items():
            if target is None:
                for job, _ in changes:
                    diverge(results, job, 'api', 'the declaring module is outside the package\'s import paths')
                continue
            root, path = target
            text = path.read_text(encoding='utf-8')
            for job, name in changes:
                try:
                    text = splice_one(text, name, names[job['type']][name])
                except ValueError as problem:
                    diverge(results, job, 'api', f'cannot splice into {path.relative_to(ROOT)}: {problem}')
            destination = overlay / path.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text, encoding='utf-8')
            spliced_files[path] = (text, [job for job, _ in changes])
            compared += [job for job, _ in changes if results[job['type']]['result'] != 'rejected']
        group = [job for job in group if job in compared]
        every = sorted({s for job in group for s in symbols[job['type']]})
        if not every:
            continue
        for compiler in COMPILERS:
            try:
                hand = describe(compiler, None, roots, every, scratch)
            except ValueError as problem:
                raise EnvironmentProblem(f':{package} does not compile on {compiler} without any splice: {problem}')
            try:
                generated = describe(compiler, overlay, roots, every, scratch)
            except ValueError as problem:
                for job in group:
                    diverge(results, job, 'api', f'{compiler}: the spliced :{package} does not compile: {problem[:600]}')
                continue
            for job in group:
                for symbol in symbols[job['type']]:
                    if hand[symbol] != generated[symbol]:
                        diverge(results, job, 'api', f'{compiler}: {symbol}: '
                                + first_difference(hand[symbol], generated[symbol]))
                        break
    if tests and spliced_files:
        run_tests(spliced_files, results, scratch)
    return results


def diverge(results, job, kind, reason):
    current = results[job['type']]
    if current['result'] == 'reproduced':
        results[job['type']] = {'result': 'diverged', 'shape': current['shape'], 'kind': kind, 'reason': reason}
    elif current['result'] == 'diverged' and kind not in current['kind'].split('+'):
        current['kind'] += '+' + kind
        current['reason'] += ' | ' + reason


# ':<package>/<compiler>' -> why: packages whose unit tests fail without any splice, so splices there go untested.
BLOCKED = {}


def run_tests(spliced_files, results, scratch):
    """The owning package's unit tests against the spliced tree; a failure counts only if main passes them."""
    tree = scratch / 'spliced'
    hardlink_tree(tree)
    packages = collections.defaultdict(list)
    for path, (text, group) in spliced_files.items():
        target = tree / path.relative_to(ROOT)
        temporary = target.with_suffix('.porter-tmp')
        temporary.write_text(text, encoding='utf-8')
        os.replace(temporary, target)
        package = package_of(path)
        packages[package].extend(group)
    pristine = None
    for package, group in sorted(packages.items(), key=lambda item: str(item[0])):
        if package is None:
            for job in group:
                diverge(results, job, 'tests', 'no dub sub-package owns the hand module')
            continue
        for compiler in COMPILERS:
            ok, log = run_package_tests(tree, package, compiler)
            if ok:
                continue
            if pristine is None:
                pristine = scratch / 'pristine'
                hardlink_tree(pristine)
            base_ok, base_log = run_package_tests(pristine, package, compiler)
            if not base_ok:
                # The splice can't be judged; the gate still fails, naming the package's own failure.
                for job in group:
                    current = results[job['type']]
                    current['blocked'] = f':{package} unit tests fail on {compiler} without any splice'
                BLOCKED[f':{package}/{compiler}'] = (f'{len(group)} spliced type(s) uncertified: '
                                                     + base_log.strip().splitlines()[-1][-200:])
                break
            for job in group:
                diverge(results, job, 'tests', f':{package} unit tests fail on {compiler}: {log[-300:]}')


def summarise(jobs, results):
    kinds = collections.defaultdict(lambda: collections.Counter())
    shapes = collections.defaultdict(lambda: collections.Counter())
    rejections = collections.defaultdict(collections.Counter)
    for job in jobs:
        r = results[job['type']]
        kinds[job['kind']]['hand_ported'] += 1
        kinds[job['kind']]['hand_ported_elements'] += job['rows']
        if r['result'] == 'rejected':
            rejections[job['kind']][r['reason']] += 1
            continue
        kinds[job['kind']]['accepted'] += 1
        shapes[r['shape']]['accepted'] += 1
        if r['result'] == 'reproduced':
            kinds[job['kind']]['reproduced'] += 1
            kinds[job['kind']]['reproduced_elements'] += job['rows']
            shapes[r['shape']]['reproduced'] += 1
            shapes[r['shape']]['reproduced_elements'] += job['rows']
        else:
            shapes[r['shape']]['diverged'] += 1
    def rated(counter, denominator):
        out = dict(sorted(counter.items()))
        out['rate'] = round(counter['reproduced'] / counter[denominator], 4) if counter[denominator] else 0.0
        return out
    return {'kinds': {k: rated(v, 'hand_ported') for k, v in sorted(kinds.items())},
            'shapes': {k: rated(v, 'accepted') for k, v in sorted(shapes.items())},
            'rejections': {k: dict(v.most_common()) for k, v in sorted(rejections.items())}}


def configuration_properties(helper, cache, summary, report):
    """The Java Beans shape against boot's hand spec: (a) twice in opposite orders, and (b) per field."""
    first = beans.compare(str(helper), str(cache))
    second = beans.compare(str(helper), str(cache), reverse=True)
    failures = []
    if json.dumps(first, sort_keys=True) != json.dumps(second, sort_keys=True):
        failures.append('configuration properties: the derivation differs between two runs')
    totals = first['totals']
    hand = totals['fields'] + totals['unsupported'] + totals['handOnly']
    summary['shapes']['configuration-properties-field'] = {
        'accepted': hand, 'reproduced': totals['exact'], 'diverged': totals['fields'] - totals['exact'],
        'rate': round(totals['exact'] / hand, 4) if hand else 0.0}
    report['configurationProperties'] = first
    report['configurationPropertiesYield'] = beans.yield_report(str(helper), str(cache))['totals']
    return failures


def accessor_shape(helper, cache, summary, report, scratch):
    """The R6 accessor shape per element (tools/port-spring/accessors.py): derived twice, in opposite orders, and
    compared with the hand members on DMD and LDC. Returns {element: result}."""
    universe = accessors.Universe(cache)
    items, results, derived, skipped = accessors.compare(universe, helper, scratch)
    failures = []
    again = {}
    for item in reversed(items):
        try:
            again[item['element']] = accessors.derive(item, universe)
        except accessors.Unsupported as problem:
            again[item['element']] = str(problem)
    for item in items:
        first = derived.get(item['element'], results.get(item['element'], {}).get('reason'))
        if item['element'] in derived and again[item['element']] != first:
            failures.append(f'{item["element"]}: the accessor derivation differs between two runs')
    accessor_summary = accessors.summarise(items, results, skipped)
    totals = accessor_summary['totals']
    accepted = totals.get('reproduced', 0) + totals.get('diverged', 0)
    summary['shapes']['r6-accessor'] = {'elements': totals.get('elements', 0), 'accepted': accepted,
                                        'reproduced': totals.get('reproduced', 0),
                                        'diverged': totals.get('diverged', 0),
                                        'rate': round(totals.get('reproduced', 0) / accepted, 4) if accepted else 0.0}
    report['accessors'] = {**accessor_summary, 'results': dict(sorted(results.items()))}
    return results, failures


def bean_shape(helper, cache, summary, report, scratch, tests):
    """The pure-bean whole-type shape (tools/port-spring/bean_types.py): derived, derived again in opposite order
    from the same D base facts, spliced and compared on DMD and LDC, with package tests. Returns {type: result}."""
    universe = accessors.Universe(cache)
    items, results, derived, _ = bean_types.compare(universe, helper, scratch, tests=tests)
    failures = []
    for item in reversed(items):
        if item['type'] in derived:
            again = bean_types.derive(item, universe, *derived[item['type']]['inputs'])
            if again['text'] != derived[item['type']]['text'] or again['rows'] != derived[item['type']]['rows']:
                failures.append(f'{item["type"]}: the pure-bean derivation differs between two runs')
    bean_summary = bean_types.summarise(items, results, {})
    totals = bean_summary['totals']
    accepted = totals.get('reproduced', 0) + totals.get('diverged', 0)
    summary['shapes']['bean-class'] = {'classes': totals.get('classes', 0), 'accepted': accepted,
                                       'reproduced': totals.get('reproduced', 0),
                                       'diverged': totals.get('diverged', 0),
                                       'rate': round(totals.get('reproduced', 0) / accepted, 4) if accepted else 0.0}
    report['beanTypes'] = {**bean_summary, 'results': dict(sorted(results.items()))}
    return results, failures


def skeleton_shape(helper, cache, summary, report, scratch):
    """Skeleton mode (tools/port-spring/skeletons.py): every hand-ported class and interface declared, derived again
    in opposite order from the same D facts, spliced and compared per member on DMD and LDC. Returns {type id:
    {'elements': divergent element count, 'reason'}} for the types with divergent elements."""
    universe = accessors.Universe(cache)
    items, types, elements, derived, skipped = skeletons.compare(universe, helper, scratch)
    failures = []
    for item in reversed(items):
        d = derived.get(item['type'])
        if d is not None:
            again = skeletons.derive(item, universe, *d['inputs'])
            if again['text'] != d['text'] or again['rows'] != d['rows']:
                failures.append(f'{item["type"]}: the skeleton differs between two runs')
    skeleton_summary = skeletons.summarise(items, types, elements, skipped)
    counts = skeleton_summary['elements']
    declared = counts.get('reproduced', 0) + counts.get('diverged', 0)
    summary['shapes']['skeleton'] = {'types': len(items), 'typesReproduced': skeleton_summary['types'].get('reproduced', 0),
                                     'declared': declared, 'reproduced': counts.get('reproduced', 0),
                                     'diverged': counts.get('diverged', 0), 'pending': counts.get('pending', 0),
                                     'rate': round(counts.get('reproduced', 0) / declared, 4) if declared else 0.0}
    report['skeletons'] = {**skeleton_summary, 'results': {'types': dict(sorted(types.items())),
                                                           'elements': dict(sorted(elements.items()))}}
    by_type = {}
    for element, r in sorted(elements.items()):
        if r['result'] == 'diverged':
            type_id = element.split('#', 1)[0]
            entry = by_type.setdefault(type_id, {'elements': 0, 'reason': f'{element}: {r["kind"]}: {r["reason"][:200]}'})
            entry['elements'] += 1
    return by_type, failures


def compare_skeletons(baseline, by_type):
    failures = []
    listed = baseline.get('skeletonDivergences', {})
    for type_id, entry in sorted(by_type.items()):
        allowed = listed.get(type_id, {}).get('elements', 0)
        if entry['elements'] > allowed:
            failures.append(f'{type_id}: {entry["elements"]} divergent skeleton elements, {allowed} listed; first '
                            + entry['reason'])
    for type_id, entry in sorted(listed.items()):
        if by_type.get(type_id, {}).get('elements', 0) < entry['elements']:
            failures.append(f'{type_id}: fewer divergent skeleton elements than listed; lower the count with '
                            '--write-baseline (the list only shrinks)')
    return failures


def skeleton_divergences(baseline, by_type, seed):
    known = baseline.get('skeletonDivergences')
    out = {}
    for type_id, entry in sorted((by_type or {}).items()):
        allowed = (known or {}).get(type_id, {}).get('elements', 0)
        if known is not None and entry['elements'] > allowed and not seed:
            raise EnvironmentProblem(f'{type_id} has {entry["elements"]} divergent skeleton elements, {allowed} '
                                     'listed; fix the rule or the port plan')
        previous = (known or {}).get(type_id)
        out[type_id] = {'elements': entry['elements'],
                        'reason': previous['reason'] if previous else 'triage: ' + entry['reason']}
    return out


def compare_accessors(baseline, results, key='accessorDivergences', what='accessor'):
    failures = []
    listed = baseline.get(key, {})
    for element, r in sorted(results.items()):
        if r['result'] == 'diverged' and element not in listed:
            failures.append(f'{element}: new {r["kind"]} {what} divergence: {r["reason"][:300]}')
    for element in sorted(listed):
        if element in results and results[element]['result'] != 'diverged':
            failures.append(f'{element}: listed under {key} but now {results[element]["result"]}; '
                            'remove it (the list only shrinks)')
    return failures


def compare_baseline(baseline, results, summary):
    failures = []
    listed = baseline.get('divergences', {})
    for type_id, r in sorted(results.items()):
        if r['result'] == 'diverged' and type_id not in listed:
            failures.append(f'{type_id}: new {r["kind"]} divergence ({r["shape"]}): {r["reason"][:300]}')
    for type_id in sorted(listed):
        if type_id in results and results[type_id]['result'] != 'diverged':
            failures.append(f'{type_id}: listed in api/porter-baseline.json but now {results[type_id]["result"]}; '
                            'remove it (the list only shrinks)')
    known = baseline.get('blocked', {})
    for key, why in sorted(BLOCKED.items()):
        if key not in known:
            failures.append(f'{key} unit tests fail without any splice ({why}); fix them, or list the package in '
                            'api/porter-baseline.json "blocked" with the reason')
    for key in sorted(known):
        if key not in BLOCKED:
            failures.append(f'{key} is listed as blocked but its tests now run; remove it (the list only shrinks)')
    for shape, floor in sorted(baseline.get('reproduced', {}).items()):
        count = summary['shapes'].get(shape, {}).get('reproduced', 0)
        if count < floor:
            failures.append(f'{shape}: {count} reproduced, below the baseline floor of {floor}')
    return failures


def per_element_divergences(baseline, key, results, seed):
    known = baseline.get(key)
    out = {}
    for element, r in sorted((results or {}).items()):
        if r['result'] != 'diverged':
            continue
        # A list's first baseline seeds itself; after that a new divergence is refused like any other.
        if known is not None and element not in known and not seed:
            raise EnvironmentProblem(f'{element} is a new {key} entry; fix the rule or the port plan')
        out[element] = (known or {}).get(element) or {'kind': r['kind'], 'reason': 'triage: ' + r['reason'][:300]}
    return out


def write_baseline(baseline, results, summary, seed, accessor_results=None, bean_results=None, skeleton_types=None):
    listed = baseline.get('divergences', {})
    divergences = {}
    for type_id, r in sorted(results.items()):
        if r['result'] != 'diverged':
            continue
        if type_id not in listed and not seed:
            raise EnvironmentProblem(f'{type_id} is a new divergence; fix it, or seed the first baseline with --seed')
        divergences[type_id] = listed.get(type_id) or {'kind': r['kind'], 'reason': 'triage: ' + r['reason'][:300]}
    known = baseline.get('blocked', {})
    blocked = {}
    for key, why in sorted(BLOCKED.items()):
        if key not in known and not seed:
            raise EnvironmentProblem(f'{key} is newly blocked; fix its tests, or seed the first baseline with --seed')
        blocked[key] = known.get(key) or 'triage: ' + why
    floors = dict(baseline.get('reproduced', {}))
    for shape, counts in summary['shapes'].items():
        floors[shape] = max(floors.get(shape, 0), counts.get('reproduced', 0))
    document = {'schema': 'flint.porter-baseline/1',
                'about': 'Shrink-only list of accepted-but-divergent porter outputs, and the reproduced count per '
                         'shape, which only grows. tools/porter_gate.py; docs/spring/phase2/porter-plan.md.',
                'reproduced': dict(sorted(floors.items())), 'blocked': blocked, 'divergences': divergences,
                'accessorDivergences': per_element_divergences(baseline, 'accessorDivergences', accessor_results, seed),
                'beanDivergences': per_element_divergences(baseline, 'beanDivergences', bean_results, seed),
                'skeletonDivergences': skeleton_divergences(baseline, skeleton_types, seed)}
    BASELINE.write_text(json.dumps(document, indent=1, sort_keys=False) + '\n', encoding='utf-8')


def gate(args):
    flint, helper, cache = args.flint.resolve(), args.helper.resolve(), args.cache.resolve()
    files = tracked_d_files()
    found, failures = check_digests(files)
    failures += check_placeholders(files)
    report = {'regions': len(found)}
    if args.digests_only:
        return report, failures
    check_tools(flint, helper, cache)
    jobs = corpus(set(args.only) if args.only else None)
    if not jobs:
        raise EnvironmentProblem('the corpus is empty')
    first = port_all(flint, helper, cache, jobs, None, args.jobs)
    failures += determinism(flint, helper, cache, jobs, args.jobs, first)
    with tempfile.TemporaryDirectory(prefix='flint-porter-gate-') as directory:
        scratch = Path(directory)
        index = module_index(import_roots())
        modules = {path: module for module, places in index.items() for _, path in places}
        modules.update({job['type']: job['module'] for job in corpus()})
        failures += regenerate(flint, helper, cache, [f for f in found if not f[2].startswith('port-skeleton/')],
                               modules)
        skeleton_regions = [f for f in found if f[2].startswith('port-skeleton/')]
        if skeleton_regions:
            (scratch / 'regenerate').mkdir()
            failures += skeletons.regenerate(accessors.Universe(cache), helper, skeleton_regions, scratch / 'regenerate')
        results = reproduce(jobs, first, flint, helper, cache, not args.no_tests, scratch)
        report['blocked'] = dict(BLOCKED)
        summary = summarise(jobs, results)
        accessor_results, bean_results, skeleton_types = {}, {}, {}
        if not args.only:
            accessor_scratch = scratch / 'accessors'
            accessor_scratch.mkdir()
            accessor_results, accessor_failures = accessor_shape(helper, cache, summary, report, accessor_scratch)
            failures += accessor_failures
            bean_scratch = scratch / 'beans'
            bean_scratch.mkdir()
            bean_results, bean_failures = bean_shape(helper, cache, summary, report, bean_scratch,
                                                     not args.no_tests)
            failures += bean_failures
            skeleton_scratch = scratch / 'skeletons'
            skeleton_scratch.mkdir()
            skeleton_types, skeleton_failures = skeleton_shape(helper, cache, summary, report, skeleton_scratch)
            failures += skeleton_failures
            report['blocked'] = dict(BLOCKED)
        if args.keep:
            shutil.copytree(scratch, args.keep, symlinks=True, dirs_exist_ok=True)
    failures += configuration_properties(helper, cache, summary, report)
    report.update(summary)
    report['tests'] = not args.no_tests
    baseline = load_json(BASELINE) if BASELINE.is_file() else {}
    if args.write_baseline:
        if args.only or args.no_tests:
            raise EnvironmentProblem('--write-baseline needs the whole corpus with tests')
        write_baseline(baseline, results, summary, args.seed, accessor_results, bean_results, skeleton_types)
        baseline = load_json(BASELINE)
    if not args.only:
        if baseline:
            failures += compare_baseline(baseline, results, summary)
            failures += compare_accessors(baseline, accessor_results)
            failures += compare_accessors(baseline, bean_results, 'beanDivergences', 'pure-bean')
            failures += compare_skeletons(baseline, skeleton_types)
        else:
            failures.append('api/porter-baseline.json is missing; seed it with --write-baseline --seed')
    report['results'] = results
    return report, failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--flint', type=Path, default=ROOT / '.flint' / 'bin' / 'flint')
    parser.add_argument('--helper', type=Path, default=ROOT / '.flint' / 'port-spring' / 'flint-port-spring')
    parser.add_argument('--cache', type=Path, default=ROOT / '.flint' / 'cache' / 'api')
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--no-tests', action='store_true', help='skip the package unit tests (not a gate pass)')
    parser.add_argument('--only', action='append', help='one Java type id; repeatable (no baseline comparison)')
    parser.add_argument('--digests-only', action='store_true', help='check only the generated-region digests')
    parser.add_argument('--write-baseline', action='store_true', help='rewrite api/porter-baseline.json: '
                        'drop fixed divergences and raise floors; new divergences are refused unless --seed')
    parser.add_argument('--seed', action='store_true')
    parser.add_argument('--keep', type=Path, help='copy the scratch tree (overlay, probes) here')
    parser.add_argument('--report', type=Path, default=ROOT / 'artifacts' / 'porter' / 'report.json')
    args = parser.parse_args(argv)
    try:
        report, failures = gate(args)
    except EnvironmentProblem as problem:
        print('PORTER GATE ERROR:', problem, file=sys.stderr)
        return 2
    report['failures'] = failures
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=1) + '\n', encoding='utf-8')
    brief = {k: v for k, v in report.items() if k not in ('results', 'rejections', 'configurationProperties',
                                                          'accessors', 'beanTypes', 'skeletons')}
    print(json.dumps(brief, indent=1))
    for failure in failures:
        print('PORTER GATE FAILED:', failure, file=sys.stderr)
    return 1 if failures or args.no_tests and not args.only and not args.digests_only else 0


if __name__ == '__main__':
    sys.exit(main())
