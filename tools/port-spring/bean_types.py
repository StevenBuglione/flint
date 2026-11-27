#!/usr/bin/env python3
"""The porter's pure-bean shape: whole Java classes made of fields, trivial accessors and mechanical constructors
(porter-plan.md, M2b).

A pure-bean class is a hand-ported class whose methods are all trivial getters and setters (accessors.accessors_of),
with no nested types and no type parameters. This module derives the whole D class by fixed rules, without reading
the hand port:

  - the header: `abstract` or `final` from the Java modifiers, the superclass and interfaces through their mapped D
    symbols (an unmapped base is unsupported);
  - one D field per Java instance field, under the accessors' name rule (R19, then `name_` when a method shares the
    name), with its D type from accessors.d_type and a literal initializer when Java gives one. A private
    `serialVersionUID` is dropped: serialization is not ported. Non-private fields and other static fields are left
    to the lane for now;
  - each constructor whose body is an optional `super(...)` or `this(...)` call over parameters and literals,
    followed by assignments of parameters or literals to its own fields. A `Throwable` subclass follows R8's D
    convention: every constructor also takes `string file = __FILE__, size_t line = __LINE__` and is `pure nothrow`,
    `this(...)` forwards `file, line`, and `super(...)` takes the landed D base constructor that adds `file, line`
    to the Java arguments, or a `Throwable cause` too (passed `null`); the base's overloads are its API, read from
    the describe probe as gate (b) reads any dependency's;
  - every accessor from accessors.derive;
  - the mapping rows: the class `ported`, each constructor `ported` or `adapted` with its parameter types' rules,
    and each accessor's row.

`--compare` splices each derived class over the hand class in a copy of its module, as gate (b) does, with a
selective import for each rulebook type the class uses and the module doesn't import (`Nullable`, `List`, `Any`
...), and prints the
class's non-private API on DMD and on LDC with tools/port-spring/gate/porter_describe.d (R24 leaves private fields
to the port). The type is reproduced when those lines are identical on both compilers, every derived row matches its
hand row, and the owning package's unit tests pass on the spliced tree.

    python3 tools/port-spring/bean_types.py --helper .flint/port-spring/flint-port-spring \\
        --cache "$PWD/.flint/cache/api" --compare [--no-tests] [--json artifacts/porter/bean-types.json]
"""
import argparse
import collections
import json
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from api_differences import erase_type  # noqa: E402
import accessors  # noqa: E402
import porter_gate as gate  # noqa: E402  (accessors and porter_gate import each other: attributes only at call time)

SHAPE = 'bean-class'
LITERAL = re.compile(r'true|false|null|-?(?:0|[1-9][0-9_]*)[lL]?|"(?:[^"\\]|\\.)*"$')
THROWABLES = ('java.lang.Throwable', 'java.lang.Exception', 'java.lang.RuntimeException')
FILE_LINE = ['string file = __FILE__', 'ulong line = cast(ulong)__LINE__']
# The D home of each type the rulebook introduces (R5, R10, R23).
IMPORTS = {'Nullable': 'std.typecons', 'Optional': 'flint.java.util', 'List': 'flint.java.util',
           'Set': 'flint.java.util', 'Collection': 'flint.java.util', 'Map': 'flint.java.util',
           'Any': 'flint.engine.aot.any'}
CALL = re.compile(r'(super|this)\s*\((.*)\)$')
ASSIGNMENT = re.compile(r'(?:this\.)?(\w+)\s*=\s*(.+)$')


# ---- the corpus ---------------------------------------------------------------------------------------------------

