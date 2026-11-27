#!/usr/bin/env python3
"""The porter's R6 accessor shape: trivial Java getters and setters as D member functions (porter-plan.md, M2b).

A trivial getter is a no-argument instance method whose body is `return this.f;` (or `return f;`) for an instance
field `f` of its own class; a trivial setter is a one-argument instance method whose body is `this.f = p;` for its
parameter `p`. For each one this module derives, by fixed rules and without reading the hand port:

  - the D declaration: the Java name (R19 for D keywords), its visibility, `override` for `@Override`, `final` for a
    Java `final` method, the D type through the mapping rows and the rulebook (R5 nullable values, R10 collections,
    R23 `Object`), and the function attributes the type's port plan records for its accessors (`"accessors"`:
    `{"getter": [...], "setter": [...]}`, none by default);
  - the body, reading or assigning the field under its Java name;
  - the mapping row: `ported`, or `adapted` with the rules the type mapping applied.

`--compare` offers every trivial accessor of a hand-ported class whose row is ported or adapted with a D symbol (the
corpus of porter_gate.corpus()). Each derived member replaces the hand member in a copy of the module that declares
it, and tools/port-spring/gate/porter_describe.d prints the type's API on DMD and on LDC. The element is reproduced
when its member lines are identical on both compilers and the derived row matches the hand row. A body that does not
compile against the hand class (a renamed field, a converted type) is compared with a `assert(0)` body, so the API
still counts, and is reported as a body divergence. `--yield` counts the deferred trivial accessors the rules derive.

    python3 tools/port-spring/accessors.py --helper .flint/port-spring/flint-port-spring \\
        --cache "$PWD/.flint/cache/api" --compare [--json artifacts/porter/accessors.json]
"""
import argparse
import collections
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from api_differences import Classifier, erase_type  # noqa: E402
import porter_gate as gate  # noqa: E402

GETTER = re.compile(r'\{\s*return\s+(?:this\.)?(\w+)\s*;\s*\}$')
SETTER = re.compile(r'\{\s*this\.(\w+)\s*=\s*(\w+)\s*;\s*\}$')
PRIMITIVES = {'boolean': 'bool', 'byte': 'byte', 'short': 'short', 'int': 'int', 'long': 'long', 'float': 'float',
              'double': 'double'}
BOXED = {'Boolean': 'bool', 'Byte': 'byte', 'Short': 'short', 'Integer': 'int', 'Long': 'long', 'Float': 'float',
         'Double': 'double'}
COLLECTIONS = {'java.util.List': 'List', 'java.util.Set': 'Set', 'java.util.Collection': 'Collection'}
# Identifiers D reserves (R19): its keywords, plus names Java allows and D rejects.
D_KEYWORDS = set('''abstract alias align asm assert auto body bool break byte case cast catch cdouble cent cfloat char
class const continue creal dchar debug default delegate delete deprecated do double else enum export extern false final
finally float for foreach foreach_reverse function goto idouble if ifloat immutable import in inout int interface
invariant ireal is lazy long macro mixin module new nothrow null out override package pragma private protected public
pure real ref return scope shared short static struct super switch synchronized template this throw true try typeid
typeof ubyte ucent uint ulong union unittest ushort version void wchar while with'''.split())
STRUCTURED = ('struct', 'enum', 'uda')
# The plan a deferred class gets until a lane writes its entry: an erased, non-final class.
DEFAULT_PLAN = {'kind': 'class'}


class Unsupported(Exception):
    pass


def d_name(name):
    name = name.replace('$', '_')
    return name + '_' if name in D_KEYWORDS else name


# ---- the Java side ----------------------------------------------------------------------------------------------

