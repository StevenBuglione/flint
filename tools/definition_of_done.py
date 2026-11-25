#!/usr/bin/env python3
"""Per-module definition of done: one command a porter runs on a module directory.

    python3 tools/gates.py --module <dir> --definition-of-done [--json] [--step NAME]... [--apps auto|none|APP,...]
                           [--release] [--no-hold] [--flint PATH] [--write-upstream-tests]

Design: coordination/notes/definition-of-done.md (proof-harness, 2026-11-25; owner decision 087f28a3, the guardrails
for the autonomous Phase 2 porter). The steps, in order:

  resolve         the directory -> module name, kind, repo, roots, upstream and Java packages (policy entries)
  structural      gates.py --gate structural, scoped where the gate can be (--package for engine packages)
  api             flint api headers on the module's roots; flint api coverage, filtered to the module's Java packages
  quality         quality.py --path on the module's roots (dfmt, D-Scanner, complexity allowlist)
  tests           dub test :<name>, plus any test packages the upstream-tests record names, on DMD and LDC
  upstream-tests  <module dir>/upstream-tests.json (flint.upstream-tests/1): each ported class's D file and unittest
                  names exist, each exclusion or skip has a reason, and the upstream inventory is covered
  budgets         measure_builds --framework-sizes against the policy/framework.json budget (framework modules)
  apps            for each Spring app that uses the module: its allocation tests (flint test --verify), its golden
                  suite (spring_bench accept), and m7's `flint budget` once it exists

Each step reports pass, fail, skip (with its reason, and never counted as a pass) or error (the environment, not the
module). Every failure names what, where, the rule, and the command that reruns that step alone. Exit 0 when every
step passes or is skipped, 1 when the module fails a step, 2 for an environment error. The report is written to
artifacts/definition-of-done/<name>.json. The whole command runs under one `measure_queue.py hold`, so a measurement
window on venus pauses it; --no-hold is for other machines.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import tomllib
from dataclasses import asdict, dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / 'tools') not in sys.path:
    sys.path.insert(0, str(ROOT / 'tools'))
import workspace  # noqa: E402

STEPS = ('resolve', 'structural', 'api', 'quality', 'tests', 'upstream-tests', 'budgets', 'apps')
UPSTREAM_TESTS = 'upstream-tests.json'
SCHEMA = 'flint.upstream-tests/1'
REPORT_DIR = ROOT / 'artifacts' / 'definition-of-done'


@dataclass
class Module:
    name: str
    kind: str  # package | framework | boot
    repo: str
    directory: str
    roots: list
    java_packages: list
    upstream: str | None = None
    budget: dict = field(default_factory=dict)
    provisional: list = field(default_factory=list)
    upstream_modules: list = field(default_factory=list)  # e.g. spring-web: narrows ownership to them when known


@dataclass
class Result:
    step: str
    status: str  # pass | fail | skip | error
    messages: list = field(default_factory=list)
    rerun: str = ''
    seconds: float = 0.0
    details: dict = field(default_factory=dict)


def rerun(directory, step):
    return f'python3 tools/gates.py --module {directory} --definition-of-done --step {step}'


def tail(text, lines=15):
    return ['  ' + line.rstrip() for line in text.strip().splitlines()[-lines:]]


# ---------------------------------------------------------------------------------------------------------------
# Running commands


class Runner:
    """Runs a command from the repository root with the pinned toolchains on PATH, under `measure_queue.py hold`
    unless told not to. Returns (exit status, stdout, stderr)."""

    def __init__(self, hold=True, root=ROOT):
        self.hold = hold
        self.root = root

    def environment(self):
        env = dict(os.environ)
        env.pop('DFLAGS', None)
        env.setdefault('FLINT_HOME', str(self.root))
        # The checkout's own .tools, then the shared one a worktree's main checkout holds.
        shared = [self.root / '.tools'] + [p / '.tools' for p in self.root.parents if (p / '.tools' / 'dmd2').is_dir()][:1]
        extra = []
        for tools in shared:
            extra += [tools / 'dmd2' / 'linux' / 'bin64', tools / 'bin', *sorted(tools.glob('ldc2-*/bin'))]
        extra.append(self.root / '.flint' / 'bin')
        env['PATH'] = os.pathsep.join([str(p) for p in extra if p.is_dir()] + [env.get('PATH', '')])
        return env

    def __call__(self, argv, timeout=3600):
        command = ([sys.executable, str(self.root / 'tools' / 'measure_queue.py'), 'hold', '--'] if self.hold else [])
        try:
            done = subprocess.run(command + [str(a) for a in argv], cwd=self.root, env=self.environment(),
                                  capture_output=True, text=True, timeout=timeout)
        except FileNotFoundError as exc:
            return 127, '', str(exc)
        except subprocess.TimeoutExpired:
            return 124, '', f'timed out after {timeout} s'
        return done.returncode, done.stdout or '', done.stderr or ''


def missing_tool(code, text):
    return code == 127 or any(s in text for s in ('No such file or directory', 'command not found', 'not found on PATH'))


def json_document(text):
    """The JSON document a tool printed, even with log lines around it."""
    try:
        return json.loads(text)
    except ValueError:
        start, end = text.find('{'), text.rfind('}')
        if start < 0 or end < start:
            raise
        return json.loads(text[start:end + 1])


def find_key(document, key):
    if isinstance(document, dict):
        if key in document:
            return document[key]
        values = document.values()
    elif isinstance(document, list):
        values = document
    else:
        return None
    for value in values:
        found = find_key(value, key)
        if found is not None:
            return found
    return None


# ---------------------------------------------------------------------------------------------------------------
# Java packages: which module owns an upstream element


def java_package(element):
    """The Java package of a mapping id or test path: the dotted segments before the first type name."""
    package = []
    for segment in element.split('#', 1)[0].replace('/', '.').split('.'):
        if not segment or segment[0].isupper() or '*' in segment:
            break
        package.append(segment)
    return '.'.join(package)


_OWNERSHIP = {}
BOOT_PORT = re.compile(r'boot/(?:core|module)/flint-')


def ported_modules(root=ROOT):
    """{name: (kind, D modules, upstream, policy entry)} for every module that ports an upstream: the
    policy/framework.json modules, and the Spring Boot ports in policy/boot.json (boot/core/flint-*,
    boot/module/flint-*, Spring Boot's own layout; the flint.boot_* libraries are Flint's own)."""
    ported = {}
    for name, meta in json.loads((root / 'policy' / 'framework.json').read_text()).get('modules', {}).items():
        ported[name] = ('framework', [meta['module'], *meta.get('also', [])], meta.get('upstream'), meta)
    boot = root / 'policy' / 'boot.json'
    if boot.is_file():
        pins = json.loads((root / 'api' / 'upstreams.json').read_text())['upstreams']
        upstream = next((f"{u['project']}@{u['version']}" for u in pins if u['project'] == 'spring-boot'), None)
        for name, meta in json.loads(boot.read_text()).get('libraries', {}).items():
            if BOOT_PORT.match(meta.get('directory', '')) and meta.get('module'):
                ported[name] = ('boot', [meta['module'], *meta.get('also', [])], upstream, meta)
    return ported


def ownership(root=ROOT):
    """{Java package prefix: module}. A Spring port by rule R1 inverted (flint.X ports org.springframework.X), over
    `module` and `also`; every module also by the packages its mapped elements come from (`d` under one of its D
    modules), which covers ports of other libraries (Jackson, Jakarta, SLF4J). The longest prefix owns an element."""
    if root in _OWNERSHIP:
        return _OWNERSHIP[root]
    d_owner, table = {}, {}
    for name, (_, modules, upstream, _) in ported_modules(root).items():
        for d in modules:
            d_owner[d] = name
            if d.startswith('flint.') and str(upstream).startswith('spring-'):
                table.setdefault('org.springframework.' + d[len('flint.'):], name)
    for mapping in sorted((root / 'api').glob('*/mapping.json')):
        for element, entry in json.loads(mapping.read_text()).get('elements', {}).items():
            d = entry.get('d')
            if not d:
                continue
            best = max((m for m in d_owner if d == m or d.startswith(m + '.')), key=len, default=None)
            package = java_package(element)
            if best and package and not package.startswith('org.springframework.'):
                table.setdefault(package, d_owner[best])
    _OWNERSHIP[root] = table
    return table


def owner(element, table):
    package = java_package(element) or element
    best = max((p for p in table if package == p or package.startswith(p + '.')), key=len, default=None)
    return table.get(best)


# `Ported from <owner/project> <tag>, spring-web/src/main/java/...`: the upstream build module a file comes from.
PORTED_MODULE = re.compile(r'Ported from\s+(\S+)\s+\S+?[,:]\s+(?:[\w.-]+/)*?([\w.-]+)/src/(?:main|test)/java/')


def upstream_modules(module, root=ROOT):
    """The upstream build modules (spring-web, spring-jdbc) the module ports: the record's "upstream_modules", else
    those its files' `Ported from` headers name. Empty when unknown, which leaves ownership to packages alone; this is
    what keeps org.springframework.web.reactive (spring-webflux) out of web."""
    record = root / module.directory / UPSTREAM_TESTS
    if record.is_file():
        listed = json.loads(record.read_text()).get('upstream_modules')
        if listed:
            return sorted(listed)
    project = str(module.upstream).partition('@')[0]
    found = set()
    for path in module_files(module, root):
        found.update(built for source, built in PORTED_MODULE.findall(path.read_text(errors='replace'))
                     if source.rsplit('/', 1)[-1] == project)
    return sorted(found)


def type_modules(module, root=ROOT):
    """{type id: upstream build module} from the module's pinned API manifest (api/upstream/<project>-<version>.json)."""
    project, _, version = str(module.upstream).partition('@')
    manifest = root / 'api' / 'upstream' / f'{project}-{version}.json'
    if not manifest.is_file():
        return {}
    return {t['id']: t.get('module') for t in json.loads(manifest.read_text()).get('types', [])}