def corpus(universe, helper, jobs=None):
    """Every pure-bean hand-ported class, with its declaration, scope and accessor items; and types not read."""
    items, skipped = [], collections.Counter()
    for job in jobs if jobs is not None else gate.corpus():
        if job['kind'] != 'class':
            continue
        try:
            path, nested = universe.source(job['project'], job['tag'], job['type'])
            tree = accessors.describe_java(helper, path)
        except accessors.Unsupported as problem:
            skipped[str(problem)] += 1
            continue
        decl, type_id = tree['type'], job['type'][:len(job['type']) - sum(len(n) + 1 for n in nested)]
        chain = [(type_id, decl)]
        for name in nested:
            decl = next(t for t in decl['types'] if t['name'] == name)
            type_id += '.' + name
            chain.append((type_id, decl))
        found = accessors.accessors_of(decl)
        trivial = {id(method) for _, method, _ in found}
        if not found or any(id(m) not in trivial for m in decl['methods']):
            continue
        scope = accessors.Scope(universe, tree, chain)
        members = []
        for kind, method, (field, declarator) in found:
            element = job['type'] + '#' + accessors.signature(method)
            members.append({'element': element, 'kind': kind, 'job': job, 'method': method, 'field': field,
                            'declarator': declarator, 'scope': scope, 'class': decl,
                            'row': universe.row(job['project'], job['tag'], element)})
        items.append({'type': job['type'], 'job': job, 'class': decl, 'scope': scope, 'accessors': members})
    return items, skipped


# ---- derivation ---------------------------------------------------------------------------------------------------

def base_name(java, scope):
    """The D name of a mapped superclass or interface."""
    java = accessors.strip_annotations(java)[0]
    if '<' in java:
        raise accessors.Unsupported(f'generic base {java}')
    full = scope.resolve(java)
    if full in accessors.D_THROWABLES:
        return accessors.D_THROWABLES[full]
    row = accessors.mapped_row(scope.universe, full)
    if row is None:
        raise accessors.Unsupported(f'base {full} is not mapped to a D symbol')
    scope.used[row['d'].rsplit('.', 1)[1]] = row['d']
    return row['d'].rsplit('.', 1)[1]


def throwable(universe, type_id):
    seen, parent = set(), accessors.parent_of(universe, type_id)
    while parent and parent not in seen:
        if parent in THROWABLES:
            return True
        seen.add(parent)
        parent = accessors.parent_of(universe, parent)
    return False


def d_parameters(text):
    """A D parameter list split at top-level commas (types like `Map!(string, Any)` and defaults like
    `cast(ulong)__LINE__` hold their own)."""
    parts, depth, start = [], 0, 0
    for index, char in enumerate(text):
        depth += char in '([{'
        depth -= char in ')]}'
        if char == ',' and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    parts.append(text[start:].strip())
    return [p for p in parts if p]


def constructor_parameters(description, name):
    """[[parameter text]] for each constructor a describe!(Base) text lists."""
    found = []
    for line in description.splitlines():
        match = re.match(rf'{re.escape(name)}\.__ctor#\d+ \S+ .*?{re.escape(name)}\((.*)\)( [\w@ ]*)?$', line)
        if match:
            found.append(d_parameters(match.group(1)))
    return found


def file_line_at(params):
    """Where R8's `file, line` pair sits in a D parameter list, or None."""
    return next((i for i in range(len(params) - 1) if params[i:i + 2] == FILE_LINE), None)


def super_arguments(arguments, base_overloads):
    """The D `super` arguments for a Throwable subclass: the Java ones plus `file, line`, with a `null` cause where
    the base takes one before them, or the Java cause after them where the base takes it last (druntime's
    `nextInChain`)."""
    cause = re.compile(r'Throwable \w+ = null$')
    for params in base_overloads:
        at = file_line_at(params)
        if at is None:
            continue
        before, after = params[:at], params[at + 2:]
        if len(before) == len(arguments) and not after:
            return arguments + ['file', 'line']
        if len(before) == len(arguments) + 1 and cause.match(before[-1]) and not after:
            return arguments + ['null', 'file', 'line']
        if len(after) == 1 and cause.match(after[0]):
            if len(before) == len(arguments):
                return arguments + ['file', 'line']
            if len(before) + 1 == len(arguments):
                return arguments[:-1] + ['file', 'line', arguments[-1]]
    raise accessors.Unsupported(f'the D base has no constructor taking {len(arguments)} argument(s) and file, line (R8)')


def literal(text, where):
    text = text.strip()
    if not LITERAL.fullmatch(text):
        raise accessors.Unsupported(f'{where} is not a parameter or literal: {text[:60]}')
    return re.sub(r'[lL]$', 'L', text.replace('_', '')) if text[0] in '-0123456789' else text