class Universe:
    """Every pinned manifest's types, every exact mapped type row, and every port plan entry."""

    def __init__(self, cache):
        self.cache = Path(cache)
        self.pins = {(u['project'], u['version']): u for u in gate.load_json(ROOT / 'api' / 'upstreams.json')['upstreams']}
        self.mappings = {p.parent.name: gate.load_json(p)['elements'] for p in (ROOT / 'api').glob('*/mapping.json')}
        self.classifiers = {repo: Classifier(elements) for repo, elements in self.mappings.items()}
        self.types = {}      # Java type id -> (project, tag, manifest type)
        for path in sorted((ROOT / 'api' / 'upstream').glob('*.json')):
            manifest = gate.load_json(path)
            for t in manifest['types']:
                self.types.setdefault(t['id'], (manifest['project'], manifest['version'], t))
        self.by_simple = collections.defaultdict(list)
        for type_id in self.types:
            self.by_simple[type_id.rsplit('.', 1)[-1]].append(type_id)
        self.plans = {}
        for path in sorted((ROOT / 'api' / 'port-plan').glob('*.json')):
            self.plans.update(gate.load_json(path)['types'])
        self.rows = {}       # Java type id -> exact ported/adapted row with a D symbol
        for repo, elements in self.mappings.items():
            for key, row in elements.items():
                if '#' not in key and row.get('status') in ('ported', 'adapted') and '.' in row.get('d', ''):
                    self.rows.setdefault(key, row)
        self._index = {}

    def row(self, project, tag, element):
        repo = self.pins[(project, tag)]['repo']
        found = self.classifiers[repo].classify(element)
        return found[1] if found and found[0] == element else None

    def source(self, project, tag, type_id):
        """(Java file, nested names) for a type: its own file, or its outer type's."""
        root = self.cache / f'{project}-{tag}'
        if root not in self._index:
            by_name = collections.defaultdict(list)
            for directory, dirs, files in os.walk(root):
                dirs.sort()
                rel = os.path.relpath(directory, root) + os.sep
                if f'{os.sep}src{os.sep}test{os.sep}' in os.sep + rel or rel.startswith('test' + os.sep) \
                        or f'{os.sep}testFixtures{os.sep}' in os.sep + rel:
                    continue
                for file in sorted(files):
                    if file.endswith('.java'):
                        by_name[file[:-5]].append(os.path.join(directory, file))
            self._index[root] = by_name
        parts = type_id.split('.')
        for cut in range(len(parts), 0, -1):
            suffix = os.sep + os.sep.join(parts[:cut]) + '.java'
            found = [p for p in self._index[root].get(parts[cut - 1], ()) if p.endswith(suffix)]
            if len(found) == 1:
                return found[0], parts[cut:]
            if found:
                raise Unsupported(f'{len(found)} candidate sources')
        raise Unsupported('no pinned source file')


def describe_java(helper, path):
    result = subprocess.run([str(helper), '--describe', path], capture_output=True, text=True, check=False)
    if result.returncode:
        raise Unsupported('the helper cannot read the source: ' + (result.stderr.strip().splitlines() or ['?'])[-1]
                          .replace(str(path), '<source>')[:160])
    return json.loads(result.stdout)


class Scope:
    """Resolves simple Java type names at one class: its nested types, imports, package and java.lang."""

    def __init__(self, universe, tree, chain):
        self.universe, self.package = universe, tree['package']
        self.imports, self.wildcards = {}, []
        for i in tree['referenceImports']:
            if i['static']:
                continue
            if i['wildcard']:
                self.wildcards.append(i['path'])
            else:
                self.imports[i['path'].rsplit('.', 1)[-1]] = i['path']
        # chain: [(type id, declaration)] from the top-level type to this one.
        self.nested = {}
        for type_id, decl in chain:
            for inner in decl['types']:
                self.nested[inner['name']] = f'{type_id}.{inner["name"]}'
        self.type_variables = set()
        for _, decl in chain:
            for parameter in decl.get('typeParameters') or ():
                self.type_variables.add(re.split(r'\s', parameter.strip())[0])

    def resolve(self, name):
        head, _, rest = name.partition('.')
        candidates = []
        if head in self.nested:
            candidates.append(self.nested[head])
        if head in self.imports:
            candidates.append(self.imports[head])
        candidates.append(f'{self.package}.{head}')
        candidates += [f'{w}.{head}' for w in self.wildcards]
        candidates += [f'java.lang.{head}', head]
        for candidate in candidates:
            full = candidate + ('.' + rest if rest else '')
            if full in self.universe.types or full in self.universe.rows:
                return full
        raise Unsupported(f'type {name} does not resolve to a pinned type')


def strip_annotations(java):
    nullable = bool(re.search(r'@(?:[\w.]+\.)?Nullable\b', java))
    return re.sub(r'@[\w.]+(\([^)]*\))?\s*', '', java).strip(), nullable


def split_arguments(text):
    parts, depth, start = [], 0, 0
    for index, char in enumerate(text):
        if char == '<':
            depth += 1
        elif char == '>':
            depth -= 1
        elif char == ',' and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    parts.append(text[start:].strip())
    return [p for p in parts if p]