def mine(element, module, table, types):
    """Whether an upstream element belongs to the module: its package's owner, and, when the module's upstream build
    modules are known, a type of one of them."""
    if owner(element, table) != module.name:
        return False
    if not module.upstream_modules or not types:
        return True
    built = types.get(element.split('#', 1)[0].rstrip('*'))
    return built is None or built in module.upstream_modules


# ---------------------------------------------------------------------------------------------------------------
# Steps


def resolve(directory, root=ROOT):
    """The module a directory holds, from the policy that registers it."""
    directory = str(Path(directory)).rstrip('/')
    found = {meta[1]: (name, meta[0]) for name, meta in workspace.package_repos(root).items()}
    if directory not in found:
        raise LookupError(f'{directory} is not a registered module: register it in policy/framework.json (or '
                          'policy/boot.json, policy/packages.json), add its subPackage to the root dub.sdl, then run '
                          '`python3 tools/platform_modules.py --write` (FLINT-E0535)')
    name, repo = found[directory]
    ported = ported_modules(root)
    packages = json.loads((root / 'policy' / 'packages.json').read_text())['packages']
    if name in ported:
        kind, _, upstream, meta = ported[name]
        mine = sorted(p for p, m in ownership(root).items() if m == name)
        mine = [p for p in mine if not any(p.startswith(q + '.') for q in mine)]
        found = Module(name, kind, repo, directory, [directory], mine, upstream, meta.get('budget', {}),
                       meta.get('provisional', []))
        found.upstream_modules = upstream_modules(found, root)
        return found
    if name in packages:
        return Module(name, 'package', repo, directory, [directory], [])
    return Module(name, 'boot', repo, directory, [directory], [])