def field_names(decl):
    """{Java field name: D field name}, under the accessors' rule (R19, then `name_` beside a same-name method)."""
    methods = {accessors.d_name(m['name']) for m in decl['methods']}
    names = {}
    for f in decl['fields']:
        for d in f['declarators']:
            name = accessors.d_name(d['name'])
            names[d['name']] = name + '_' if name in methods else name
    return names


def derive_fields(decl, scope, names):
    lines = []
    for f in decl['fields']:
        modifiers = f['modifiers']
        if 'static' in modifiers:
            if 'private' in modifiers and [d['name'] for d in f['declarators']] == ['serialVersionUID']:
                continue
            raise accessors.Unsupported('a static field')
        if 'private' not in modifiers:
            raise accessors.Unsupported('a non-private instance field (R24)')
        nullable = any(a['name'] == 'Nullable' for a in f['annotations']) or accessors.strip_annotations(f['type'])[1]
        for d in f['declarators']:
            dtype = accessors.d_type(f['type'] + (d.get('dimensions') or ''), nullable, scope, set())
            value = f' = {literal(d["value"], "a field initializer")}' if d.get('value') else ''
            lines.append(f'private {dtype} {names[d["name"]]}{value};')
    return lines


def statements(body):
    body = ' '.join((body or '').split())
    if not (body.startswith('{') and body.endswith('}')):
        raise accessors.Unsupported('a constructor without a body')
    inner = body[1:-1].strip()
    if '"' in inner and ';' in ''.join(re.findall(r'"(?:[^"\\]|\\.)*"', inner)):
        raise accessors.Unsupported('a string literal holding a semicolon')
    return [s.strip() for s in inner.split(';') if s.strip()]


def derive_constructor(ctor, decl, scope, names, base_overloads=None):
    """(text, row status, rules, element signature) for one mechanical constructor; `base_overloads` (the D base's
    constructor parameters) marks a Throwable subclass."""
    visibility = next((v for v in ('public', 'protected', 'private') if v in ctor['modifiers']), None)
    if visibility is None:
        raise accessors.Unsupported('a package-private constructor')
    if ctor.get('typeParameters'):
        raise accessors.Unsupported('a generic constructor')
    for annotation in ctor['annotations']:
        if annotation['name'] not in ('SuppressWarnings',):
            raise accessors.Unsupported(f'constructor annotation @{annotation["name"]}')
    rules, parameters, renamed = set(), [], {}
    for p in ctor['parameters']:
        if p.get('variadic'):
            raise accessors.Unsupported('a variadic constructor (R7)')
        for annotation in p['annotations']:
            if annotation['name'] != 'Nullable':
                raise accessors.Unsupported(f'parameter annotation @{annotation["name"]}')
        nullable = any(a['name'] == 'Nullable' for a in p['annotations'])
        if nullable and base_overloads is not None and accessors.strip_annotations(p['type'])[0] == 'String':
            nullable = False  # R26: an exception's detail message stays a plain string
            rules.add('R26')
        dtype = accessors.d_type(p['type'], nullable, scope, rules)
        renamed[p['name']] = accessors.d_name(p['name'])
        parameters.append(f'{dtype} {renamed[p["name"]]}')
    fields = {d['name'] for f in decl['fields'] if 'static' not in f['modifiers'] for d in f['declarators']}

    def argument(text):
        text = text.strip()
        return renamed[text] if text in renamed else literal(text, 'a constructor argument')

    body = []
    for index, statement in enumerate(statements(ctor['body'])):
        call = CALL.fullmatch(statement)
        if call and index == 0:
            args = [argument(a) for a in (accessors.split_arguments(call.group(2)) if call.group(2).strip() else [])]
            if base_overloads is not None:
                args = args + ['file', 'line'] if call.group(1) == 'this' else super_arguments(args, base_overloads)
            body.append(f'{call.group(1)}({", ".join(args)});')
            continue
        assignment = ASSIGNMENT.fullmatch(statement)
        if not assignment or assignment.group(1) not in fields \
                or (not statement.startswith('this.') and assignment.group(1) in renamed):
            raise accessors.Unsupported(f'a constructor statement that is not a field assignment: {statement[:60]}')
        body.append(f'this.{names[assignment.group(1)]} = {argument(assignment.group(2))};')
    suffix = ''
    if base_overloads is not None:
        if not any(CALL.fullmatch(s) for s in statements(ctor['body'])[:1]):
            body.insert(0, f'super({", ".join(super_arguments([], base_overloads))});')
        parameters += ['string file = __FILE__', 'size_t line = __LINE__']
        suffix = ' pure nothrow'
    text = f'{visibility} this({", ".join(parameters)}){suffix}\n{{\n' + ''.join(f'    {s}\n' for s in body) + '}'
    signature = '<init>(' + ','.join(erase_type(p['type']) for p in ctor['parameters']) + ')'
    rules = sorted(rules, key=lambda r: int(r[1:]))
    return text, 'adapted' if rules else 'ported', rules, signature


