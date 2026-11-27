#!/usr/bin/env python3
"""Reconcile the OpenJDK manifest with the flint.java* code that exists, and publish the JDK coverage table.

The JDK port (docs/spring/phase2/jdk-port.md) classifies every java.* element in api/framework/mapping.json. This tool
finds the D declarations that already exist, so the classification starts from the truth rather than from zero:

1. It reads the D declarations of framework/java*/source from the compiler's JSON output (dmd -X), and resolves each
   type of the pinned OpenJDK manifest at its R1 canonical path (java.util.Optional -> flint.java.util.Optional; a
   package or member name that is a D keyword takes R19's trailing underscore; public imports re-export).
2. --classify adds a row for each element that exists in D but is still deferred (or unclassified):
   - a type whose D kind matches Java's (or a static-only type as a struct, R1) is ported; an enum as a struct is
     adapted R15, a record is adapted R11 (R16 when a class), an annotation is adapted R2;
   - a member is matched by name (R19), arity and parameter kinds (a Java primitive needs the same D primitive,
     String a D string, a reference a non-primitive; D exceptions' trailing file/line defaults don't count). It is
     ported unless its Java signature uses a type a rule maps (Class R4, Object R23, varargs R7, CharSequence R14,
     boxed values and Optional R5), in which case it is adapted with those rules; a final instance field read through
     an accessor is adapted R24. Optional* as a struct is adapted R5.
   A row that would open a dependency gap (tools/api_differences.py) or a kind mismatch is not added. Every row this
   tool adds is listed in api/jdk-unconfirmed.json until the owning lane confirms it (removes the id after checking the
   signature and behaviour); a lane that finds a row wrong reclassifies it.
3. Each run records the leaf-only types in api/jdk-leaf-types.json. The table is built from committed files only, so
   tools/api_differences.py --write regenerates it (the merge train included) and --check fails when it is stale;
   --table writes it here too. docs/spring/jdk-coverage.md: per package, the owners, done (ported or adapted) against in scope
   (everything not excluded), and the types that exist only in a leaf module, not at their R1 path. Until the JDK
   aggregate re-exports them, --classify makes such a type adapted R1 with a note naming the leaf import path.

    python3 tools/measure_queue.py hold -- python3 tools/jdk_coverage.py --classify --table
"""
import argparse
import collections
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import api_differences  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MAPPING = Path('api/framework/mapping.json')
UNCONFIRMED = Path('api/jdk-unconfirmed.json')
LEAF_TYPES = Path('api/jdk-leaf-types.json')
TABLE = Path('docs/spring/jdk-coverage.md')
AGGREGATES = {'class', 'struct', 'interface', 'enum', 'union'}
D_KEYWORDS = {
    'abstract', 'alias', 'align', 'asm', 'assert', 'auto', 'body', 'bool', 'break', 'byte', 'case', 'cast', 'catch',
    'cdouble', 'cent', 'cfloat', 'char', 'class', 'const', 'continue', 'creal', 'dchar', 'debug', 'default',
    'delegate', 'delete', 'deprecated', 'do', 'double', 'else', 'enum', 'export', 'extern', 'false', 'final',
    'finally', 'float', 'for', 'foreach', 'foreach_reverse', 'function', 'goto', 'idouble', 'if', 'ifloat',
    'immutable', 'import', 'in', 'inout', 'int', 'interface', 'invariant', 'ireal', 'is', 'lazy', 'long', 'macro',
    'mixin', 'module', 'new', 'nothrow', 'null', 'out', 'override', 'package', 'pragma', 'private', 'protected',
    'public', 'pure', 'real', 'ref', 'return', 'scope', 'shared', 'short', 'static', 'struct', 'super', 'switch',
    'synchronized', 'template', 'this', 'throw', 'true', 'try', 'typeid', 'typeof', 'ubyte', 'ucent', 'uint',
    'ulong', 'union', 'unittest', 'ushort', 'version', 'void', 'wchar', 'while', 'with'}