def structural(module, run):
    argv = [sys.executable, 'tools/gates.py', '--gate', 'structural']
    argv += ['--package', module.name] if module.kind == 'package' else ['--repo', module.repo]
    code, out, err = run(argv)
    if code == 0:
        return Result('structural', 'pass')
    text = out + err
    failure = next((line for line in text.splitlines() if 'GATE FAILED' in line), text.strip()[-600:])
    failure = failure.replace('GATE FAILED:', '').strip()
    if module.name in failure or module.directory in failure:
        return Result('structural', 'fail', [failure, 'fix it in this module (AGENTS.md "Dependency rules" and '
                                             '"Mandatory language rules")'])
    return Result('structural', 'error', [failure, f'a {module.repo}-wide structural failure that does not name '
                                          f'{module.name}: not this module\'s; tell the integration owner'])


def api(module, run, flint, release=False, root=ROOT):
    if not Path(flint).is_file():
        return Result('api', 'error', [f'no flint at {flint}: `python3 tools/install_toolchains.py --compiler flint` '
                                       'or pass --flint'])
    messages, details = [], {}
    code, out, err = run([flint, 'api', 'headers', *module.roots, '--json'])
    try:
        headers = json_document(out)
    except ValueError:
        return Result('api', 'error', ['flint api headers printed no JSON:', *tail(out + err)])
    details['headers'] = {k: headers.get(k) for k in ('files', 'ported', 'problems')}
    problems = [d for d in headers.get('diagnostics', []) if d.get('severity', 'error') == 'error']
    if problems:
        messages.append(f'{len(problems)} ported-file header problems:')
        messages += [f"  {d.get('file', '?')}: {d.get('message', '')}" for d in problems[:20]]
        messages.append('each ported file carries `Ported from <owner/project> <tag>, <path>` and "Modified by the '
                        'Flint authors", for an upstream policy/upstream-licences.json lets Flint port (AGENTS.md '
                        '"Ported code")')
    if not module.java_packages:
        details['coverage'] = 'not applicable: the module ports no upstream Java packages'
        return Result('api', 'fail' if messages else 'pass', messages, details=details)
    mapping = root / 'api' / module.repo / 'mapping.json'
    code, out, err = run([flint, 'api', 'coverage', '--repo', module.repo, '--mapping', mapping, '--show', '0',
                          '--json', *(['--release'] if release else [])])
    try:
        coverage = json_document(out)
    except ValueError:
        return Result('api', 'error', messages + ['flint api coverage printed no JSON:', *tail(out + err)])
    table, types = ownership(root), type_modules(module, root)
    ids = find_key(coverage, 'unclassified_ids') or {}
    groups = ids.values() if isinstance(ids, dict) else [ids]
    unclassified = sorted({e for group in groups for e in group if mine(e, module, table, types)})
    elements = json.loads(mapping.read_text()).get('elements', {}) if mapping.is_file() else {}
    deferred = sorted(e for e, entry in elements.items()
                      if entry.get('category') == 'deferred' and mine(e, module, table, types))
    details.update({'java_packages': module.java_packages, 'unclassified': len(unclassified), 'deferred': len(deferred)})
    if unclassified:
        messages.append(f'{len(unclassified)} upstream elements under {", ".join(module.java_packages)} are '
                        'unclassified (FLINT-E1002):')
        messages += ['  ' + e for e in unclassified[:20]] + (['  ...'] if len(unclassified) > 20 else [])
        messages.append(f'classify each in api/{module.repo}/mapping.json as ported ("d": the D symbol), adapted '
                        '("rules": R1-R14) or excluded ("category"); docs/spring/api-mapping.md')
    if release and deferred:
        messages.append(f'{len(deferred)} elements are excluded as "deferred"; a release resolves each:')
        messages += ['  ' + e for e in deferred[:20]] + (['  ...'] if len(deferred) > 20 else [])
    return Result('api', 'fail' if messages else 'pass', messages, details=details)