def derive(item, universe, base_overloads=None, base_members=()):
    """{'text', 'name', 'rows': {element: (status, rules)}} for one pure-bean class, or accessors.Unsupported. A Throwable
    subclass needs `base_overloads`, its D base's constructor parameters."""
    decl, scope, type_id = item['class'], item['scope'], item['type']
    plan = universe.plans.get(type_id)
    if plan is None:
        raise accessors.Unsupported('the type has no port plan entry')
    if plan.get('kind') not in ('class', 'final class', 'abstract class'):
        raise accessors.Unsupported(f'plan kind {plan.get("kind")}')
    if decl.get('typeParameters'):
        raise accessors.Unsupported('a generic class')
    if decl['types']:
        raise accessors.Unsupported('a nested type')
    if decl.get('initializers'):
        raise accessors.Unsupported('an initializer block')
    for annotation in decl['annotations']:
        if annotation['name'] not in ('SuppressWarnings',):
            raise accessors.Unsupported(f'class annotation @{annotation["name"]}')
    bases = [base_name(decl['superclass'], scope)] if decl.get('superclass') else []
    bases += [base_name(i, scope) for i in accessors.split_arguments(decl.get('interfaces') or '')]
    if throwable(universe, type_id) and base_overloads is None:
        parent = accessors.parent_of(universe, type_id)
        if parent not in accessors.D_THROWABLES:
            raise accessors.Unsupported('a Throwable subclass whose D base constructors are unknown')
        base_overloads = [['string msg', 'string file = __FILE__', 'ulong line = cast(ulong)__LINE__',
                           'Throwable nextInChain = null']]  # druntime's Exception and Throwable
    if not throwable(universe, type_id) or not any(file_line_at(p) is not None for p in base_overloads):
        base_overloads = None  # not a Throwable, or a D base without R8's file, line family: plain forwarding
    names = field_names(decl)
    body = derive_fields(decl, scope, names)
    rows = {type_id: ('ported', [])}
    for ctor in decl['constructors']:
        text, status, rules, signature = derive_constructor(ctor, decl, scope, names, base_overloads)
        body.append(text)
        rows[f'{type_id}#{signature}'] = (status, rules)
    by_line = sorted(item['accessors'], key=lambda a: a['method']['line'])
    for member in by_line:
        d = accessors.derive({**member, 'baseMembers': base_members}, universe)
        body.append(d['text'])
        rows[member['element']] = (d['status'], d['rules'])
    modifiers = [m for m in ('abstract', 'final') if m in decl['modifiers']]
    if plan['kind'] == 'final class' and 'final' not in modifiers:
        modifiers.append('final')
    name = accessors.d_name(decl['name'])
    head = ' '.join(modifiers + ['class', name]) + (' : ' + ', '.join(bases) if bases else '')
    fields, members = body[:len(body) - len(rows) + 1], body[len(body) - len(rows) + 1:]
    inner = '\n\n'.join(accessors.indented('    ' + b, '    ') for b in (['\n'.join(fields)] if fields else []) + members)
    return {'text': f'{head}\n{{\n{inner}\n}}', 'name': name, 'rows': rows}


# ---- comparison ---------------------------------------------------------------------------------------------------

def with_imports(text, module):
    """The class text behind the selective imports it needs that `module` doesn't already have."""
    lines = []
    for symbol, home in IMPORTS.items():
        if not re.search(rf'\b{symbol}\b', text):
            continue
        if re.search(rf'\bimport\s+[^;]*\b{symbol}\b', module) or re.search(rf'\bimport\s+{re.escape(home)}\s*;', module):
            continue
        lines.append(f'import {home} : {symbol};\n')
    return ''.join(lines) + text