def d_type(java, nullable, scope, rules, element=False):
    """The D spelling of a Java type; adds the rules it applies to `rules`."""
    java, inner_nullable = strip_annotations(java)
    java = re.sub(r'^\?\s+(extends|super)\s+', '', java).strip()
    if java == '?':
        raise Unsupported('unbounded wildcard')
    if java.endswith('[]'):
        return d_type(java[:-2], False, scope, rules, element=True) + '[]'
    if java in PRIMITIVES:
        return PRIMITIVES[java]
    if java == 'char':
        raise Unsupported('no rule maps Java char')
    base, _, arguments = java.partition('<')
    arguments = split_arguments(arguments[:-1]) if arguments else []
    if base in scope.type_variables:
        raise Unsupported(f'type variable {base}')
    full = scope.resolve(base)
    if full == 'java.lang.String':
        if nullable and not element:
            rules.add('R5')
            return 'Nullable!string'
        return 'string'
    if full.startswith('java.lang.') and base in BOXED:
        if element:
            return BOXED[base]
        rules.add('R5')
        return f'Nullable!{BOXED[base]}'
    if full == 'java.lang.Object':
        rules.add('R23')
        return 'Any'
    if full in COLLECTIONS:
        if len(arguments) != 1:
            raise Unsupported(f'raw {base}')
        rules.add('R10')
        return f'{COLLECTIONS[full]}!({d_type(arguments[0], False, scope, rules, element=True)})'
    if full == 'java.util.Map':
        if len(arguments) != 2:
            raise Unsupported('raw Map')
        rules.add('R10')
        key = d_type(arguments[0], False, scope, rules, element=True)
        value = d_type(arguments[1], False, scope, rules, element=True)
        return f'Map!({key}, {value})'
    if full == 'java.util.Optional':
        if len(arguments) != 1:
            raise Unsupported('raw Optional')
        rules.add('R5')
        return f'Optional!({d_type(arguments[0], False, scope, rules, element=True)})'
    if full == 'java.lang.Class':
        raise Unsupported('Class<?> needs a plan choice (R4: ClassRef or RuntimeClassRef)')
    if arguments:
        raise Unsupported(f'generic type {base}<...>')
    row = scope.universe.rows.get(full)
    if row is None:
        raise Unsupported(f'type {full} is not mapped to a D symbol')
    plan = scope.universe.plans.get(full, {})
    if plan.get('storage') not in (None, 'erased'):
        raise Unsupported(f'type {full} has templated storage')
    target = row['d'].rsplit('.', 1)[1]
    if nullable and not element and plan.get('kind') in STRUCTURED:
        rules.add('R5')
        return f'Nullable!({target})'
    return target


# ---- the corpus ---------------------------------------------------------------------------------------------------

def accessors_of(decl):
    """(kind, method, field declaration) for each trivial getter and setter of a class declaration."""
    fields = {}
    for f in decl['fields']:
        if 'static' not in f['modifiers']:
            for d in f['declarators']:
                fields[d['name']] = (f, d)
    found = []
    for method in decl['methods']:
        if 'static' in method['modifiers'] or not method['body'] or method.get('typeParameters'):
            continue
        body = ' '.join(method['body'].split())
        params = method['parameters']
        match = GETTER.fullmatch(body) if not params else SETTER.fullmatch(body) if len(params) == 1 else None
        if not match or match.group(1) not in fields:
            continue
        if params and (match.group(2) != params[0]['name'] or params[0].get('variadic')):
            continue
        if not params and method['type'] == 'void':
            continue
        found.append(('getter' if not params else 'setter', method, fields[match.group(1)]))
    return found


def signature(method):
    return method['name'] + '(' + ','.join(erase_type(p['type']) for p in method['parameters']) + ')'


def corpus(universe, helper, statuses=('ported', 'adapted'), jobs=None):
    """Every trivial accessor of a mapped class, with its element row; and the types that could not be read."""
    elements, skipped = [], collections.Counter()
    for job in jobs if jobs is not None else gate.corpus():
        if job['kind'] != 'class':
            continue
        try:
            path, nested = universe.source(job['project'], job['tag'], job['type'])
            tree = describe_java(helper, path)
        except Unsupported as problem:
            skipped[str(problem)] += 1
            continue
        decl, type_id = tree['type'], job['type'][:len(job['type']) - sum(len(n) + 1 for n in nested)]
        chain = [(type_id, decl)]
        for name in nested:
            decl = next(t for t in decl['types'] if t['name'] == name)
            type_id += '.' + name
            chain.append((type_id, decl))
        scope = Scope(universe, tree, chain)
        for kind, method, (field, declarator) in accessors_of(decl):
            element = job['type'] + '#' + signature(method)
            row = universe.row(job['project'], job['tag'], element)
            if row is None or row['status'] not in statuses or (row['status'] != 'excluded' and not row.get('d')):
                continue
            elements.append({'element': element, 'kind': kind, 'job': job, 'method': method, 'field': field,
                             'declarator': declarator, 'scope': scope, 'row': row, 'class': decl})
    return elements, skipped