QUALITY_BASELINE = 'policy/quality-baseline.json'


def quality(module, run):
    """quality.py on the module's roots against the ratchet (coordinator, 2026-11-25): findings recorded in
    policy/quality-baseline.json are inherited debt and pass; any other finding fails, and so does a recorded one that
    is gone until the baseline is shrunk."""
    argv = [sys.executable, 'tools/quality.py']
    for root in module.roots:
        argv += ['--path', root]
    code, out, err = run(argv + ['--baseline', QUALITY_BASELINE])
    if code == 0:
        return Result('quality', 'pass')
    text = out + err
    if missing_tool(code, text) or "is not Flint's patched dfmt" in text:
        return Result('quality', 'error', [*tail(text, 4), 'install the pinned dfmt and D-Scanner: '
                                           '`python3 tools/install_quality_tools.py`'])
    findings = [line for line in text.splitlines() if line.strip() and not line.startswith(('+', '-', '@@', ' '))]
    return Result('quality', 'fail', ['  ' + line for line in findings[-30:]] +
                  [f'fix each new finding; inherited ones are in {QUALITY_BASELINE}, which only shrinks. dfmt is the '
                   'patched `+flint.stack-udas` build, D-Scanner reads dscanner.ini, and a justified complexity '
                   'exception goes in policy/complexity-allowlist.json'])


NATIVE_MISSING = ('pinned llhttp provider is unavailable', 'cannot find -lflint', 'undefined reference to `llhttp_',
                  'undefined reference to `PQ', 'undefined reference to `OPENSSL')


def tests(module, run, record=None):
    packages = [':' + module.name] + [p for p in (record or {}).get('test_packages', []) if p != ':' + module.name]
    messages, details = [], {}
    for package in packages:
        for compiler in ('dmd', 'ldc2'):
            code, out, err = run(['dub', 'test', package, f'--compiler={compiler}', '--build=unittest'])
            details[f'{package} {compiler}'] = 'pass' if code == 0 else f'exit {code}'
            if code == 0:
                continue
            text = out + err
            if code == 127:
                return Result('tests', 'error', [f'{compiler} or dub is not available:', *tail(text, 4)], details=details)
            if any(s in text for s in NATIVE_MISSING):
                return Result('tests', 'error', ['the native providers are not built or emitted in this checkout: '
                                                 'python3 tools/native_build.py --profile ci --target '
                                                 'linux-x86_64-glibc --phase build (never commit the dub.sdl native '
                                                 'blocks it writes)', *tail(text, 4)], details=details)
            failed = [line for line in text.splitlines()
                      if re.search(r'FAIL|Error|error:|Assertion|core\.exception|failed', line)]
            messages.append(f'`dub test {package} --compiler={compiler} --build=unittest` failed (exit {code}):')
            messages += ['  ' + line.strip() for line in (failed or text.strip().splitlines())[-15:]]
    if messages:
        messages.append('both compilers must pass (AGENTS.md "Daily task loop", step 4)')
    return Result('tests', 'fail' if messages else 'pass', messages, details=details)