# docs/spring/phase2/jdk-port.md's lane table (owner, 2026-11-26 16:20Z), by package. Where a package is split, every
# lane that owns part of it is listed; the lane table names the classes.
OWNERS = {
    'java.lang': 'sol-framework, sol-boot, sol-jdk-math-regex (Character)',
    'java.util': 'sol-jdk-core, sol-ai, sol-aop, sol-jdk-math-regex, sol-jdk-time-text (Locale)',
    'java.util.function': 'sol-context', 'java.util.stream': 'sol-context',
    'java.util.concurrent': 'sol-jdk-concurrent-io, sol-observability',
    'java.util.concurrent.atomic': 'sol-observability', 'java.util.concurrent.locks': 'sol-observability',
    'java.util.regex': 'sol-jdk-math-regex', 'java.util.random': 'sol-jdk-math-regex',
    'java.math': 'sol-jdk-math-regex', 'java.text': 'sol-template', 'java.io': 'sol-test',
    'java.nio': 'sol-jackson', 'java.nio.charset': 'sol-jackson',
    'java.nio.file': 'sol-data', 'java.nio.file.attribute': 'sol-data', 'java.sql': 'sol-data',
    'java.net': 'sol-web', 'java.util.zip': 'sol-jpa',
    'java.security': 'sol-security', 'java.security.spec': 'sol-security', 'java.security.interfaces': 'sol-security',
    'javax.crypto': 'sol-security', 'javax.crypto.spec': 'sol-security',
    # Packages added after the reconciliation (coordinator, 2026-11-26 16:40Z, c9b6e8ac6).
    'java.lang.annotation': 'sol-framework', 'java.lang.ref': 'sol-boot', 'javax.sql': 'sol-data',
    'java.nio.channels': 'sol-jackson', 'java.util.jar': 'sol-jpa',
    'java.security.cert': 'sol-security', 'javax.security.auth.x500': 'sol-security', 'javax.net': 'sol-security',
    'javax.net.ssl': 'sol-security', 'javax.security.auth': 'sol-security',
    'javax.security.auth.callback': 'sol-security', 'javax.security.auth.login': 'sol-security',
    'javax.security.auth.spi': 'sol-security', 'javax.security.cert': 'sol-security',
    'javax.crypto.interfaces': 'sol-security',
}
OWNER_PREFIXES = {'java.time': 'sol-jdk-time-text'}
# Java types a rule maps (rulebook docs/spring/api-mapping.md), for an adapted member's rules. Collections, streams
# and functional interfaces are not here: flint.java ports them as the same types, so using one is not an adaptation.
OPTIONALS = {'Optional', 'OptionalInt', 'OptionalLong', 'OptionalDouble'}
BOXED = {'Integer', 'Long', 'Short', 'Byte', 'Double', 'Float', 'Boolean', 'Character'}
OBJECT_METHODS = {'equals(Object)', 'hashCode()', 'toString()'}


def d_name(name):
    return name + '_' if name in D_KEYWORDS else name


def d_module(package):
    return 'flint.' + '.'.join(d_name(p) for p in package.split('.'))


def compile_json(root, out):
    """Run dmd -X over the flint.java* sources; the caller holds the measurement queue."""
    sources = sorted(str(p.relative_to(root)) for p in root.glob('framework/java*/source/**/*.d'))
    listed = subprocess.run(['git', '-C', str(root), 'ls-files', '*/source/*.d'], capture_output=True, text=True,
                            check=True).stdout.split()
    roots = sorted({f.split('/source/')[0] + '/source' for f in listed
                    if not f.startswith(('handoff/', 'examples/', 'benchmarks/', 'starters/'))})
    compiler = root / '.tools' / 'dmd2' / 'linux' / 'bin64' / 'dmd'
    args = ['-preview=dip1000', '-o-', '-X', f'-Xf={out}'] + ['-I' + r for r in roots] + sources
    with tempfile.NamedTemporaryFile('w', suffix='.rsp', delete=False) as rsp:
        rsp.write('\n'.join(args))
    run = subprocess.run([str(compiler) if compiler.is_file() else 'dmd', '@' + rsp.name], cwd=root,
                         capture_output=True, text=True)
    Path(rsp.name).unlink()
    if run.returncode:
        raise SystemExit('dmd -X failed:\n' + run.stdout + run.stderr)