def api_lines(description):
    """The description's lines less private members (R24: private fields are the port's choice)."""
    return [line for line in description.splitlines() if len(line.split()) < 2 or line.split()[1] != 'private']


def compare(universe, helper, scratch, compilers=None, tests=True, log=None, only=None):
    """{type id: result} for every pure-bean class, results shaped like porter_gate.reproduce's."""
    compilers = compilers or gate.COMPILERS
    jobs = [j for j in gate.corpus() if not only or j['type'] in only]
    items, skipped = corpus(universe, helper, jobs)
    results, derived = {}, {}
    index = gate.module_index(gate.import_roots())
    by_package = collections.defaultdict(list)
    for item in items:
        owners = [gate.package_of(p) for _, p in index.get(item['job']['module'], ())]
        if not owners or owners[0] is None:
            results[item['type']] = {'result': 'rejected', 'reason': f'no package declares {item["job"]["module"]}'}
            continue
        by_package[owners[0]].append(item)
    spliced_files = {}
    for package, group in sorted(by_package.items()):
        if log:
            log(f':{package}: {len(group)} classes')
        roots = gate.import_paths(package)
        bases = {}
        for item in group:
            parent = accessors.parent_of(universe, item['type'])
            row = universe.rows.get(parent) if parent else None
            if row:
                bases[item['type']] = row['d']
        described = {}
        for symbol in sorted(set(bases.values())):
            try:
                described.update(accessors.describe(compilers[0], None, roots, [symbol], scratch))
            except ValueError:
                pass
        # The D base's ancestors, from its description's `base` lines, for the member names `override` needs.
        ancestors = sorted({line.split()[2] for text in described.values() for line in text.splitlines()
                            if len(line.split()) == 3 and line.split()[1] == 'base'
                            and not line.split()[2].startswith('object.')} - set(described))
        for symbol in ancestors:
            try:
                described.update(accessors.describe(compilers[0], None, roots, [symbol], scratch))
            except ValueError:
                pass
        overloads, members = {}, {}
        for type_id, symbol in bases.items():
            if symbol not in described:
                continue
            overloads[type_id] = constructor_parameters(described[symbol], symbol.rsplit('.', 1)[1])
            chain = [symbol] + [line.split()[2] for line in described[symbol].splitlines()
                                if len(line.split()) == 3 and line.split()[1] == 'base']
            members[type_id] = {m.group(1) for s in chain if s in described
                                for m in re.finditer(r'^\w+\.(\w+)#\d+ (?!private)', described[s], re.M)}
        live_group = []
        for item in group:
            try:
                inputs = (overloads.get(item['type']), members.get(item['type'], ()))
                derived[item['type']] = {**derive(item, universe, *inputs), 'inputs': inputs}
                results[item['type']] = {'result': 'reproduced', 'shape': SHAPE}
                live_group.append(item)
            except accessors.Unsupported as problem:
                results[item['type']] = {'result': 'rejected', 'reason': str(problem)}
        group = live_group
        symbols = sorted({item['job']['symbol'] for item in group})
        declaring = gate.locate(roots, symbols, scratch)
        overlay = scratch / 'overlay' / package
        files = collections.defaultdict(list)
        for item in group:
            places = [(r, p) for r, p in index.get(declaring.get(item['job']['symbol'], ''), ()) if r in roots]
            if not places:
                diverge(results, item, 'api', 'the hand type is not declared in the package\'s import paths')
                continue
            files[places[0]].append(item)
        live = []
        for (root, path), file_items in files.items():
            text = path.read_text(encoding='utf-8')
            for item in file_items:
                try:
                    text = gate.splice_one(text, item['job']['symbol'].rsplit('.', 1)[1],
                                           with_imports(derived[item['type']]['text'], text))
                    live.append(item)
                except ValueError as problem:
                    diverge(results, item, 'api', f'cannot splice: {problem}')
            destination = overlay / path.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text, encoding='utf-8')
            spliced_files[path] = [i for i in file_items if i in live]
        wanted = sorted({item['job']['symbol'] for item in live})
        if not wanted:
            continue
        for compiler in compilers:
            hand = accessors.describe(compiler, None, roots, wanted, scratch)
            try:
                spliced = accessors.describe(compiler, overlay, roots, wanted, scratch)
            except ValueError as problem:
                spliced = {}
                for item in live:  # one class at a time, to name the one that breaks the module
                    try:
                        spliced.update(accessors.describe(compiler, overlay, roots, [item['job']['symbol']], scratch))
                    except ValueError:
                        diverge(results, item, 'api', f'{compiler}: the spliced :{package} does not compile: '
                                + accessors.first_error(str(problem)))
            for item in live:
                symbol = item['job']['symbol']
                if symbol not in spliced:
                    continue
                before, after = api_lines(hand[symbol]), api_lines(spliced[symbol])
                if before != after:
                    diverge(results, item, 'api', f'{compiler}: ' + gate.first_difference('\n'.join(before),
                                                                                         '\n'.join(after)))
    for item in items:
        if item['type'] not in derived:
            continue
        for element, (status, rules) in sorted(derived[item['type']]['rows'].items()):
            row = universe.row(item['job']['project'], item['job']['tag'], element)
            if row is None:
                diverge(results, item, 'mapping', f'{element}: no exact hand row')
            elif (row['status'], row.get('rules', [])) != (status, rules):
                diverge(results, item, 'mapping', f"{element}: hand {row['status']} {row.get('rules', [])}, "
                                                  f'porter {status} {rules}')
    if tests and spliced_files:
        # The tests see only the classes whose API matched, so one divergent splice can't fail its neighbours'.
        compiled = {}
        for path, file_items in spliced_files.items():
            clean = [i for i in file_items if 'api' not in results[i['type']].get('kind', '').split('+')]
            if not clean:
                continue
            text = path.read_text(encoding='utf-8')
            for item in clean:
                text = gate.splice_one(text, item['job']['symbol'].rsplit('.', 1)[1],
                                       with_imports(derived[item['type']]['text'], text))
            compiled[path] = (text, [{'type': i['type']} for i in clean])
        if compiled:
            gate.run_tests(compiled, results, scratch)
    return items, results, derived, skipped