# ---------------------------------------------------------------------------------------------------------------
# Upstream tests


# `@("name")` followed, past attributes and comments, by `unittest`.
UNITTEST = re.compile(r'@\("((?:[^"\\]|\\.)*)"\)(?:\s+|//[^\n]*|@?\w+\b(?:\([^)]*\))?)*?\s*unittest\b')
# `Ported from spring-projects/spring-framework v7.1.0, spring-jdbc/src/test/java/.../XxxTests.java` (or `:`).
PORTED_TEST = re.compile(r'Ported from\s+(\S+)\s+(\S+?)[,:]\s+(\S+?/src/test/java/\S+?\.java)')
IDENTIFIER = re.compile(r'[A-Za-z_]\w*$')


def test_key(path):
    """An upstream test's record key: its path under src/test/java."""
    return path.split('/src/test/java/', 1)[-1]


def unittest_names(path):
    return set(UNITTEST.findall(path.read_text(errors='replace')))


def module_files(module, root=ROOT):
    skip = ('/.dub/', '/.flint/', '/build/', '/artifacts/')
    return sorted(p for r in module.roots for p in (root / r).rglob('*.d') if not any(s in str(p) for s in skip))


def scan_tests(files, root=ROOT):
    """{key: entry} for the upstream tests the module's D files say they port. A file that ports one test class names
    its unittests by method (`@("parseSql")`); a file that ports several names them `@("Class.method")`. Names that
    are not identifiers are Flint's own tests, never counted as ported methods."""
    found = {}
    for path in files:
        text = path.read_text(errors='replace')
        headers = list(dict.fromkeys(test_key(m.group(3)) for m in PORTED_TEST.finditer(text)))
        if not headers:
            continue
        names = UNITTEST.findall(text)
        for header in headers:
            cls = Path(header).stem
            methods = {n.split('.', 1)[1] for n in names
                       if n.startswith(cls + '.') and IDENTIFIER.match(n.split('.', 1)[1])}
            if len(headers) == 1:
                methods |= {n for n in names if IDENTIFIER.match(n)}
            entry = found.setdefault(header, {'status': 'ported', 'd': [], 'methods': {'ported': []}})
            entry['d'].append(str(path.relative_to(root)))
            entry['methods']['ported'] = sorted(set(entry['methods']['ported']) | methods)
    for entry in found.values():  # one file is a string, several a list
        entry['d'] = entry['d'][0] if len(entry['d']) == 1 else sorted(entry['d'])
    return found


def cache_dirs():
    dirs = [Path(os.environ['FLINT_CACHE']) / 'api'] if os.environ.get('FLINT_CACHE') else []
    return dirs + [Path.home() / '.flint' / 'cache' / 'api', ROOT / '.flint' / 'cache' / 'api']


def upstream_inventory(module, root=ROOT, caches=None):
    """The record keys of every upstream test class the module owns, from the fetched upstream sources; None when no
    fetched copy of the upstream exists."""
    if not module.upstream or '@' not in module.upstream:
        return None
    project, _, version = module.upstream.partition('@')
    table = ownership(root)
    for cache in caches if caches is not None else cache_dirs():
        for key in (f'{project}-{version}-tests', f'{project}-{version}'):
            base = cache / key
            if not base.is_dir():
                continue
            keys = set()
            for path in base.rglob('*Tests.java'):
                text = str(path.relative_to(base))
                if '/src/test/java/' not in '/' + text:
                    continue
                built = ('/' + text).split('/src/test/java/', 1)[0].rsplit('/', 1)[-1]
                if module.upstream_modules and built not in module.upstream_modules:
                    continue
                key = test_key('/' + text)
                if owner(key[:-len('.java')], table) == module.name:
                    keys.add(key)
            return sorted(keys)
    return None