def deferred_jobs(universe):
    """Every public class of a pinned, mapped upstream (yield: its deferred trivial accessors)."""
    jobs = []
    for path in sorted((ROOT / 'api' / 'upstream').glob('*.json')):
        manifest = gate.load_json(path)
        pin = universe.pins.get((manifest['project'], manifest['version']))
        if pin is None or pin.get('repo') not in universe.classifiers or pin.get('signatures_only'):
            continue
        for t in manifest['types']:
            if t.get('visibility') == 'public' and t['kind'] == 'class':
                jobs.append({'project': manifest['project'], 'tag': manifest['version'], 'type': t['id'],
                             'kind': 'class'})
    return jobs


def parent_of(universe, type_id):
    """The Java superclass's type id, from the pinned manifests (same package first, then a unique simple name)."""
    entry = universe.types.get(type_id)
    extends = [e for e in (entry[2].get('extends') or ()) if e != 'Object'] if entry else []
    if not extends or entry[2]['kind'] != 'class':
        return None
    name = re.sub(r'<.*', '', extends[0])
    package = entry[2].get('package', type_id.rsplit('.', 1)[0])
    if f'{package}.{name}' in universe.types:
        return f'{package}.{name}'
    if name in universe.types:
        return name
    found = universe.by_simple.get(name.rsplit('.', 1)[-1], [])
    found = [f for f in found if f.endswith('.' + name)]
    return found[0] if len(found) == 1 else None


def overrides(universe, type_id, sig):
    """Whether a superclass declares the same non-private instance method (D needs `override`)."""
    seen, parent = set(), parent_of(universe, type_id)
    while parent and parent not in seen:
        seen.add(parent)
        for member in universe.types[parent][2].get('members', ()):
            if member.get('kind') == 'method' and member.get('signature') == sig \
                    and member.get('visibility') in ('public', 'protected', 'package') \
                    and 'static' not in member.get('modifiers', ()):
                return True
        parent = parent_of(universe, parent)
    return False


# ---- derivation ---------------------------------------------------------------------------------------------------

def derive(item, universe, default_plan=None):
    """{'text', 'safe_text', 'name', 'arity', 'status', 'rules'} for one accessor, or Unsupported. A type with no
    plan entry takes `default_plan` when given (yield: a lane writes the entry when it ports the type)."""
    method, job, scope = item['method'], item['job'], item['scope']
    plan = universe.plans.get(job['type'], default_plan)
    if plan is None:
        raise Unsupported('the type has no port plan entry')
    if plan.get('storage') not in (None, 'erased'):
        raise Unsupported('the type has templated storage')
    rules = set()
    name = d_name(method['name'])
    if name != method['name']:
        rules.add('R19')
    visibility = next((v for v in ('public', 'protected') if v in method['modifiers']), None)
    if visibility is None:
        raise Unsupported('package-private or private accessor')
    method_nullable = any(a['name'] == 'Nullable' for a in method['annotations'])
    field_nullable = any(a['name'] == 'Nullable' for a in item['field']['annotations']) \
        or strip_annotations(item['field']['type'])[1]
    for annotation in method['annotations']:
        if annotation['name'] not in ('Override', 'Nullable', 'SuppressWarnings'):
            raise Unsupported(f'annotation @{annotation["name"]}')
    prefix = [visibility]
    if plan['kind'] not in STRUCTURED and overrides(universe, item['job']['type'], signature(method)):
        prefix.append('override')
    if 'final' in method['modifiers'] and plan['kind'] not in ('final class', 'struct'):
        prefix.append('final')
    attributes = list(plan.get('accessors', {}).get(item['kind'], ()))
    field = d_name(item['declarator']['name'])
    if any(d_name(m['name']) == field for m in item['class']['methods']):
        field += '_'  # D can't declare a field and a method with one name (R24's private `name_`)
    if item['kind'] == 'getter':
        dtype = d_type(method['type'] + (method.get('dimensions') or ''), method_nullable or field_nullable,
                       scope, rules)
        head = f'{" ".join(prefix)} {dtype} {name}()'
        body = f'return this.{field};'
    else:
        parameter = method['parameters'][0]
        nullable = any(a['name'] == 'Nullable' for a in parameter['annotations']) or field_nullable
        for annotation in parameter['annotations']:
            if annotation['name'] not in ('Nullable',):
                raise Unsupported(f'parameter annotation @{annotation["name"]}')
        dtype = d_type(parameter['type'], nullable, scope, rules)
        pname = d_name(parameter['name'])
        head = f'{" ".join(prefix)} void {name}({dtype} {pname})'
        body = f'this.{field} = {pname};'
    suffix = (' ' + ' '.join(attributes)) if attributes else ''
    text = f'{head}{suffix}\n{{\n    {body}\n}}'
    safe = f'{head}{suffix}\n{{\n    assert(0);\n}}'
    rules = sorted(rules, key=lambda r: int(r[1:]))
    return {'text': text, 'safe_text': safe, 'name': name, 'arity': len(method['parameters']),
            'status': 'adapted' if rules else 'ported', 'rules': rules}