class DCode:
    """The flint.java* declarations, from dmd -X."""

    def __init__(self, xjson):
        self.modules = {m['name']: m for m in json.loads(Path(xjson).read_text()) if m.get('name')}
        self._exports = {}

    @staticmethod
    def unwrap(decl):
        """An eponymous template counts as what it wraps: struct Optional(T) is a struct named Optional."""
        if decl.get('kind') == 'template':
            inner = [c for c in decl.get('members', []) if c.get('name') == decl.get('name')]
            if inner:
                found = dict(inner[0])
                found['template'] = True
                return found
        return decl

    def exports(self, module, seen=frozenset()):
        """Public names a module offers, own declarations first, then its public imports (selective or whole)."""
        if module in self._exports:
            return self._exports[module]
        if module in seen or module not in self.modules:
            return {}
        out = {}
        for d in self.modules[module].get('members', []):
            if d['kind'] == 'import':
                if d.get('protection') == 'private':
                    continue
                selective = [s.split('=')[0].strip() for s in d.get('selective', [])] or None
                for name, decl in self.exports(d['name'], seen | {module}).items():
                    if selective is None or name in selective:
                        out.setdefault(name, decl)
            elif d.get('name') and d.get('protection', 'public') in ('public', 'export'):
                out.setdefault(d['name'], self.unwrap(d))
        self._exports[module] = out
        return out

    def type_at(self, java_type):
        """The D aggregate at java_type's R1 canonical path, or None."""
        names = java_type['id'][len(java_type['package']) + 1:].split('.')
        decl = self.exports(d_module(java_type['package'])).get(d_name(names[0]))
        for name in names[1:]:
            decl = next((self.unwrap(c) for c in (decl or {}).get('members', []) if c.get('name') == d_name(name)),
                        None)
        return decl if decl and decl.get('kind') in AGGREGATES else None

    def leaf_only(self, java_type):
        """(module, declaration) of a module below the canonical one that declares the type, when the canonical path
        lacks it; (None, None) otherwise."""
        canonical, name = d_module(java_type['package']), d_name(java_type['id'].rsplit('.', 1)[-1])
        if '.' in java_type['id'][len(java_type['package']) + 1:]:
            return None, None         # a nested type follows its outer type
        for module, m in sorted(self.modules.items()):
            if module.startswith(canonical + '.') and '.internal' not in module:
                for d in m.get('members', []):
                    d = self.unwrap(d)
                    if d.get('name') == name and d.get('kind') in AGGREGATES and d.get('protection', 'public') == 'public':
                        return module, d
        return None, None


def functions_named(decl, name, module_functions):
    """The D functions (and function templates) a Java member of that name could be: aggregate members, then
    module-level functions for an enum's methods (R20)."""
    found = []
    candidates = list(decl.get('members', []))
    if decl.get('kind') == 'enum':
        candidates += module_functions.get(name, [])
    for c in candidates:
        c = DCode.unwrap(c)
        if c.get('name') == name and c.get('kind') in ('function', 'constructor', 'variable', 'enum member', 'alias'):
            found.append(c)
    return found


JAVA_PRIMITIVES = {'boolean': 'b', 'int': 'i', 'long': 'l', 'short': 's', 'byte': 'gh', 'char': 'auw', 'float': 'f',
                   'double': 'd'}
D_PRIMITIVE = re.compile(r'[xyO]*([bilsgauwfdhtkm])')


def d_parameters(function):
    """A D function's parameters, without the trailing file and line defaults that D exceptions add (R8)."""
    params = list(function.get('parameters', []))
    while params and params[-1].get('default', '').endswith(('__FILE__', '__LINE__', '__FILE_FULL_PATH__')):
        params.pop()
    return params