def check_upstream_tests(module, record, root=ROOT, inventory=None):
    if record.get('schema') != SCHEMA:
        return [f'{UPSTREAM_TESTS}: "schema" must be "{SCHEMA}"']
    messages, names = [], {}
    for key, entry in sorted(record.get('classes', {}).items()):
        status = entry.get('status')
        if status not in ('ported', 'partial', 'excluded'):
            messages.append(f'{key}: "status" must be ported, partial or excluded, not {status!r}')
            continue
        if status == 'excluded':
            if not str(entry.get('reason', '')).strip():
                messages.append(f'{key}: excluded without a "reason" (a rule id or a short note)')
            continue
        files = entry.get('d') or []
        files = [files] if isinstance(files, str) else list(files)
        missing = [f for f in files if not (root / f).is_file()]
        if not files or missing:
            messages.append(f'{key}: its D file {(missing or [None])[0]!r} does not exist')
            continue
        have = set().union(*(names.setdefault(f, unittest_names(root / f)) for f in files))
        where = files[0] if len(files) == 1 else ', '.join(files)
        cls = Path(key).stem
        methods = entry.get('methods', {})
        for method in methods.get('ported', []):
            if f'{cls}.{method}' not in have and method not in have:
                messages.append(f'{key}: ported method {method} has no `@("{cls}.{method}") unittest` (or '
                                f'`@("{method}")` in a one-class file) in {where}')
        for method, reason in methods.get('skipped', {}).items():
            if not str(reason).strip():
                messages.append(f'{key}: skipped method {method} has no reason')
        if status == 'partial' and not methods.get('skipped'):
            messages.append(f'{key}: "partial", but "methods.skipped" lists no method with its reason')
    if len(messages) > 40:
        messages = messages[:40] + [f'... and {len(messages) - 40} more problems in the record']
    if inventory:
        missing = [k for k in inventory if k not in record.get('classes', {})]
        if missing:
            messages.append(f'{len(missing)} upstream test classes are not in {UPSTREAM_TESTS}; port each, or record '
                            'it as partial or excluded with a reason:')
            messages += ['  ' + k for k in missing[:20]] + (['  ...'] if len(missing) > 20 else [])
    return messages


def counts(record):
    classes = list(record.get('classes', {}).values())
    return {'classes': len(classes),
            'ported': sum(c.get('status') == 'ported' for c in classes),
            'partial': sum(c.get('status') == 'partial' for c in classes),
            'excluded': sum(c.get('status') == 'excluded' for c in classes),
            'methods_ported': sum(len(c.get('methods', {}).get('ported', [])) for c in classes),
            'methods_skipped': sum(len(c.get('methods', {}).get('skipped', {})) for c in classes)}


def draft(module, root=ROOT):
    """A new or extended record from the module's `Ported from ...Tests.java` headers and unittest names; existing
    entries are kept as they are."""
    path = root / module.directory / UPSTREAM_TESTS
    record = json.loads(path.read_text()) if path.is_file() else {
        'schema': SCHEMA, 'upstream': module.upstream, 'module': module.name, 'test_packages': [':' + module.name],
        'classes': {}}
    for key, entry in scan_tests(module_files(module, root), root).items():
        record['classes'].setdefault(key, entry)
    path.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return record


def upstream_tests(module, write=False, root=ROOT, caches=None):
    path = root / module.directory / UPSTREAM_TESTS
    pinned = bool(module.upstream and '@' in module.upstream)
    if write and pinned:
        draft(module, root)
    if not path.is_file():
        if not pinned:
            return Result('upstream-tests', 'skip', [f'{module.kind} module with no pinned upstream: no upstream tests '
                                                     'to record'])
        return Result('upstream-tests', 'fail', [f'{module.directory}/{UPSTREAM_TESTS} is missing; every ported module '
                                                 'ports its upstream tests (AGENTS.md "Proof obligations")',
                                                 f'draft it with: python3 tools/gates.py --module {module.directory} '
                                                 '--definition-of-done --step upstream-tests --write-upstream-tests, '
                                                 'then give each exclusion and skip its reason'])
    record = json.loads(path.read_text())
    inventory = upstream_inventory(module, root, caches)
    messages = check_upstream_tests(module, record, root, inventory)
    details = counts(record)
    details['inventory'] = len(inventory) if inventory is not None else 'unavailable'
    if messages:
        return Result('upstream-tests', 'fail', messages, details=details)
    if inventory is None and pinned:
        return Result('upstream-tests', 'error', [f'the record is consistent, but there are no fetched {module.upstream} '
                                                  'sources to check it against: run `flint api fetch --tests` (the '
                                                  'cache is FLINT_CACHE or ~/.flint/cache)'], details=details)
    return Result('upstream-tests', 'pass', details=details)


# ---------------------------------------------------------------------------------------------------------------
# Budgets and applications


