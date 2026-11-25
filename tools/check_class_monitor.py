#!/usr/bin/env python3
"""The class-monitor gate (FLINT-E0536): `python3 tools/check_class_monitor.py [--json] [--compiler DMD]`.

Owner rule of 2026-11-25 (docs/spring/phase1/decisions.md): a class's metadata object (`typeid(X)`, `X.classinfo`,
any `TypeInfo`) never owns a GC-allocated monitor, so the collector can stop scanning class metadata. In D a
metadata object's monitor word can point at a GC object only through `new Mutex(obj)` (either constructor taking an
`Object`, plain or `shared`) or `setSameMutex(ownee, owner)` with the metadata object as `obj` or `ownee`, or through
druntime internals (`_d_setSameMutex`, a direct `__monitor` write). `synchronized (typeid(X))` is fine: druntime
allocates that monitor with calloc. `core.sync.rwmutex`, `core.sync.condition` and the other `core.sync` types have no
constructor that takes an arbitrary `Object`.

The check is typed: the compiler decides the static type of every argument, not this script. The gate copies the
compiler's own `object.d` and `core/sync/mutex.d` into a private import directory and adds overloads there:

    class Mutex { @disable this(TypeInfo obj); @disable this(TypeInfo obj) shared; ... }
    @disable void setSameMutex(shared TypeInfo ownee, shared Object owner) @safe pure nothrow @nogc;

D's overload resolution picks the more specialised `TypeInfo` overload exactly when the argument's static type
converts to `TypeInfo` (every `TypeInfo_*`, `ClassInfo`, through locals, `auto`, parameters, fields, function
results, casts, UFCS and aliases) and the compiler rejects the call at its own file:line. It then type-checks
(`-o-`, no code generation) every module that can reach these APIs with that import directory in front of
druntime. Ordinary builds never see the copy, so `flint build` and its build times are unchanged.

Which modules are compiled is narrowed textually, which keeps the gate fast: only modules that mention `Mutex`,
`setSameMutex`, `core.sync` or the druntime internals, or a public alias or subclass of `Mutex` that such a module
declares (to a fixed point). A module the gate cannot type-check fails the gate: a type the gate cannot see is never
a pass.

Limits (the runtime verifier, the second enforcement, covers them): an argument whose static type is `Object` hides
the metadata object (`new Mutex(cast(Object) typeid(X))`, or a `Mutex` subclass forwarding an `Object` parameter to
`super`); a template body is checked only where the type-checked modules instantiate it; code under a `version`
that none of its package's DUB configurations sets, or for another target OS, is not compiled. druntime and Phobos
were reviewed by hand and are not scanned.

A deliberate negative test suppresses one finding with a reason, on the finding's line or the line above:

    auto mutex = new Mutex(typeid(Probe)); // flint: allow-class-monitor (the verifier's negative test)

A suppression without a reason, or one that matches no finding, fails the gate; the report counts the honoured ones.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from check_exchange_retention import _blank

ROOT = Path(__file__).resolve().parent.parent
CODE = 'FLINT-E0536'
# Application, framework and Boot sources; every dependency the apps lock is a workspace package under these.
SOURCE_ROOTS = ('apps', 'benchmarks/spring/flint', 'framework', 'boot', 'starters', 'packages', 'examples')
RULE = ("docs/spring/phase1/gc.md section 3c and the owner rule of 2026-11-25 in docs/spring/phase1/decisions.md, "
        "'class metadata never owns a GC monitor'")
FIX_MUTEX = ('lock a dedicated `new Mutex()` instead of giving class metadata a GC-allocated monitor; see ' + RULE)
FIX_SAME = ('synchronize on a dedicated object (or a dedicated `new Mutex()`) instead of making class metadata share '
            'a GC-allocated monitor; see ' + RULE)
FIX_INTERNAL = ('use a dedicated `new Mutex()`; only druntime may touch a monitor word directly; see ' + RULE)
SUPPRESSION = re.compile(r'//\s*flint:\s*allow-class-monitor\b(.*)$')
REASON = re.compile(r'^\s*\(\s*([^()\s][^()]*?)\s*\)')
WATCHED = ('Mutex', 'setSameMutex', '_d_setSameMutex', '__monitor')
# Druntime internals no Flint or application code may name: there is no typed way to use them safely.
INTERNALS = {'_d_setSameMutex': '`_d_setSameMutex` is a druntime internal that sets a monitor word directly',
             '__monitor': 'direct access to an object\'s monitor word (`__monitor`)'}
POISON = {
    re.compile(r'constructor `core\.sync\.mutex\.Mutex\.this` cannot be used because it is annotated with `@disable`'):
        ('`new Mutex(...)` gives a TypeInfo/ClassInfo (class metadata) a GC-allocated monitor', FIX_MUTEX),
    re.compile(r'function `object\.setSameMutex` cannot be used because it is annotated with `@disable`'):
        ('`setSameMutex(ownee, ...)` gives a TypeInfo/ClassInfo (class metadata) a GC-allocated monitor', FIX_SAME),
}
# The instantiation site of a template whose body was rejected.
CONSEQUENCE = re.compile(r'^template instance `[^`]*` error instantiating$')
DIAGNOSTIC = re.compile(r'^(.+?)\((\d+)(?:,\d+)?\): (Error|Deprecation|Warning): (.*)$')
_MUTEX_OVERLOADS = '''
    // Added by tools/check_class_monitor.py (FLINT-E0536) in its private copy; druntime itself is unchanged.
    @disable this(TypeInfo obj) @safe pure nothrow @nogc;
    @disable this(TypeInfo obj) shared @safe pure nothrow @nogc;
    this(typeof(null) obj) @safe pure nothrow @nogc { }
    this(typeof(null) obj) shared @safe pure nothrow @nogc { }
'''
_OBJECT_OVERLOAD = '''
// Added by tools/check_class_monitor.py (FLINT-E0536) in its private copy; druntime itself is unchanged.
@disable void setSameMutex(shared TypeInfo ownee, shared Object owner) @safe pure nothrow @nogc;
'''


class GateError(ValueError):
    """The gate cannot reach a verdict; it fails closed."""


def compiler_path(explicit=None):
    """DMD (or LDC's DMD-compatible ldmd2): --compiler, $DMD, the pinned toolchain, then PATH."""
    if explicit is not None:
        found = shutil.which(str(explicit))
        if not found:
            raise GateError(f'{explicit} is not an executable compiler')
        return Path(found).resolve()
    candidates = [os.environ.get('DMD'), ROOT / '.tools/dmd2/linux/bin64/dmd', 'dmd']
    candidates += sorted(ROOT.glob('.tools/ldc2-*/bin/ldmd2')) + ['ldmd2']
    for candidate in candidates:
        found = shutil.which(str(candidate)) if candidate else None
        if found:
            return Path(found).resolve()
    raise GateError('the class-monitor gate needs DMD or ldmd2: install the toolchain or set DMD=/absolute/path')


def standard_imports(compiler):
    """(druntime import directory, Phobos import directory or None, is LDC) of `compiler`."""
    dmd_druntime = compiler.parents[2] / 'src/druntime/import'
    if (dmd_druntime / 'object.d').is_file():
        return dmd_druntime, compiler.parents[2] / 'src/phobos', False
    ldc_import = compiler.parents[1] / 'import'
    if (ldc_import / 'object.d').is_file():
        return ldc_import, None, True
    raise GateError(f'cannot find druntime next to {compiler}')


def write_shadow(druntime, directory):
    """The private copy of object.d and core/sync/mutex.d with the poisoned overloads."""
    mutex = (druntime / 'core/sync/mutex.d').read_text(encoding='utf-8')
    obj = (druntime / 'object.d').read_text(encoding='utf-8')
    opening = re.search(r'^class Mutex\b[^{;]*\{', mutex, re.M)
    if (opening is None or '@disable' in mutex or not re.search(r'\bthis\(Object obj\) @trusted', mutex)
            or not re.search(r'\bthis\(Object obj\) shared @trusted', mutex)
            or 'void setSameMutex(shared Object ownee, shared Object owner)' not in obj):
        raise GateError(f"{druntime}: druntime's Mutex(Object) or setSameMutex changed; review "
                        'tools/check_class_monitor.py before trusting the gate again')
    (directory / 'core/sync').mkdir(parents=True)
    (directory / 'core/sync/mutex.d').write_text(mutex[:opening.end()] + _MUTEX_OVERLOADS + mutex[opening.end():],
                                                 encoding='utf-8')
    (directory / 'object.d').write_text(obj + _OBJECT_OVERLOAD, encoding='utf-8')


def write_config(directory, ldc):
    """An empty compiler configuration, so the private copy precedes druntime on the import path."""
    path = directory / ('ldc2.conf' if ldc else 'dmd.conf')
    text = ('default:\n{\n    switches = [];\n    post-switches = [];\n    lib-dirs = [];\n};\n' if ldc
            else '[Environment32]\nDFLAGS=\n\n[Environment64]\nDFLAGS=\n')
    path.write_text(text, encoding='utf-8')
    return path


def d_sources(root, tops):
    """Every .d file under the source roots, skipping hidden directories (.flint, .dub) and build output."""
    for top in tops:
        base = root / top
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.d')):
            parts = path.relative_to(base).parts
            if not any(part.startswith('.') or part in ('build', 'artifacts') for part in parts):
                yield path


def _names_pattern(names):
    return re.compile(r'\b(?:' + '|'.join(sorted(re.escape(name) for name in names)) + r')\b|\bcore\s*\.\s*sync\b')


def candidates(files):
    """{path: blanked text} of the modules that can reach the watched APIs, widened through aliases and subclasses."""
    raw = {path: path.read_text(encoding='utf-8', errors='replace') for path in files}
    blanked = {}
    names = set(WATCHED)
    chosen = {}
    while True:
        pattern = _names_pattern(names)
        added = {}
        for path, text in raw.items():
            # The raw text is a cheap superset; comments and strings are blanked only where it matches.
            if path in chosen or not pattern.search(text):
                continue
            if path not in blanked:
                blanked[path] = _blank(text)
            if pattern.search(blanked[path]):
                added[path] = blanked[path]
        if not added:
            return chosen
        chosen.update(added)
        watched = '|'.join(sorted(re.escape(name) for name in names))
        for text in added.values():
            # `alias L = Mutex;`, `import core.sync.mutex : L = Mutex;` and `class L : Mutex` name it anew.
            names.update(re.findall(r'\b(\w+)\s*=\s*(?:[\w.]+\.)?(?:' + watched + r')\b', text))
            names.update(re.findall(r'\bclass\s+(\w+)[^{;]*:[^{;]*\b(?:' + watched + r')\b', text))


def suppressions(path, text):
    """({finding line: reason}, [problems]) of the `// flint: allow-class-monitor (reason)` comments in `text`."""
    allowed, problems = {}, []
    for number, line in enumerate(text.splitlines(), 1):
        match = SUPPRESSION.search(line)
        if not match:
            continue
        reason = REASON.match(match.group(1))
        if reason is None:
            problems.append((path, number, 'a class-monitor suppression needs a reason: '
                             '`// flint: allow-class-monitor (why this is deliberate)`'))
            continue
        # The comment covers its own line, or the next line when it stands alone.
        code = line[:match.start()].strip()
        allowed[number if code else number + 1] = (number, reason.group(1))
    return allowed, problems


def internal_findings(path, blanked):
    found = []
    for number, line in enumerate(blanked.splitlines(), 1):
        for name, what in INTERNALS.items():
            if re.search(r'\b' + re.escape(name) + r'\b', line):
                found.append((path, number, what, FIX_INTERNAL))
    return found


def _project_of(path, root):
    """The directory of the DUB package or Flint project that owns `path` (its nearest manifest)."""
    for parent in path.parents:
        if any((parent / name).is_file() for name in ('dub.sdl', 'dub.json', 'flint.toml')):
            return parent
        if parent == root:
            break
    return path.parent


def _sdl_values(line, key):
    """The values of an SDL directive: its quoted strings that are not an attribute's (`platform="linux"`)."""
    match = re.match(r'\s*' + key + r'\b(.*)$', line)
    return re.findall(r'(?<![=\w])"([^"]*)"', match.group(1)) if match else None


def project_settings(directory):
    """(import directories, string-import directories, version sets) of a project, over all its configurations."""
    imports, strings = [], []
    base_versions, configurations = [], []
    sdl, toml = directory / 'dub.sdl', directory / 'flint.toml'
    if sdl.is_file():
        depth, current = 0, None
        for line in sdl.read_text(encoding='utf-8').splitlines():
            stripped = line.split('//', 1)[0]
            configuration = re.match(r'\s*configuration\s+"[^"]*"\s*\{', stripped)
            if configuration and depth == 0:
                current = []
                configurations.append(current)
            for key, target in (('importPaths', imports), ('sourcePaths', imports), ('stringImportPaths', strings)):
                values = _sdl_values(stripped, key)
                if values:
                    target.extend(directory / value for value in values)
            versions = _sdl_values(stripped, 'versions')
            if versions:
                (current if current is not None and depth >= 1 else base_versions).extend(versions)
            depth += stripped.count('{') - stripped.count('}')
            if depth == 0:
                current = None
    elif (directory / 'dub.json').is_file():
        recipe = json.loads((directory / 'dub.json').read_text(encoding='utf-8'))
        for entry in [recipe] + recipe.get('configurations', []):
            imports.extend(directory / value for value in entry.get('importPaths', []) + entry.get('sourcePaths', []))
            strings.extend(directory / value for value in entry.get('stringImportPaths', []))
            if entry is not recipe:
                configurations.append(list(entry.get('versions', [])))
        base_versions = list(recipe.get('versions', []))
    if toml.is_file() or not (sdl.is_file() or (directory / 'dub.json').is_file()):
        imports.extend(directory / name for name in ('src', 'test', 'source'))
        imports.append(directory)
    # One compile per distinct version set, so code each DUB configuration enables is type-checked.
    sets = sorted({tuple(sorted(set(base_versions + extra))) for extra in configurations} or {tuple(base_versions)})
    return [p for p in dict.fromkeys(imports) if p.is_dir()], [p for p in dict.fromkeys(strings) if p.is_dir()], sets


def workspace_imports(root):
    """The `source` directory of every workspace package (the DUB dependencies an app or package can import)."""
    found = []
    for top in ('packages', 'framework', 'boot'):
        base = root / top
        if not base.is_dir():
            continue
        for manifest in sorted(base.rglob('dub.sdl')):
            if any(part.startswith('.') for part in manifest.relative_to(base).parts):
                continue
            if (manifest.parent / 'source').is_dir():
                found.append(manifest.parent / 'source')
    return found


def locked_dependency_roots(root):
    """Source directories of non-workspace dependencies that the apps' flint.lock files name."""
    extra = []
    for lock in sorted(list(root.glob('apps/*/flint.lock')) + list(root.glob('benchmarks/spring/flint/*/flint.lock'))):
        for block in lock.read_text(encoding='utf-8').split('[[package]]')[1:]:
            block = block.split('[[native]]', 1)[0]
            fields = dict(re.findall(r'^(\w+) = "([^"]*)"$', block, re.M))
            kind = fields.get('kind')
            if kind in (None, 'core'):
                continue
            if kind in ('path', 'local') and fields.get('path'):
                extra.append((lock.parent / fields['path']).resolve())
            elif kind == 'dub' and fields.get('version'):
                name = fields['name']
                homes = [Path(os.environ['DUB_HOME']) / 'packages'] if 'DUB_HOME' in os.environ else []
                homes += [Path.home() / '.dub/packages', Path.home() / '.local/share/dub/packages']
                found = [h / name / fields['version'] / name for h in homes
                         if (h / name / fields['version'] / name).is_dir()]
                if not found:
                    raise GateError(f'{lock.relative_to(root)}: {name} {fields["version"]} is not fetched; build the '
                                    'app once so the class-monitor gate can read its sources')
                extra.append(found[0])
            else:
                raise GateError(f'{lock.relative_to(root)}: {fields.get("name")} is a `{kind}` dependency, whose '
                                'sources the class-monitor gate does not locate yet; '
                                'extend tools/check_class_monitor.py')
    return extra


def _relative(path, root):
    try:
        return Path(path).resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


class Result:
    """The gate's verdict: findings and failures (file, line, message, fix) plus what it checked."""

    def __init__(self):
        self.findings = []
        self.errors = []
        self.suppressed = []
        self.modules = 0
        self.compiles = 0
        self.compiler = ''

    @property
    def ok(self):
        return not self.findings and not self.errors

    def lines(self):
        return [f'{f}:{n}: {CODE}: {message}; {fix}' for f, n, message, fix in self.findings + self.errors]

    def summary(self):
        honoured = ', '.join(f'{f}:{n} ({reason})' for f, n, reason in self.suppressed)
        return (f'class-monitor gate ({CODE}): {self.modules} module(s) type-checked in {self.compiles} compile(s) '
                f'with {self.compiler or "no compiler"}; {len(self.suppressed)} suppression(s) honoured'
                + (': ' + honoured if honoured else ''))

    def as_json(self):
        def entry(item):
            return {'file': item[0], 'line': item[1], 'message': item[2], 'fix': item[3]}
        return {'ok': self.ok, 'code': CODE, 'findings': [entry(i) for i in self.findings],
                'errors': [entry(i) for i in self.errors],
                'suppressions': [{'file': f, 'line': n, 'reason': r} for f, n, r in self.suppressed],
                'modules': self.modules, 'compiles': self.compiles, 'compiler': self.compiler}


def _compile(command):
    process = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
    return process.returncode, process.stdout + process.stderr


def check(root=ROOT, tops=SOURCE_ROOTS, compiler=None, extra_roots=None, jobs=4):
    """Run the gate over the D sources under `root`/`tops` (and `extra_roots`); returns a Result."""
    result = Result()
    files = list(d_sources(root, tops))
    for extra in (extra_roots if extra_roots is not None else locked_dependency_roots(root)):
        files.extend(d_sources(extra, ('.',)))
    chosen = candidates(dict.fromkeys(files))
    result.modules = len(chosen)
    if not chosen:
        return result
    raw = {}
    allowed = {}
    for path, blanked in chosen.items():
        raw_findings = internal_findings(path, blanked)
        for item in raw_findings:
            raw[(item[0].resolve(), item[1])] = item[2:]
        allowed[path.resolve()], problems = suppressions(path, path.read_text(encoding='utf-8', errors='replace'))
        result.errors.extend((_relative(p, root), n, message, 'give the suppression a reason')
                             for p, n, message in problems)
    dc = compiler_path(compiler)
    result.compiler = str(dc)
    druntime, phobos, ldc = standard_imports(dc)
    groups = {}
    for path in chosen:
        groups.setdefault(_project_of(path.resolve(), root.resolve()), []).append(path.resolve())
    shared_imports = workspace_imports(root)
    with tempfile.TemporaryDirectory(prefix='flint-class-monitor-') as temporary:
        shadow = Path(temporary) / 'import'
        write_shadow(druntime, shadow)
        config = write_config(Path(temporary), ldc)
        standard = [shadow, druntime] + ([phobos] if phobos else [])
        commands = []
        for project, sources in sorted(groups.items()):
            imports, strings, version_sets = project_settings(project)
            for versions in version_sets:
                command = [str(dc), '-conf=' + str(config), '-o-', '-unittest', '-debug', '-preview=dip1000',
                           '-verrors=0']
                command += ['-I' + str(p) for p in standard + imports + shared_imports]
                command += ['-J' + str(p) for p in strings] + ['-version=' + v for v in versions]
                commands.append((project, versions, command + [str(s) for s in sorted(sources)]))
        with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
            outcomes = list(pool.map(lambda item: _compile(item[2]), commands))
    result.compiles = len(commands)
    for (project, versions, _), (status, output) in zip(commands, outcomes):
        errors, poisoned = [], set()
        for line in output.splitlines():
            match = DIAGNOSTIC.match(line)
            if not match or match.group(3) != 'Error':
                continue
            location = (Path(match.group(1)).resolve(), int(match.group(2)))
            for pattern, (what, fix) in POISON.items():
                if pattern.search(match.group(4)):
                    raw[location] = (what, fix)
                    poisoned.add(location)
                    break
            else:
                errors.append((location, match.group(4)))
        # An error on a rejected line is a consequence of the rejection; any other error leaves the project unproven.
        unexplained = [f'{_relative(where[0], root)}:{where[1]}: {message}' for where, message in errors
                       if where not in poisoned and not (poisoned and CONSEQUENCE.search(message))]
        if unexplained or (status != 0 and not poisoned):
            detail = '; '.join(unexplained[:3]) or output.strip()[-600:]
            where = _relative(project, root) + (f' (versions {", ".join(versions)})' if versions else '')
            result.errors.append((where, 0, 'the class-monitor gate could not type-check this project, so it cannot '
                                  f'prove its Mutex/setSameMutex arguments: {detail}',
                                  'fix the compile error, or give the argument an explicit, non-metadata type'))
    used = set()
    for (path, line), (what, fix) in sorted(raw.items()):
        entry = allowed.get(path, {}).get(line)
        if entry is not None:
            used.add((path, entry[0]))
            result.suppressed.append((_relative(path, root), entry[0], entry[1]))
        else:
            result.findings.append((_relative(path, root), line, what, fix))
    for path, entries in allowed.items():
        for _, (number, _reason) in entries.items():
            if (path, number) not in used:
                result.errors.append((_relative(path, root), number, 'a class-monitor suppression matches no finding',
                                      'remove the stale `// flint: allow-class-monitor` comment'))
    result.findings.sort()
    result.errors.sort()
    result.suppressed.sort()
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--compiler', help='DMD or ldmd2 (default: $DMD, the pinned toolchain, then PATH)')
    parser.add_argument('--root', type=Path, default=ROOT, help='the checkout to scan (default: this one)')
    parser.add_argument('--json', action='store_true', help='print the verdict as JSON')
    args = parser.parse_args(argv)
    try:
        result = check(args.root.resolve(), compiler=args.compiler)
    except GateError as error:
        result = Result()
        result.errors.append(('tools/check_class_monitor.py', 0, str(error), 'see the message'))
    if args.json:
        print(json.dumps(result.as_json(), indent=2))
    else:
        for line in result.lines():
            print(line)
        print(result.summary())
    return 0 if result.ok else 1


if __name__ == '__main__':
    sys.exit(main())