def compatible(java, d_param):
    """Whether a Java parameter type could be this D parameter: primitives must match, String is a char array, and a
    reference is not a D primitive. A template parameter (no mangled type) accepts anything."""
    deco = d_param.get('deco')
    if deco is None:
        return True
    java = re.sub(r'@\w+(\([^)]*\))?\s*', '', java).strip()
    java = re.sub(r'<.*>', '', java).strip()
    primitive = D_PRIMITIVE.fullmatch(deco)
    if java.endswith('[]'):
        # An array needs a D array. Java's char[] is UTF-16, so only a wchar array is the same overload: a
        # const(char)[] parameter is the CharSequence/String overload (R14) and must not also claim char[].
        element = java[:-2].strip()
        array = re.fullmatch(r'[xyO]*A(.*)', deco)
        if not array:
            return False
        if element == 'char':
            return bool(re.fullmatch(r'[xyO]*u', array.group(1)))
        return compatible(element, {'deco': array.group(1)})
    if java in JAVA_PRIMITIVES:
        return bool(primitive) and primitive.group(1) in JAVA_PRIMITIVES[java]
    text = bool(re.fullmatch(r'[xyO]*A[xyO]*[auw]', deco))
    if java == 'String':
        return text or deco.startswith('S')
    # A D string parameter is the String/CharSequence overload: IOException(string message = null, ...) is not
    # IOException(Throwable) (sol-test's find).
    return not primitive and (not text or java == 'CharSequence')


def accepts(function, member):
    """Whether a D function or constructor can stand for the Java member: arity first, then each parameter."""
    if function.get('kind') not in ('function', 'constructor'):
        return not member.get('parameters')
    java = [p.rsplit(' ', 1)[0] if ' ' in p.strip() else p for p in member.get('parameters', [])]
    if '...' in member['signature']:
        return True
    params = d_parameters(function)
    required = sum(1 for p in params if 'default' not in p)
    if not required <= len(java) <= len(params):
        return False
    return all(compatible(j, d) for j, d in zip(java, params))


def simple_types(text):
    return re.findall(r'[A-Za-z_][\w.]*', re.sub(r'@\w+(\([^)]*\))?\s*', '', text or ''))


def member_rules(member, renamed, owner):
    """The rules an adapted member cites, from the Java types in its signature (its own type's name excepted: Optional's
    methods returning Optional adapt nothing); empty when it is ported."""
    if member['signature'] in OBJECT_METHODS:
        return []
    written = [p.rsplit(' ', 1)[0] if ' ' in p.strip() else p for p in member.get('parameters', [])]
    written.append(member.get('type', ''))
    names = {n.rsplit('.', 1)[-1] for text in written for n in simple_types(text)} - {owner}
    rules = set()
    if 'Class' in names:
        rules.add('R4')
    if 'Object' in names:
        rules.add('R23')
    if '...' in member['signature'] or any('...' in p for p in member.get('parameters', [])):
        rules.add('R7')
    if 'CharSequence' in names:
        rules.add('R14')
    if names & BOXED or names & OPTIONALS:
        rules.add('R5')
    if renamed:
        rules.add('R19')
    return sorted(rules, key=lambda r: int(r[1:]))


def type_row(java_type, decl, d_symbol):
    """The row for a type that exists in D, or None when its kind needs a hand classification."""
    kind, d_kind = java_type['kind'], decl['kind']
    if d_kind in api_differences.PORTED_KINDS.get(kind, set()) and kind not in ('record', 'annotation'):
        return {'d': d_symbol, 'status': 'ported'}
    if kind in ('class', 'interface') and d_kind == 'struct' and api_differences.static_only(java_type):
        return {'d': d_symbol, 'status': 'ported'}
    if java_type['id'] in {'java.util.' + o for o in OPTIONALS} and d_kind == 'struct':
        return {'d': d_symbol, 'rules': ['R5'], 'status': 'adapted'}
    if kind == 'enum' and d_kind == 'struct':
        return {'d': d_symbol, 'rules': ['R15'], 'status': 'adapted'}
    if kind == 'record' and d_kind in ('struct', 'class'):
        return {'d': d_symbol, 'rules': ['R11'] if d_kind == 'struct' else ['R11', 'R16'], 'status': 'adapted'}
    if kind == 'annotation' and d_kind == 'struct':
        return {'d': d_symbol, 'rules': ['R2'], 'status': 'adapted'}
    return None