# ---- splicing into the hand class ---------------------------------------------------------------------------------

def member_spans(source, type_name, name, arity):
    """[(start, end, indent)] for each member function `name` with `arity` parameters in top-level type `type_name`."""
    spans = gate.declarations(source)
    if type_name not in spans:
        raise Unsupported(f'the hand module declares no top-level {type_name}')
    start, end = spans[type_name]
    tokens = [(t, o) for t, o in gate.scan(source) if start <= o < end]
    first = next(i for i, (t, _) in enumerate(tokens) if t == '{')
    found, depth, paren, boundary = [], 0, 0, first
    i = first
    while i < len(tokens):
        text = tokens[i][0]
        if text == '{':
            depth += 1
            if depth == 1:
                boundary = i
        elif text == '}':
            depth -= 1
            if depth == 1:
                boundary = i
            if depth == 0:
                break
        elif text in '([':
            paren += 1
        elif text in ')]':
            paren -= 1
        elif depth == 1 and paren == 0 and text in (';', ':'):
            boundary = i
        elif (depth == 1 and paren == 0 and text == name and i + 1 < len(tokens) and tokens[i + 1][0] == '('
              and tokens[i - 1][0] not in ('.', 'new', '=', 'return')):
            close = gate.matching(tokens, i + 1)
            inside = tokens[i + 2:close]
            count, level = (1 if inside else 0), 0
            for t, _ in inside:
                level += t in '([{'
                level -= t in ')]}'
                count += t == ',' and level == 0
            k = close + 1
            while k < len(tokens) and tokens[k][0] not in ('{', ';', '=>'):
                k = gate.matching(tokens, k) + 1 if tokens[k][0] in '([' else k + 1
            if k >= len(tokens):
                break
            if tokens[k][0] == '{':
                last = gate.matching(tokens, k)
            elif tokens[k][0] == '=>':
                last = k
                while tokens[last][0] != ';':
                    last = gate.matching(tokens, last) + 1 if tokens[last][0] in '([{' else last + 1
            else:
                last = k
            if count == arity:
                begin = tokens[boundary + 1][1]
                line = gate.line_start(source, begin)
                found.append((begin, tokens[last][1] + 1, source[line:begin] if not source[line:begin].strip() else ''))
            i = last + 1
            boundary = last
            continue
        i += 1
    return found


def indented(text, indent):
    lines = text.split('\n')
    return '\n'.join([lines[0]] + [(indent + line) if line else line for line in lines[1:]])


def splice(source, type_name, changes):
    """The source with each (name, arity, text) member replaced; raises Unsupported on an ambiguous member."""
    edits = []
    for name, arity, text in changes:
        spans = member_spans(source, type_name, name, arity)
        if len(spans) != 1:
            raise Unsupported(f'the hand class has {len(spans)} members {name} with {arity} parameter(s)')
        begin, end, indent = spans[0]
        edits.append((begin, end, indented(text, indent)))
    for begin, end, text in sorted(edits, reverse=True):
        source = source[:begin] + text + source[end:]
    return source


# ---- comparison ---------------------------------------------------------------------------------------------------