def budgets(module, run):
    if module.kind != 'framework':
        return Result('budgets', 'skip', [f'{module.kind} module: policy has no per-module budget for it yet'])
    if not module.budget:
        return Result('budgets', 'fail', [f'{module.name} has no "budget" in policy/framework.json'])
    with tempfile.TemporaryDirectory(prefix='dod-sizes-') as directory:
        out_path = Path(directory) / 'sizes.json'
        code, out, err = run([sys.executable, 'tools/measure_builds.py', '--framework-sizes', '--framework',
                              module.name, '--output', out_path])
        if code != 0 or not out_path.is_file():
            hint = (['measure_builds measures a commit: commit your work (on your task branch) and rerun this step']
                    if 'invalidate commit identity' in out + err else [])
            return Result('budgets', 'error', ['measure_builds.py --framework-sizes failed:', *tail(out + err, 6),
                                               *hint])
        row = json.loads(out_path.read_text()).get('framework', {}).get(module.name)
    if not row:
        return Result('budgets', 'fail', [f'{module.name} has no size probe: give it a "bench" entry (fixture, '
                                          'baseline, edit_source) in policy/framework.json'])
    messages, details = [], {}
    for key in ('incremental_linked_bytes', 'template_instances'):
        measured, budget = row.get(key), module.budget.get(key)
        details[key] = {'measured': measured, 'budget': budget}
        if budget is None:
            messages.append(f'{key}: no budget in policy/framework.json')
        elif measured is None:
            messages.append(f'{key}: measure_builds reported no value')
        elif measured > budget:
            messages.append(f'{key} {measured} exceeds the budget {budget} (policy/framework.json); a budget miss is '
                            'a blocker, not a rationale (AGENTS.md): cut the module\'s instantiations or linked code')
    details['provisional, not gated'] = sorted(module.provisional)
    return Result('budgets', 'fail' if messages else 'pass', messages, details=details)


def using_apps(module, root=ROOT):
    """The Spring benchmark apps whose dependency closure contains the module."""
    edges = workspace.dependencies(root)
    apps = []
    for manifest in sorted((root / 'benchmarks' / 'spring' / 'flint').glob('*/flint.toml')):
        document = tomllib.loads(manifest.read_text())
        todo = [d[len('flint:'):] for section in ('dependencies', 'test-dependencies')
                for d in document.get(section, {}) if d.startswith('flint:')]
        closure = set()
        while todo:
            name = todo.pop()
            if name not in closure:
                closure.add(name)
                todo += [d.removeprefix('flint:') for d in edges.get(name, [])]
        if module.name in closure:
            apps.append(manifest.parent.name)
    return apps


def applications(module, run, which='auto', flint=None, root=ROOT):
    if which == 'none':
        return Result('apps', 'skip', ['--apps none'])
    apps = using_apps(module, root) if which == 'auto' else [a for a in which.split(',') if a]
    if not apps:
        return Result('apps', 'skip', ['no Spring benchmark app (benchmarks/spring/flint) uses this module'])
    if not flint or not Path(flint).is_file():
        return Result('apps', 'error', [f'no flint at {flint}: `python3 tools/install_toolchains.py --compiler flint`'])
    messages, details = [], {'apps': apps}
    budget_cli = run([flint, 'budget', '--help'])[0] == 0
    for app in apps:
        code, out, err = run([flint, 'test', '-C', f'benchmarks/spring/flint/{app}', '--compiler', 'both', '--verify'])
        details[f'{app} allocation tests'] = 'pass' if code == 0 else f'exit {code}'
        if code != 0:
            messages.append(f'{app}: its tests or request-allocation budgets fail (policy/request-allocations.json; '
                            'budgets only go down):')
            messages += tail(out + err, 10)
        code, out, err = run([sys.executable, 'tools/spring_bench.py', 'accept', app, '--impl', 'flint'])
        details[f'{app} acceptance'] = 'pass' if code == 0 else f'exit {code}'
        if code != 0:
            messages.append(f'{app}: the golden suite fails in exact mode (benchmarks/spring/suites):')
            messages += tail(out + err, 10)
        if not budget_cli:
            details[f'{app} flint budget'] = 'skip: `flint budget` does not exist yet (m7)'
            continue
        code, out, err = run([flint, 'budget', '--app', f'benchmarks/spring/flint/{app}', '--json'])
        details[f'{app} flint budget'] = {0: 'pass', 1: 'regression', 2: 'run failed'}.get(code, f'exit {code}')
        if code == 1:
            messages.append(f'{app}: flint budget reports a regression, or a missing or stale budget:')
            messages += tail(out + err, 10)
        elif code != 0:
            messages.append(f'{app}: flint budget could not run (exit {code}):')
            messages += tail(out + err, 6)
    return Result('apps', 'fail' if messages else 'pass', messages, details=details)