def leaf_note(java_type, module):
    return (f'Import from {module}; {d_module(java_type["package"])} does not re-export it until the JDK aggregate '
            'exists.')


def open_for_classification(classifier, element):
    match = classifier.classify(element)
    return match is None or (match[1]['status'] == 'excluded' and match[1].get('category') == 'deferred'
                             and match[0] != element)


def propose(root, code, manifest, elements):
    """{element id: row} for every deferred or unclassified element that exists in D, and the leaf-only types."""
    classifier = api_differences.Classifier(elements)
    rows, leaf = {}, {}
    module_functions = collections.defaultdict(lambda: collections.defaultdict(list))
    for module, m in code.modules.items():
        for d in m.get('members', []):
            d = DCode.unwrap(d)
            if d.get('kind') == 'function':
                module_functions[module][d['name']].append(d)
    for t in manifest['types']:
        if t.get('visibility') != 'public':
            continue
        decl = code.type_at(t)
        module = d_module(t['package'])
        short = t['id'][len(t['package']) + 1:]
        if decl is None:
            # Until the JDK aggregate exists, a type only a leaf module declares is adapted R1 with a note naming
            # the leaf import path (coordinator, 2026-11-26 16:31Z).
            module, decl = code.leaf_only(t)
            if decl is None:
                continue
            leaf[t['id']] = module
        d_type = module + '.' + '.'.join(d_name(p) for p in short.split('.'))
        if open_for_classification(classifier, t['id']):
            row = type_row(t, decl, d_type)
            if row is None:
                continue          # a kind change needs a rule chosen by hand; members wait for it too
            if t['id'] in leaf:
                row = {'d': d_type, 'rules': sorted(set(row.get('rules', [])) | {'R1'}, key=lambda r: int(r[1:])),
                       'status': 'adapted', 'note': leaf_note(t, module)}
            rows[t['id']] = row
        elif classifier.classify(t['id'])[1]['status'] not in ('ported', 'adapted'):
            continue
        functions = module_functions[module]
        for member in t['members']:
            if member.get('visibility') not in ('public', 'protected'):
                continue
            element = t['id'] + '#' + member['signature']
            if not open_for_classification(classifier, element):
                continue
            constructor = member['kind'] == 'constructor'
            name = 'this' if constructor else d_name(member['name'])
            found = functions_named(decl, name, functions) if not constructor else [
                c for c in decl.get('members', []) if c.get('kind') == 'constructor']
            if constructor and not found and not member.get('parameters'):
                found = [{'kind': 'variable'}]     # an implicit default constructor (struct or class)
            if member['kind'] == 'field':
                fits = [f for f in found if f['kind'] in ('variable', 'enum member', 'function', 'alias')]
            else:
                fits = [f for f in found if accepts(f, member)]
            if not fits:
                continue
            rules = member_rules(member, renamed=name != member['name'] and not constructor,
                                 owner=t['id'].rsplit('.', 1)[-1])
            if member['kind'] == 'field' and 'static' not in member.get('modifiers', []) and any(
                    f['kind'] == 'function' for f in fits):
                rules = sorted(set(rules) | {'R24'}, key=lambda r: int(r[1:]))
            row = {'d': f'{d_type}.{name}'}
            if rules:
                row.update(rules=rules, status='adapted')
            else:
                row['status'] = 'ported'
            rows[element] = row
    return rows, leaf


def safe_rows(root, rows):
    """Drop rows that would open an unlisted dependency gap or kind mismatch."""
    found = api_differences.repos(root)
    elements = found['framework'][0]
    elements.update(rows)
    allowed = json.loads((root / api_differences.DEPENDENCY_BASELINE).read_text()).get('gaps', {})
    for key in api_differences.dependency_gaps(root, found):
        element = key.partition(' -> ')[0]
        if key not in allowed and element in rows:
            rows.pop(element)
            elements.pop(element)
    kinds = json.loads((root / api_differences.KIND_BASELINE).read_text()).get('mismatches', {})
    for key in api_differences.kind_mismatches(root, found):
        if key not in kinds and key in rows:
            rows.pop(key)
    return rows