def describe(compiler, overlay, roots, symbols, scratch):
    """porter_gate.describe, keeping the whole diagnostic so first_error can name the cause."""
    probe = scratch / f'accessor_probe_{compiler}.d'
    lines = ['module accessor_probe;', 'import porter_describe : describe;']
    lines += [f'static import {m};' for m in sorted({s.rsplit('.', 1)[0] for s in symbols})]
    lines += [f'pragma(msg, "PORTER-BEGIN {s}\\n" ~ describe!({s}) ~ "PORTER-END");' for s in symbols]
    probe.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    includes = ([f'-I{overlay}'] if overlay else []) + [f'-I{r}' for r in roots] + [f'-I{gate.DESCRIBER}']
    result = subprocess.run([compiler, '-o-', '-d', '-preview=dip1000', *includes, str(probe)], cwd=scratch,
                            capture_output=True, text=True, env=gate.compiler_env(), check=False)
    if result.returncode:
        raise ValueError(result.stderr)
    found = dict(re.findall(r'PORTER-BEGIN (\S+)\n(.*?)PORTER-END', result.stderr + result.stdout, re.S))
    missing = [s for s in symbols if s not in found]
    if missing:
        raise ValueError('probe printed no description for ' + ', '.join(missing))
    return found


def first_error(diagnostics):
    errors = [line.strip() for line in diagnostics.splitlines() if 'Error:' in line
              and not re.search(r'CTFE failed|template instance|error instantiating', line)] \
        or [line.strip() for line in diagnostics.splitlines() if 'Error:' in line]
    return re.sub(r'^\S+?\(\d+(,\d+)?\): ', '', errors[0])[:300] if errors else diagnostics[-300:]


def attributes_of(line):
    """The function attributes a description line shows, less what the module and class decide."""
    tail = line[line.rfind(')') + 1:].split()
    return [a for a in tail if a not in ('@safe', 'virtual', 'final', 'static', 'abstract', 'deprecated')]


def member_lines(description, type_name, name):
    return [line for line in description.splitlines() if line.startswith(f'{type_name}.{name}#')]


def compare(universe, helper, scratch, compilers=None, log=None, only=None):
    compilers = compilers or gate.COMPILERS
    jobs = [j for j in gate.corpus() if not only or j['type'] in only]
    items, skipped = corpus(universe, helper, jobs=jobs)
    results = {}
    derived = {}
    for item in items:
        try:
            derived[item['element']] = derive(item, universe)
        except Unsupported as problem:
            results[item['element']] = {'result': 'unsupported', 'reason': str(problem)}
    index = gate.module_index(gate.import_roots())
    by_package = collections.defaultdict(list)
    for item in items:
        if item['element'] not in derived:
            continue
        module = item['job']['module']
        owners = [gate.package_of(p) for _, p in index.get(module, ())]
        if not owners or owners[0] is None:
            results[item['element']] = {'result': 'diverged', 'kind': 'api', 'reason': f'no package declares {module}'}
            continue
        by_package[owners[0]].append(item)
    for package, group in sorted(by_package.items()):
        if log:
            log(f':{package}: {len(group)} accessors')
        compare_package(package, group, derived, results, index, scratch, compilers)
    for item in items:
        result = results.get(item['element'])
        if result is None or result['result'] == 'unsupported':
            continue
        d, row = derived[item['element']], item['row']
        if (row['status'], row.get('rules', [])) != (d['status'], d['rules']):
            mismatch = f"row: hand {row['status']} {row.get('rules', [])}, porter {d['status']} {d['rules']}"
            diverge(results, item['element'], 'mapping', mismatch)
    return items, results, derived, skipped


def diverge(results, element, kind, reason):
    current = results.get(element)
    if current is None or current['result'] == 'reproduced':
        results[element] = {'result': 'diverged', 'kind': kind, 'reason': reason}
    elif current['result'] == 'diverged' and kind not in current['kind'].split('+'):
        current['kind'] += '+' + kind
        current['reason'] += ' | ' + reason