def diverge(results, item, kind, reason):
    gate.diverge(results, {'type': item['type']}, kind, reason)


def summarise(items, results, skipped):
    totals = collections.Counter(r['result'] for r in results.values())
    totals['classes'] = len(items)
    kinds = collections.Counter(k for r in results.values() if r['result'] == 'diverged' for k in r['kind'].split('+'))
    rejected = collections.Counter(re.sub(r'(base|plan kind|annotation @?)\s?\S+', r'\1 X', r['reason'])
                                   for r in results.values() if r['result'] == 'rejected')
    accepted = totals['reproduced'] + totals['diverged']
    return {'totals': dict(totals), 'rate': round(totals['reproduced'] / len(items), 4) if items else 0.0,
            'acceptedRate': round(totals['reproduced'] / accepted, 4) if accepted else 0.0,
            'divergenceKinds': dict(kinds), 'rejected': dict(rejected.most_common()), 'typesNotRead': dict(skipped)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--helper', required=True, type=Path)
    parser.add_argument('--cache', required=True, type=Path, help='the api cache holding the pinned sources')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compare', action='store_true')
    mode.add_argument('--render', metavar='TYPE', help='print the derived D class for one Java type id')
    parser.add_argument('--no-tests', action='store_true', help='skip the package unit tests (development)')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--only', action='append', help='compare one Java type id; repeatable (development)')
    args = parser.parse_args(argv)
    universe = accessors.Universe(args.cache.resolve())
    if args.render:
        project, tag, _ = universe.types[args.render]
        job = {'project': project, 'tag': tag, 'type': args.render, 'kind': 'class'}
        items, _ = corpus(universe, args.helper, [job])
        if not items:
            print(f'error: {args.render} is not a pure-bean class', file=sys.stderr)
            return 2
        try:
            d = derive(items[0], universe)
        except accessors.Unsupported as problem:
            print(f'error: {problem}', file=sys.stderr)
            return 2
        print(d['text'])
        for element, (status, rules) in sorted(d['rows'].items()):
            print(f'// row {element}: {status} {rules}')
        return 0
    with tempfile.TemporaryDirectory(prefix='flint-bean-types-') as directory:
        items, results, _, skipped = compare(universe, args.helper, Path(directory), tests=not args.no_tests,
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