def write_rows(root, rows):
    """Insert rows into api/framework/mapping.json, each after the pattern line that classified it before (one row
    per line, as the file is written), so lanes adding rows elsewhere don't conflict."""
    path = root / MAPPING
    lines = path.read_text().split('\n')
    classifier = api_differences.Classifier(json.loads(path.read_text())['elements'])
    after = collections.defaultdict(list)
    for key in sorted(rows):
        match = classifier.classify(key)
        after[match[0] if match else None].append(key)
    out = []
    for line in lines:
        out.append(line)
        if line.startswith('"') and '":{' in line and not line.startswith('"elements":'):
            pattern = json.loads(line[:line.index('":{') + 1])
            for key in after.pop(pattern, []):
                out.append(json.dumps(key) + ':' + json.dumps(rows[key], separators=(',', ':')) + ',')
    if after:
        index = next(i for i, line in enumerate(out) if line.startswith('"elements":{')) + 1
        extra = [json.dumps(k) + ':' + json.dumps(rows[k], separators=(',', ':')) + ','
                 for keys in after.values() for k in keys]
        out[index:index] = extra
    path.write_text('\n'.join(out))
    json.loads(path.read_text())


def openjdk_manifest(root):
    pin = next(u for u in json.loads((root / MAPPING).read_text())['upstream'] if u.startswith('openjdk@'))
    return json.loads((root / 'api' / 'upstream' / f'openjdk-{pin.partition("@")[2]}.json').read_text())


def table_text(root):
    """docs/spring/jdk-coverage.md from committed files only (the mapping, the manifest, api/jdk-unconfirmed.json and
    api/jdk-leaf-types.json), so tools/api_differences.py --write regenerates it wherever it regenerates the Java
    differences page, including the merge train, and --check fails when it is stale."""
    leaf = json.loads((root / LEAF_TYPES).read_text())['types'] if (root / LEAF_TYPES).is_file() else {}
    return render_table(coverage(root, openjdk_manifest(root), leaf), leaf)


def coverage(root, manifest, leaf):
    elements = json.loads((root / MAPPING).read_text())['elements']
    classifier = api_differences.Classifier(elements)
    unconfirmed = set(json.loads((root / UNCONFIRMED).read_text())['ids']) if (root / UNCONFIRMED).is_file() else set()
    table = collections.defaultdict(lambda: collections.Counter())
    for t in manifest['types']:
        if t.get('visibility') != 'public':
            continue
        package = t['package']
        for element, is_type in [(t['id'], True)] + [(t['id'] + '#' + m['signature'], False) for m in t['members']
                                                      if m.get('visibility') in ('public', 'protected')]:
            match = classifier.classify(element)
            status = 'unclassified' if match is None else match[1]['status']
            if status == 'excluded' and match[1].get('category') != 'deferred':
                table[package]['excluded'] += 1
                continue
            unit = 'types' if is_type else 'members'
            table[package][unit] += 1
            if status in ('ported', 'adapted'):
                table[package][unit + ' done'] += 1
                table[package]['unconfirmed'] += element in unconfirmed
        table[package]['leaf'] += t['id'] in leaf
    return table


def owner_of(package):
    if package in OWNERS:
        return OWNERS[package]
    if package.endswith('.spi'):
        # Every *.spi package goes to the owner of its parent package (c9b6e8ac6).
        return owner_of(package[:-len('.spi')])
    return next((o for p, o in OWNER_PREFIXES.items() if package == p or package.startswith(p + '.')), '')