def compare_package(package, group, derived, results, index, scratch, compilers):
    roots = gate.import_paths(package)
    symbols = sorted({item['job']['symbol'] for item in group})
    declaring = gate.locate(roots, symbols, scratch)
    files = {}
    for item in group:
        symbol = item['job']['symbol']
        places = [(r, p) for r, p in index.get(declaring.get(symbol, ''), ()) if r in roots]
        if not places:
            results[item['element']] = {'result': 'diverged', 'kind': 'api',
                                        'reason': 'the hand type is not declared in the package\'s import paths'}
            continue
        files.setdefault(places[0], []).append(item)
    hand = {}
    for compiler in compilers:
        try:
            hand[compiler] = describe(compiler, None, roots, symbols, scratch)
        except ValueError:
            hand[compiler] = {}
            for symbol in symbols:
                try:
                    hand[compiler].update(describe(compiler, None, roots, [symbol], scratch))
                except ValueError:
                    pass

    hand_attributes = {}

    def attempt(edits, use_safe):
        """Splice `edits` (items) into an overlay; {element: (ok, reason)} from the descriptions, or None."""
        overlay = scratch / 'overlay' / package
        if overlay.exists():
            subprocess.run(['rm', '-rf', str(overlay)], check=True)
        touched = collections.defaultdict(list)
        for (root, path), file_items in files.items():
            for item in file_items:
                if item in edits:
                    touched[(root, path)].append(item)
        outcome = {}
        for (root, path), file_items in touched.items():
            text = path.read_text(encoding='utf-8')
            by_type = collections.defaultdict(list)
            for item in file_items:
                by_type[item['job']['symbol'].rsplit('.', 1)[1]].append(item)
            for type_name, type_items in by_type.items():
                changes = [(derived[i['element']]['name'], derived[i['element']]['arity'],
                            derived[i['element']]['safe_text' if i['element'] in use_safe else 'text'])
                           for i in type_items]
                try:
                    text = splice(text, type_name, changes)
                except Unsupported as problem:
                    for i in type_items:
                        outcome[i['element']] = (None, str(problem))
            destination = overlay / path.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text, encoding='utf-8')
        live = [i for i in edits if i['element'] not in outcome]
        wanted = sorted({i['job']['symbol'] for i in live})
        if not wanted:
            return outcome
        for compiler in compilers:
            try:
                spliced = describe(compiler, overlay, roots, wanted, scratch)
            except ValueError as problem:
                if len(live) > 1:
                    return None
                outcome[live[0]['element']] = (False, f'{compiler}: does not compile: ' + first_error(str(problem)))
                return outcome
            for item in live:
                symbol = item['job']['symbol']
                type_name, d = symbol.rsplit('.', 1)[1], derived[item['element']]
                if symbol not in hand[compiler]:
                    outcome[item['element']] = (False, f'{compiler}: the hand type does not compile alone')
                    continue
                before = member_lines(hand[compiler][symbol], type_name, d['name'])
                if compiler == compilers[0] and len(before) == 1:
                    hand_attributes[item['element']] = attributes_of(before[0])
                after = member_lines(spliced[symbol], type_name, d['name'])
                if before != after and item['element'] not in outcome:
                    outcome[item['element']] = (False, f'{compiler}: hand `{" / ".join(before)}` porter '
                                                       f'`{" / ".join(after)}`')
        for item in live:
            outcome.setdefault(item['element'], (True, None))
        return outcome

    def settle(edits, use_safe):
        """Outcomes for `edits`, bisecting whenever one splice keeps the others from compiling."""
        outcome = attempt(edits, use_safe)
        if outcome is not None:
            return outcome
        if len(edits) == 1:
            return {edits[0]['element']: (False, 'does not compile')}
        middle = len(edits) // 2
        merged = settle(edits[:middle], use_safe)
        merged.update(settle(edits[middle:], use_safe))
        return merged

    every = [item for file_items in files.values() for item in file_items]
    outcome = settle(every, set())
    retry = [i for i in every if outcome[i['element']][0] is False and 'does not compile' in outcome[i['element']][1]]
    body_problem = {}
    if retry:
        again = settle(retry, {i['element'] for i in retry})
        for item in retry:
            if again[item['element']][0] is not None:
                body_problem[item['element']] = outcome[item['element']][1]
                outcome[item['element']] = again[item['element']]
    for item in every:
        ok, reason = outcome[item['element']]
        element = item['element']
        if ok is None:
            results[element] = {'result': 'unsupported', 'reason': reason}
        elif ok:
            results[element] = {'result': 'reproduced'}
        else:
            results[element] = {'result': 'diverged', 'kind': 'api', 'reason': reason}
        if element in hand_attributes:
            results[element]['handAttributes'] = hand_attributes[element]
        if element in body_problem:
            diverge(results, element, 'body', 'the derived body does not compile against the hand class: '
                    + body_problem[element][-300:])


def summarise(items, results, skipped):
    totals = collections.Counter()
    by_kind = collections.defaultdict(collections.Counter)
    reasons = collections.Counter()
    divergences = collections.Counter()
    for item in items:
        r = results.get(item['element'], {'result': 'unsupported', 'reason': 'not compared'})
        totals['elements'] += 1
        totals[r['result']] += 1
        by_kind[item['kind']]['elements'] += 1
        by_kind[item['kind']][r['result']] += 1
        if r['result'] == 'unsupported':
            reasons[re.sub(r'(type(?! variable)|generic type|annotation|parameter annotation) \S+', r'\1 X', r['reason'])] += 1
        elif r['result'] == 'diverged':
            for kind in r['kind'].split('+'):
                divergences[kind] += 1
    accepted = totals['reproduced'] + totals['diverged']
    return {'totals': dict(totals), 'byKind': {k: dict(v) for k, v in sorted(by_kind.items())},
            'rate': round(totals['reproduced'] / totals['elements'], 4) if totals['elements'] else 0.0,
            'acceptedRate': round(totals['reproduced'] / accepted, 4) if accepted else 0.0,
            'divergenceKinds': dict(divergences), 'unsupported': dict(reasons.most_common()),
            'typesNotRead': dict(skipped)}