# ---------------------------------------------------------------------------------------------------------------


def run_all(directory, steps=STEPS, apps='auto', release=False, hold=True, flint=None, write_upstream_tests=False,
            runner=None, root=ROOT):
    run = runner or Runner(hold=hold, root=root)
    flint = Path(flint) if flint else root / '.flint' / 'bin' / 'flint'
    began = time.monotonic()
    try:
        module = resolve(directory, root)
    except LookupError as exc:
        return None, [Result('resolve', 'fail', [str(exc)], rerun(directory, 'resolve'))]
    results = [Result('resolve', 'pass', seconds=round(time.monotonic() - began, 1),
                      details={'name': module.name, 'kind': module.kind, 'repo': module.repo,
                               'upstream': module.upstream, 'java_packages': module.java_packages})]
    record_path = root / module.directory / UPSTREAM_TESTS
    table = {'structural': lambda: structural(module, run),
             'api': lambda: api(module, run, flint, release, root),
             'quality': lambda: quality(module, run),
             'tests': lambda: tests(module, run, json.loads(record_path.read_text()) if record_path.is_file() else None),
             'upstream-tests': lambda: upstream_tests(module, write_upstream_tests, root),
             'budgets': lambda: budgets(module, run),
             'apps': lambda: applications(module, run, apps, flint, root)}
    for step in steps:
        if step == 'resolve':
            continue
        started = time.monotonic()
        result = table[step]()
        result.seconds = round(time.monotonic() - started, 1)
        result.rerun = rerun(directory, step)
        results.append(result)
    return module, results


def exit_status(results):
    if any(r.status == 'fail' for r in results):
        return 1
    if any(r.status == 'error' for r in results):
        return 2
    return 0


def report(module, results, directory):
    return {'schema': 'flint.definition-of-done/1', 'module': module.name if module else None, 'directory': directory,
            'time': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'done': exit_status(results) == 0,
            'steps': [asdict(r) for r in results]}


def render(out, results):
    lines = []
    for r in results:
        lines.append(f'{r.status.upper():5} {r.step:15} {r.seconds:7.1f} s')
        lines += ['      ' + m for m in r.messages]
        if r.status in ('fail', 'error') and r.rerun:
            lines.append('      rerun: ' + r.rerun)
    skipped = [r.step for r in results if r.status == 'skip']
    verdict = 'DONE' if out['done'] else 'NOT DONE'
    lines.append(f"{verdict}: {out['module'] or out['directory']}" + (f" (skipped: {', '.join(skipped)})" if skipped else ''))
    return '\n'.join(lines)


def main(argv=None):
    p = argparse.ArgumentParser(prog='gates.py --module DIR --definition-of-done', description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--module', required=True, help='the module directory, e.g. framework/jdbc')
    p.add_argument('--definition-of-done', action='store_true', required=True)
    p.add_argument('--step', action='append', choices=STEPS, help='run only this step (repeatable; resolve always runs)')
    p.add_argument('--apps', default='auto', help='auto (the Spring apps that use the module), none, or APP,APP')
    p.add_argument('--release', action='store_true', help='api: deferred exclusions fail too')
    p.add_argument('--no-hold', action='store_true', help='do not run under measure_queue.py hold')
    p.add_argument('--flint', type=Path, help='the flint executable (default: .flint/bin/flint)')
    p.add_argument('--write-upstream-tests', action='store_true',
                   help='draft or extend <dir>/upstream-tests.json from the module\'s ported test files first')
    p.add_argument('--json', action='store_true', help='print the report as JSON')
    a = p.parse_args(argv)
    if not a.no_hold:
        # The whole command runs under one hold, its own Python work (ownership, the upstream-tests scan) included, so
        # it never loads venus during a measurement window; inside, nothing is wrapped again.
        argv = list(sys.argv[1:] if argv is None else argv)
        command = [sys.executable, str(ROOT / 'tools' / 'measure_queue.py'), 'hold', '--', sys.executable,
                   str(Path(__file__).resolve()), *argv, '--no-hold']
        return subprocess.run(command, cwd=ROOT).returncode
    steps =[s for s in STEPS if s == 'resolve' or not a.step or s in a.step]
    module, results = run_all(a.module, steps, a.apps, a.release, not a.no_hold, a.flint, a.write_upstream_tests)
    out = report(module, results, a.module)
    if module:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        (REPORT_DIR / f'{module.name}.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(out, indent=2) if a.json else render(out, results))
    return exit_status(results)


if __name__ == '__main__':
    sys.exit(main())