def render_table(table, leaf):
    def pct(done, total):
        return f'{100 * done / total:.0f}%' if total else '-'
    scoped = {p: c for p, c in table.items() if c['types'] or c['members']}
    total = collections.Counter()
    for c in scoped.values():
        total.update(c)
    lines = [
        '# JDK coverage',
        '',
        'Generated by `python3 tools/jdk_coverage.py --table` from api/framework/mapping.json and the pinned OpenJDK '
        '21.0.13 manifest. **Done** is ported or adapted; **in scope** is every public type and public or protected '
        'member not excluded (deferred counts as in scope). Owners are from '
        '[the lane table](phase2/jdk-port.md#lanes). **Unconfirmed** rows were classified by the tool from the D code '
        'that exists (name, arity and parameter kinds) and wait for the owning lane to confirm them (api/jdk-unconfirmed.json). '
        '**Leaf only** types exist in D but not at their R1 path: `import flint.java.x : T` fails, so they are '
        'adapted R1 with a note naming the leaf module until the JDK aggregate (sol-jdk-core) re-exports them.',
        '',
        f'Overall: types {total["types done"]}/{total["types"]} ({pct(total["types done"], total["types"])}), '
        f'members {total["members done"]}/{total["members"]} ({pct(total["members done"], total["members"])}).',
        '',
        '| Package | Owners | Types done / in scope | Members done / in scope | Members % | Unconfirmed | Leaf only |',
        '|---|---|---|---|---|---|---|',
    ]
    for package in sorted(scoped, key=lambda p: (not owner_of(p), p)):
        c = scoped[package]
        lines.append(f'| `{package}` | {owner_of(package) or "(none yet)"} | {c["types done"]} / {c["types"]} | '
                     f'{c["members done"]} / {c["members"]} | {pct(c["members done"], c["members"])} | '
                     f'{c["unconfirmed"] or ""} | {c["leaf"] or ""} |')
    if leaf:
        lines += ['', '## Types that exist only in a leaf module', '',
                  'Each is adapted R1 with a note naming its leaf module until the JDK aggregate re-exports it '
                  '(coordinator, 2026-11-26 16:31Z).', '']
        lines += [f'- `{t}`: declared in `{m}`' for t, m in sorted(leaf.items())]
    return '\n'.join(lines) + '\n'


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument('--root', type=Path, default=ROOT)
    p.add_argument('--xjson', type=Path, help='an existing dmd -X output (default: run dmd)')
    p.add_argument('--classify', action='store_true', help='add rows for D code that exists but is not classified')
    p.add_argument('--table', action='store_true', help=f'write {TABLE}')
    a = p.parse_args(argv)
    root = a.root
    manifest = openjdk_manifest(root)
    xjson = a.xjson
    if xjson is None:
        xjson = Path(tempfile.mkdtemp()) / 'flint-java.json'
        compile_json(root, xjson)
    code = DCode(xjson)
    elements = json.loads((root / MAPPING).read_text())['elements']
    rows, leaf = propose(root, code, manifest, elements)
    if a.classify:
        rows = safe_rows(root, rows)
        write_rows(root, rows)
        path = root / UNCONFIRMED
        previous = json.loads(path.read_text())['ids'] if path.is_file() else []
        path.write_text(json.dumps({
            'note': 'Rows tools/jdk_coverage.py --classify added from the D code that exists (name, arity, parameter kinds). The '
                    'owning lane confirms each (signature and behaviour) and removes its id, or reclassifies it.',
            'ids': sorted(set(previous) | set(rows))}, indent=1) + '\n')
        print(f'{len(rows)} rows added; {len(leaf)} types exist only in a leaf module', file=sys.stderr)
    else:
        print(f'{len(rows)} rows would be added; {len(leaf)} types exist only in a leaf module', file=sys.stderr)
    (root / LEAF_TYPES).write_text(json.dumps({
        'note': 'JDK types that exist only in a leaf module, not at their R1 path (tools/jdk_coverage.py, from dmd -X). '
                'The table reads this file, so it regenerates without a compiler.',
        'types': dict(sorted(leaf.items()))}, indent=1) + '\n')
    if a.table:
        (root / TABLE).write_text(table_text(root))
    return 0


if __name__ == '__main__':
    sys.exit(main())