def yield_report(universe, helper):
    """The deferred trivial accessors of every pinned class, and how many the rules derive."""
    items, skipped = corpus(universe, helper, statuses=('excluded',), jobs=deferred_jobs(universe))
    totals = collections.Counter()
    reasons = collections.Counter()
    for item in items:
        if item['row'].get('category') != 'deferred':
            continue
        totals['deferred'] += 1
        try:
            derive(item, universe, DEFAULT_PLAN)
            totals['derived'] += 1
        except Unsupported as problem:
            reasons[re.sub(r'(type(?! variable)|generic type|annotation|parameter annotation) \S+', r'\1 X', str(problem))] += 1
    return {'totals': dict(totals), 'reasons': dict(reasons.most_common(25)), 'typesNotRead': sum(skipped.values())}


def seed_plan(report):
    """Record, per type and accessor kind, the attributes every hand accessor of that kind agrees on."""
    universe_types = {}
    for element, result in report['results'].items():
        if 'handAttributes' not in result:
            continue
        type_id, member = element.split('#', 1)
        kind = 'setter' if not member.endswith('()') else 'getter'
        universe_types.setdefault(type_id, {}).setdefault(kind, set()).add(tuple(result['handAttributes']))
    changed = 0
    for path in sorted((ROOT / 'api' / 'port-plan').glob('*.json')):
        plan = gate.load_json(path)
        dirty = False
        for type_id, entry in plan['types'].items():
            kinds = universe_types.get(type_id)
            if not kinds:
                continue
            agreed = {kind: list(next(iter(sets))) for kind, sets in sorted(kinds.items()) if len(sets) == 1}
            agreed = {kind: attrs for kind, attrs in agreed.items() if attrs}
            current = entry.get('accessors', {})
            merged = {**agreed, **current}  # a lane's entry wins
            if merged and merged != current:
                entry['accessors'] = dict(sorted(merged.items()))
                dirty = True
                changed += 1
        if dirty:
            path.write_text(json.dumps(plan, indent=0) + '\n', encoding='utf-8')
    return changed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--helper', required=True, type=Path)
    parser.add_argument('--cache', required=True, type=Path, help='the api cache holding the pinned sources')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compare', action='store_true')
    mode.add_argument('--yield', dest='yield_', action='store_true')
    mode.add_argument('--seed-plan', type=Path, metavar='REPORT',
                      help="record the hand ports' agreed accessor attributes in the port plans, from a --compare report")
    mode.add_argument('--render', metavar='ELEMENT', help='print the derived D member for one Java element id')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--only', action='append', help='compare one Java type id; repeatable (development)')
    args = parser.parse_args(argv)
    if args.seed_plan:
        print(f'port plan entries given accessor attributes: {seed_plan(gate.load_json(args.seed_plan))}')
        return 0
    universe = Universe(args.cache.resolve())
    if args.render:
        type_id = args.render.split('#', 1)[0]
        project, tag, _ = universe.types[type_id]
        job = {'project': project, 'tag': tag, 'type': type_id, 'kind': 'class'}
        items, _ = corpus(universe, args.helper, statuses=('ported', 'adapted', 'excluded'), jobs=[job])
        for item in items:
            if item['element'] == args.render:
                try:
                    d = derive(item, universe, DEFAULT_PLAN)
                except Unsupported as problem:
                    print(f'error: {problem}', file=sys.stderr)
                    return 2
                print(d['text'])
                print(f'// row: {d["status"]} {d["rules"]}')
                return 0
        print(f'error: {args.render} is not a trivial accessor', file=sys.stderr)
        return 2
    if args.yield_:
        result = yield_report(universe, args.helper)
    else:
        with tempfile.TemporaryDirectory(prefix='flint-accessors-') as directory:
            items, results, derived, skipped = compare(universe, args.helper, Path(directory),
                                                       log=lambda m: print(m, file=sys.stderr), only=args.only)
        result = summarise(items, results, skipped)
        result['results'] = dict(sorted(results.items()))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=1, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())
