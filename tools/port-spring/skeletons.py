#!/usr/bin/env python3
"""The porter's skeleton mode: every declaration of a Java class or interface, with marked bodies (porter-plan.md,
M3).

A skeleton is the whole D type a lane would otherwise write by hand around the bodies: the header, fields,
constructors and methods with their D signatures, DDoc and mapping rows. Each body is derived where a mechanical
shape covers it (accessors.derive for trivial accessors, bean_types.derive_constructor for constructors that only
forward and assign), and every other body becomes a marked region the lane fills:

    // port:body <element id>
    assert(0, "port:body <element id>");
    // port:end-body

`assert(0)` compiles in every attribute context (`pure nothrow @nogc`, a constructor whose D base has no default
constructor) and fails loudly until the lane writes the body; the element's row stays deferred until then. The
signature rules are the accessors' (accessors.d_type: R5, R10, R19, R23), plus:

  - visibility as in Java (`package` for package-private); `static`, `abstract` and `final` as in Java, and
    `override` where a Java superclass declares the method or Java says @Override and the landed D base chain
    declares the name;
  - Java `throws` clauses are dropped (R8); `@Deprecated` becomes `deprecated`;
  - a `Throwable` subclass's constructors take R8's `string file = __FILE__, size_t line = __LINE__` and are
    `pure nothrow`, with a `String` message parameter kept as a plain `string` (R26);
  - `equals`, `hashCode` and `toString` keep their names under R11, with `mixin JavaObject;` when the class
    declares `equals` or `hashCode`; `equals` takes `Object`;
  - a `public` or `protected` `final` instance field becomes R24's `final` accessor over a private `name_` field; a
    non-final one stays a D field; a private one stays private; a `static final` field with a literal initializer
    becomes an `enum`.

A member the rules can't declare yet (a generic method, varargs under R7, an unmapped type, a nested type under
R13, an interface default method under R3) is left out with a `// port:pending <element id>: <reason>` line, so
the skeleton stays complete for everything else; its row stays deferred with that reason.

`--compare` offers every hand-ported class and interface (gate (b)'s corpus) to the rules, splices the skeleton over
the hand type in a copy of its module and prints both types' API with gate/porter_describe.d on DMD and LDC. A
member is reproduced when its description lines (all overloads of its D name, less the overload index) match the
hand port's on both compilers and its row agrees; a type is reproduced when every non-private line matches and no
member is pending. Bodies don't matter for the API comparison, so package tests don't run here.

    python3 tools/port-spring/skeletons.py --helper .flint/port-spring/flint-port-spring \\
        --cache "$PWD/.flint/cache/api" --compare [--json artifacts/porter/skeletons.json]   # compiles: under hold
    python3 tools/port-spring/skeletons.py ... --render org.springframework.transaction.support.DefaultTransactionStatus
    python3 tools/port-spring/skeletons.py ... --yield
"""
import argparse
import collections
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from api_differences import erase_type  # noqa: E402
import accessors  # noqa: E402
import bean_types  # noqa: E402
import beans  # noqa: E402  (doc_text: the Javadoc's main description as one line)
import porter_gate as gate  # noqa: E402  (accessors and porter_gate import each other: attributes only at call time)

SHAPE = 'skeleton'
# Java annotations with no D counterpart on a declaration: compile-time checks, nullness carried by the type.
IGNORED = {'Override', 'SuppressWarnings', 'Nullable', 'NonNull', 'Contract', 'Serial', 'SafeVarargs',
           'CheckReturnValue', 'FunctionalInterface', 'Deprecated', 'NullMarked', 'NullUnmarked'}
JAVA_OBJECT = {'equals(Object)': 'bool equals(Object other)', 'hashCode()': 'int hashCode()'}
CLASS_KINDS = ('class', 'final class', 'abstract class')


def body_region(element, indent='    '):
    return (f'{indent}// port:body {element}\n{indent}assert(0, "port:body {element}");\n'
            f'{indent}// port:end-body\n')


def ddoc(decl, indent=4):
    text = beans.doc_text(decl.get('javadoc'))
    if text:
        text = re.sub(r'</?(?:b|i|tt|ul|li|ol|pre|br)\s*/?>', '', text)
    return [f'/// {line}' for line in wrap(text, 116 - indent)] if text else []


def wrap(text, width):
    lines, line = [], ''
    for word in text.split():
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = word
        else:
            line = f'{line} {word}' if line else word
    return lines + ([line] if line else [])


def deprecation(decl):
    found = next((a for a in decl['annotations'] if a['name'] == 'Deprecated'), None)
    if found is None:
        return []
    since = re.search(r'since\s*=\s*"([^"]*)"', found.get('arguments') or '')
    return [f'deprecated("since {since.group(1)}")'] if since else ['deprecated']


def check_annotations(decl, what):
    for annotation in decl['annotations']:
        if annotation['name'] not in IGNORED:
            raise accessors.Unsupported(f'{what} annotation @{annotation["name"]}')


def nullable(decl):
    return any(a['name'] == 'Nullable' for a in decl['annotations']) or accessors.strip_annotations(decl['type'])[1]


def visibility_of(modifiers, interface=False):
    found = next((v for v in ('public', 'protected', 'private') if v in modifiers), None)
    return found or ('public' if interface else 'package')


def parameters_of(member, scope, rules, throwable=False):
    params = []
    for p in member['parameters']:
        if p.get('variadic'):
            raise accessors.Unsupported('varargs (R7)')
        for annotation in p['annotations']:
            if annotation['name'] not in IGNORED:
                raise accessors.Unsupported(f'parameter annotation @{annotation["name"]}')
        is_null = any(a['name'] == 'Nullable' for a in p['annotations']) or accessors.strip_annotations(p['type'])[1]
        if throwable and is_null and accessors.strip_annotations(p['type'])[0] == 'String':
            is_null = False
            rules.add('R26')  # an exception's detail message stays a plain string
        dtype = accessors.d_type(p['type'] + (p.get('dimensions') or ''), is_null, scope, rules,
                                 throwables=True)
        name = accessors.d_name(p['name'])
        params.append(f'{dtype} {name}')
    return params


def unpublic(text):
    """A mechanical member's text without the `public` D gives a class member anyway."""
    return text[len('public '):] if text.startswith('public ') else text


def status(rules):
    rules = sorted(rules, key=lambda r: int(r[1:]))
    return ('adapted' if rules else 'ported'), rules


# ---- members ------------------------------------------------------------------------------------------------------

class Context:
    """What every member of one type needs: the item, its plan, D base facts and the accessors it has."""

    def __init__(self, item, universe, base_overloads, base_members, interface):
        self.item, self.universe, self.interface = item, universe, interface
        self.decl, self.scope, self.type_id = item['class'], item['scope'], item['type']
        self.base_overloads, self.base_members = base_overloads, base_members
        self.throwable = bean_types.throwable(universe, self.type_id)
        self.accessors = {id(method): (kind, field, declarator)
                          for kind, method, (field, declarator) in accessors.accessors_of(self.decl)} \
            if not interface else {}
        self.final_class = 'final' in self.decl['modifiers']
        self.java_interface = self.decl['kind'] == 'interface'
        self.defaults = []  # R3 default method texts for an interface's `mixin template Defaults`


def derive_method(method, ctx, plan):
    """(text, (status, rules), pending body?) for one method, or accessors.Unsupported."""
    sig = accessors.signature(method)
    element = f'{ctx.type_id}#{sig}'
    check_annotations(method, 'method')
    if method.get('typeParameters'):
        raise accessors.Unsupported('a generic method')
    if id(method) in ctx.accessors and sig not in JAVA_OBJECT and sig != 'toString()':
        kind, field, declarator = ctx.accessors[id(method)]
        member = {'method': method, 'job': ctx.item['job'], 'scope': ctx.scope, 'kind': kind, 'field': field,
                  'declarator': declarator, 'class': ctx.decl, 'baseMembers': ctx.base_members}
        try:
            d = accessors.derive(member, ctx.universe, default_plan=plan)
            return '\n'.join(ddoc(method) + [unpublic(d['text'])]), (d['status'], d['rules']), False
        except accessors.Unsupported as problem:
            if 'package-private or private' not in str(problem):
                raise
    modifiers, rules = method['modifiers'], set()
    name = accessors.d_name(method['name'])
    if name != method['name']:
        rules.add('R19')
    static, body = 'static' in modifiers, method['body']
    default = 'default' in modifiers
    prefix = deprecation(method)
    visibility = visibility_of(modifiers, ctx.interface)
    if visibility != 'public':
        prefix.append(visibility)
    if static:
        prefix.append('static')
    elif sig in JAVA_OBJECT or sig == 'toString()':
        rules.add('R11')
    java_override = any(a['name'] == 'Override' for a in method['annotations'])
    if not static and not ctx.interface and (sig == 'toString()' or accessors.overrides(ctx.universe, ctx.type_id, sig)
                                             or (java_override and name in ctx.base_members)):
        prefix.append('override')
    if not ctx.interface and ('abstract' in modifiers or (ctx.java_interface and not body and not static)):
        prefix.append('abstract')
    if 'final' in modifiers and not ctx.final_class and not static:
        prefix.append('final')
    if sig in JAVA_OBJECT:
        head = JAVA_OBJECT[sig]
    else:
        returns = 'void' if method['type'] == 'void' else accessors.d_type(
            method['type'] + (method.get('dimensions') or ''), nullable(method), ctx.scope, rules, throwables=True)
        params = parameters_of(method, ctx.scope, rules)
        head = f'{returns} {name}({", ".join(params)})'
    text = ' '.join(prefix + [head])
    if default:
        rules.add('R3')
    if not body:
        return '\n'.join(ddoc(method) + [text + ';']), status(rules), False
    if default and ctx.interface:
        # R3: the interface declares it, and `mixin template Defaults` carries the body for implementors.
        ctx.defaults.append('\n'.join(ddoc(method, 8) + [f'{text}\n{{\n{body_region(element)}}}']))
        return '\n'.join(ddoc(method) + [text + ';']), status(rules), True
    return '\n'.join(ddoc(method) + [f'{text}\n{{\n{body_region(element)}}}']), status(rules), True


def derive_constructor(ctor, ctx, names, initialized):
    """(text, (status, rules), pending body?, element) for one constructor."""
    signature = '<init>(' + ','.join(erase_type(p['type']) for p in ctor['parameters']) + ')'
    element = f'{ctx.type_id}#{signature}'
    check_annotations(ctor, 'constructor')
    if ctor.get('typeParameters'):
        raise accessors.Unsupported('a generic constructor')
    overloads = ctx.base_overloads if ctx.throwable else None
    if not initialized:
        try:
            text, row_status, rules, _ = bean_types.derive_constructor(ctor, ctx.decl, ctx.scope, names, overloads)
            return '\n'.join(ddoc(ctor) + [unpublic(text)]), (row_status, rules), False, element
        except accessors.Unsupported as problem:
            if not re.search(r'constructor statement|not a parameter or literal|without a body|semicolon|'
                             r'no constructor taking|package-private', str(problem)):
                raise
    rules = set()
    params = parameters_of(ctor, ctx.scope, rules, throwable=ctx.throwable)
    suffix = ''
    if ctx.throwable and overloads is not None:
        params += ['string file = __FILE__', 'size_t line = __LINE__']
        suffix = ' pure nothrow'
    visibility = visibility_of(ctor['modifiers'])
    text = ' '.join(deprecation(ctor) + [v for v in (visibility,) if v != 'public']
                    + [f'this({", ".join(params)}){suffix}'])
    return '\n'.join(ddoc(ctor) + [f'{text}\n{{\n{body_region(element)}}}']), status(rules), True, element


def derive_fields(ctx, names):
    """(declaration lines, accessor members [(text, element, row)], pending [(element, reason)], whether some
    instance field has a non-literal initializer)."""
    lines, members, pending, computed = [], [], [], False
    for f in ctx.decl['fields']:
        modifiers = f['modifiers']
        for d in f['declarators']:
            element = f'{ctx.type_id}#{d["name"]}'
            try:
                check_annotations(f, 'field')
                if ctx.java_interface or 'static' in modifiers:
                    if 'static' in modifiers and 'private' in modifiers and d['name'] == 'serialVersionUID':
                        continue
                    if not (ctx.java_interface or 'final' in modifiers):
                        raise accessors.Unsupported('mutable static state')
                    if not d.get('value') or not bean_types.LITERAL.fullmatch(d['value'].strip()):
                        raise accessors.Unsupported('a constant whose initializer is not a literal')
                    rules = set()
                    dtype = accessors.d_type(f['type'] + (d.get('dimensions') or ''), False, ctx.scope, rules,
                                             throwables=True)
                    visibility = visibility_of(modifiers, ctx.java_interface)
                    value = bean_types.literal(d['value'], 'a constant')
                    lines += ddoc(f) + [' '.join([v for v in (visibility,) if v != 'public']
                                                 + [f'enum {dtype} {accessors.d_name(d["name"])} = {value};'])]
                    members.append((None, element, status(rules)))
                    continue
                rules = set()
                dtype = accessors.d_type(f['type'] + (d.get('dimensions') or ''), nullable(f), ctx.scope, rules,
                                         throwables=True)
                value = ''
                if d.get('value'):
                    if bean_types.LITERAL.fullmatch(d['value'].strip()):
                        value = f' = {bean_types.literal(d["value"], "a field initializer")}'
                    else:
                        computed = True
                visibility = visibility_of(modifiers)
                name = names[d['name']]
                if visibility in ('public', 'protected') and 'final' in modifiers:
                    rules.add('R24')
                    lines.append(f'private {dtype} {name}{value};')
                    accessor = ddoc(f) + [' '.join([v for v in (visibility,) if v != 'public']
                                                   + [f'final {dtype} {name[:-1]}() => {name};'])]
                    members.append(('\n'.join(accessor), element, status(rules)))
                else:
                    lines += (ddoc(f) if visibility != 'private' else []) + [
                        ' '.join([v for v in (visibility,) if v != 'public'] + [f'{dtype} {name}{value};'])]
                    if visibility != 'private':
                        members.append((None, element, status(rules)))
            except accessors.Unsupported as problem:
                if 'private' in modifiers and 'static' not in modifiers:
                    raise  # a private instance field is state every body needs
                pending.append((element, str(problem)))
    return lines, members, pending, computed


def defaults_of(ctx, bases):
    """The D names of the interfaces a class implements directly whose Java declaration has default methods and
    whose plan keeps them an interface (R3's `mixin template Defaults`)."""
    found = []
    java = accessors.split_arguments(ctx.decl.get('interfaces') or '')
    for name, d_name in zip(java, bases[len(bases) - len(java):]):
        full = ctx.scope.resolve(accessors.strip_annotations(name)[0])
        if ctx.d_defaults is not None and full in ctx.universe.rows:
            if ctx.universe.rows[full]['d'] in ctx.d_defaults:
                found.append(d_name)
            continue  # a landed D interface decides by what it declares
        entry = ctx.universe.types.get(full)
        if entry is None or ctx.universe.plans.get(full, {}).get('kind', 'interface') != 'interface':
            continue
        if any('default' in m.get('modifiers', ()) for m in entry[2].get('members', ()) if m.get('kind') == 'method'):
            found.append(d_name)
    return found


def derive(item, universe, base_overloads=None, base_members=(), d_defaults=None):
    """{'text', 'name', 'rows': {element: (status, rules)}, 'pending': {element: reason}, 'bodies': [element]}."""
    decl, scope, type_id = item['class'], item['scope'], item['type']
    interface = decl['kind'] == 'interface'
    plan = universe.plans.get(type_id, item.get('default_plan'))
    if plan is None:
        raise accessors.Unsupported('the type has no port plan entry')
    if decl['kind'] not in ('class', 'interface'):
        raise accessors.Unsupported(f'a Java {decl["kind"]}')
    if plan.get('kind') not in (('interface', 'abstract class') if interface else CLASS_KINDS):
        raise accessors.Unsupported(f'plan kind {plan.get("kind")} for a Java {decl["kind"]}')
    if interface and plan['kind'] == 'abstract class':
        if decl.get('interfaces'):
            raise accessors.Unsupported('an interface ported as an abstract class (D-3) that extends interfaces')
        interface = False  # R3's deviation D-3: an interface implemented selectively is an abstract class
    if plan.get('storage') not in (None, 'erased'):
        raise accessors.Unsupported('templated storage')
    if decl.get('typeParameters'):
        raise accessors.Unsupported('a generic type')
    check_annotations(decl, 'type')
    scope.used = {}
    bases = [bean_types.base_name(decl['superclass'], scope)] if decl.get('superclass') else []
    bases += [bean_types.base_name(i, scope) for i in accessors.split_arguments(decl.get('interfaces') or '')]
    ctx = Context(item, universe, base_overloads, base_members, interface)
    ctx.d_defaults = d_defaults  # D interface symbols declaring `mixin template Defaults`, when known
    if ctx.throwable and base_overloads is None:
        if accessors.parent_of(universe, type_id) not in accessors.D_THROWABLES:
            raise accessors.Unsupported('a Throwable subclass whose D base constructors are unknown')
        ctx.base_overloads = [['string msg', 'string file = __FILE__', 'ulong line = cast(ulong)__LINE__',
                               'Throwable nextInChain = null']]
    if ctx.throwable and not any(bean_types.file_line_at(p) is not None for p in ctx.base_overloads):
        ctx.throwable = False
    rows, pending, bodies = {type_id: ('ported', [])}, {}, []
    names = bean_types.field_names(decl)
    for f in decl['fields']:
        if {'public', 'protected'} & set(f['modifiers']) and 'final' in f['modifiers'] \
                and 'static' not in f['modifiers'] and not interface:
            for d in f['declarators']:
                names[d['name']] = accessors.d_name(d['name']) + '_'  # R24: the private field behind the accessor
    fields, field_members, field_pending, computed = derive_fields(ctx, names)
    pending.update(field_pending)
    members = []
    for text, element, row in field_members:
        rows[element] = row
        if text:
            members.append((None, text))
    if decl.get('initializers'):
        computed = True
    for nested in decl['types']:
        pending[f'{type_id}.{nested["name"]}'] = f'a nested {nested["kind"]} (R13)'
    for ctor in decl['constructors']:
        if len(decl['constructors']) == 1 and not ctor['parameters'] and not computed and not interface \
                and 'public' in ctor['modifiers'] and not ctx.throwable \
                and ' '.join((ctor['body'] or '').split()) in ('{ }', '{}', '{ super(); }'):
            rows[f'{type_id}#<init>()'] = ('ported', [])  # D's implicit default constructor is the same API
            continue
        try:
            text, row, open_body, element = derive_constructor(ctor, ctx, names, computed)
        except accessors.Unsupported as problem:
            sig = '<init>(' + ','.join(erase_type(p['type']) for p in ctor['parameters']) + ')'
            pending[f'{type_id}#{sig}'] = str(problem)
            continue
        rows[element] = row
        members.append((ctor['line'], text))
        if open_body:
            bodies.append(element)
    if computed and not decl['constructors'] and not interface:
        element = f'{type_id}#<init>()'
        members.append((decl['line'], f'this()\n{{\n{body_region(element)}}}'))
        bodies.append(element)  # Java's field initializers or initializer blocks run in the implicit constructor
    mixins = [f'mixin {name}.Defaults;' for name in defaults_of(ctx, bases)] if not ctx.java_interface else []
    java_object = False
    for method in decl['methods']:
        element = f'{type_id}#{accessors.signature(method)}'
        try:
            text, row, open_body = derive_method(method, ctx, plan)
        except accessors.Unsupported as problem:
            pending[element] = str(problem)
            continue
        java_object |= accessors.signature(method) in JAVA_OBJECT
        rows[element] = row
        members.append((method['line'], text))
        if open_body:
            bodies.append(element)
    modifiers = [m for m in ('abstract', 'final') if m in decl['modifiers'] and not interface]
    if plan['kind'] == 'final class' and 'final' not in modifiers:
        modifiers.append('final')
    name = accessors.d_name(decl['name'])
    head = ' '.join(deprecation(decl) + modifiers + ['interface' if interface else 'class', name])
    head += ' : ' + ', '.join(bases) if bases else ''
    blocks = []
    blocks += mixins
    if java_object:
        blocks.append('mixin JavaObject;')
    if fields:
        blocks.append('\n'.join(fields))
    blocks += [text for _, text in sorted(members, key=lambda m: m[0] if m[0] is not None else -1)]
    if ctx.defaults:
        inner_defaults = '\n\n'.join(accessors.indented('    ' + b, '    ') for b in ctx.defaults)
        blocks.append(f'/// R3: implementors mix the default methods in with `mixin {name}.Defaults;`.\n'
                      f'mixin template Defaults()\n{{\n{inner_defaults}\n}}')
    blocks += [f'// port:pending {element}: {reason}' for element, reason in sorted(pending.items())]
    inner = '\n\n'.join(accessors.indented('    ' + b, '    ') for b in blocks)
    text = '\n'.join(ddoc(decl, 0) + [f'{head}\n{{\n{inner}\n}}'])
    return {'text': text, 'name': name, 'rows': rows, 'pending': pending, 'bodies': bodies,
            'imports': dict(scope.used)}


# ---- the corpus ---------------------------------------------------------------------------------------------------

def read(universe, helper, job):
    """{'type', 'job', 'class', 'scope'} for one Java type id, or accessors.Unsupported."""
    path, nested = universe.source(job['project'], job['tag'], job['type'])
    tree = accessors.describe_java(helper, path)
    decl, type_id = tree['type'], job['type'][:len(job['type']) - sum(len(n) + 1 for n in nested)]
    chain = [(type_id, decl)]
    for name in nested:
        decl = next(t for t in decl['types'] if t['name'] == name)
        type_id += '.' + name
        chain.append((type_id, decl))
    return {'type': job['type'], 'job': job, 'class': decl, 'scope': accessors.Scope(universe, tree, chain)}


def corpus(universe, helper, jobs=None):
    """Every hand-ported class and interface, read; and the types not read."""
    items, skipped = [], collections.Counter()
    for job in jobs if jobs is not None else gate.corpus():
        if job['kind'] not in ('class', 'interface'):
            continue
        try:
            items.append(read(universe, helper, job))
        except accessors.Unsupported as problem:
            skipped[str(problem)] += 1
    return items, skipped


# ---- comparison ---------------------------------------------------------------------------------------------------

def api_by_name(description):
    """{D member name: sorted lines} of the non-private, non-package API, without overload indices."""
    found = collections.defaultdict(list)
    for line in description.splitlines():
        parts = line.split()
        if len(parts) > 1 and parts[1] in ('private', 'package'):
            continue
        head = parts[0] if parts else ''
        member = head.split('.', 1)[1].split('#')[0] if '.' in head else ''
        found[member].append(re.sub(r'^(\S+?)#\d+ ', r'\1 ', line))
    return {k: sorted(v) for k, v in found.items()}


ATTRIBUTE = re.compile(r' (?:pure|nothrow|@nogc|@safe|@trusted|@system|@live)(?= )')


def without_attributes(lines):
    """The lines without function attributes, wherever the describer prints them."""
    return [re.sub(r'\)( [\w@ ]*)?$', lambda m: ')' + ''.join(f' {w}' for w in (m.group(1) or '').split()
                                                         if w in ('virtual', 'abstract', 'static', 'final')),
                   ATTRIBUTE.sub('', line + ' ').rstrip()) for line in lines]


def d_member(element):
    """The D member name an element's description lines sit under."""
    signature = element.split('#', 1)[1]
    if signature.startswith('<init>'):
        return '__ctor'
    return accessors.d_name(signature.split('(')[0])


def compare(universe, helper, scratch, compilers=None, log=None, only=None):
    """(items, {type id: result}, {element: result}, derived, skipped)."""
    compilers = compilers or gate.COMPILERS
    jobs = [j for j in gate.corpus() if not only or j['type'] in only]
    items, skipped = corpus(universe, helper, jobs)
    types, elements, derived = {}, {}, {}
    index = gate.module_index(gate.import_roots())
    by_package = collections.defaultdict(list)
    for item in items:
        owners = [gate.package_of(p) for _, p in index.get(item['job']['module'], ())]
        if not owners or owners[0] is None:
            types[item['type']] = {'result': 'rejected', 'reason': f'no package declares {item["job"]["module"]}'}
            continue
        by_package[owners[0]].append(item)
    for package, group in sorted(by_package.items()):
        if log:
            log(f':{package}: {len(group)} types')
        roots = gate.import_paths(package)
        overloads, members, d_defaults = base_facts(universe, group, roots, scratch, compilers[0])
        live = []
        for item in group:
            try:
                inputs = (overloads.get(item['type']), members.get(item['type'], ()), d_defaults)
                derived[item['type']] = {**derive(item, universe, *inputs), 'inputs': inputs}
                live.append(item)
            except accessors.Unsupported as problem:
                types[item['type']] = {'result': 'rejected', 'reason': str(problem)}
        compare_package(package, live, derived, types, elements, roots, index, scratch, compilers)
    for item in items:
        d = derived.get(item['type'])
        if d is None or types.get(item['type'], {}).get('result') == 'rejected':
            continue
        for element, reason in d['pending'].items():
            elements[element] = {'result': 'pending', 'reason': reason}
        for element, (row_status, rules) in d['rows'].items():
            if element == item['type'] or element not in elements:
                continue
            row = universe.row(item['job']['project'], item['job']['tag'], element)
            if row is None or row['status'] not in ('ported', 'adapted'):
                # Beyond the hand port: nothing to reproduce, and its declaration is new work the skeleton adds.
                elements[element] = {'result': 'extra', 'hand': row['status'] if row else None}
            elif (row['status'], row.get('rules', [])) != (row_status, rules):
                gate.diverge(elements, {'type': element}, 'mapping',
                             f"hand {row['status']} {row.get('rules', [])}, porter {row_status} {rules}")
        if d['pending'] and types[item['type']]['result'] == 'reproduced':
            types[item['type']] = {'result': 'diverged', 'kind': 'pending',
                                   'reason': f'{len(d["pending"])} member(s) pending'}
    return items, types, elements, derived, skipped


def base_facts(universe, group, roots, scratch, compiler):
    """({type id: D base constructor parameter lists}, {type id: member names of the D base chain}, {D interface
    symbols that declare `mixin template Defaults`})."""
    bases = {}
    for item in group:
        parent = accessors.parent_of(universe, item['type'])
        row = universe.rows.get(parent) if parent else None
        if row:
            bases[item['type']] = row['d']
    implemented = set()
    for item in group:
        for name in accessors.split_arguments(item['class'].get('interfaces') or ''):
            try:
                full = item['scope'].resolve(accessors.strip_annotations(name)[0].split('<')[0])
            except accessors.Unsupported:
                continue
            if full in universe.rows:
                implemented.add(universe.rows[full]['d'])
    described = {}
    for symbol in sorted(set(bases.values()) | implemented):
        try:
            described.update(accessors.describe(compiler, None, roots, [symbol], scratch))
        except ValueError:
            pass
    ancestors = sorted({line.split()[2] for text in described.values() for line in text.splitlines()
                        if len(line.split()) == 3 and line.split()[1] == 'base'
                        and not line.split()[2].startswith('object.')} - set(described))
    for symbol in ancestors:
        try:
            described.update(accessors.describe(compiler, None, roots, [symbol], scratch))
        except ValueError:
            pass
    overloads, members = {}, {}
    for type_id, symbol in bases.items():
        if symbol not in described:
            continue
        overloads[type_id] = bean_types.constructor_parameters(described[symbol], symbol.rsplit('.', 1)[1])
        chain = [symbol] + [line.split()[2] for line in described[symbol].splitlines()
                            if len(line.split()) == 3 and line.split()[1] == 'base']
        members[type_id] = {m.group(1) for s in chain if s in described
                            for m in re.finditer(r'^\w+\.(\w+)#\d+ (?!private)', described[s], re.M)}
    d_defaults = {symbol for symbol in implemented if symbol in described
                  and re.search(r'^\w+\.Defaults[# ]', described[symbol], re.M)}
    return overloads, members, d_defaults


def compare_package(package, group, derived, types, elements, roots, index, scratch, compilers):
    symbols = sorted({item['job']['symbol'] for item in group})
    if not symbols:
        return
    declaring = gate.locate(roots, symbols, scratch)
    overlay = scratch / 'overlay' / package
    files = collections.defaultdict(list)
    for item in group:
        places = [(r, p) for r, p in index.get(declaring.get(item['job']['symbol'], ''), ()) if r in roots]
        if not places:
            types[item['type']] = {'result': 'diverged', 'kind': 'api',
                                   'reason': 'the hand type is not declared in the package\'s import paths'}
            continue
        modules = {symbol.rsplit('.', 1)[0] for symbol in derived[item['type']]['imports'].values()}
        unreachable = sorted(m for m in modules if not any(r in roots for r, _ in index.get(m, ())))
        if unreachable:
            reason = f':{package} has no DUB dependency declaring ' + ', '.join(unreachable)
            types[item['type']] = {'result': 'diverged', 'kind': 'dependency', 'reason': reason}
            for element in derived[item['type']]['rows']:
                if element != item['type']:
                    elements[element] = {'result': 'diverged', 'kind': 'dependency', 'reason': reason}
            continue
        files[places[0]].append(item)
    live, places_of = [], {}
    for (root, path), file_items in files.items():
        for item in file_items:
            try:
                splice_all([item], {item['type']: (root, path)}, derived)
                places_of[item['type']] = (root, path)
                live.append(item)
            except ValueError as problem:
                types[item['type']] = {'result': 'diverged', 'kind': 'api', 'reason': f'cannot splice: {problem}'}
    for (root, path), text in splice_all(live, places_of, derived).items():
        write_overlay(overlay, root, path, text)
    wanted = sorted({item['job']['symbol'] for item in live})
    if not wanted:
        return
    for item in live:
        types[item['type']] = {'result': 'reproduced', 'shape': SHAPE}
        for element in derived[item['type']]['rows']:
            if element != item['type']:
                elements[element] = {'result': 'reproduced', 'shape': SHAPE}
    for compiler in compilers:
        hand, failed = describe_each(compiler, None, roots, wanted, scratch)
        for item in live:
            if item['job']['symbol'] in failed:
                types[item['type']] = {'result': 'rejected', 'reason': f'{compiler} cannot describe the hand type: '
                                       + failed[item['job']['symbol']]}
                for element in derived[item['type']]['rows']:
                    elements.pop(element, None)
        live = [item for item in live if item['job']['symbol'] not in failed]
        wanted = [symbol for symbol in wanted if symbol not in failed]
        if not wanted:
            return
        try:
            spliced = accessors.describe(compiler, overlay, roots, wanted, scratch)
        except ValueError:
            # Bisect: halves that compile are described together, so one broken skeleton costs log2(n) probes and
            # can't fail its neighbours.
            spliced = {}
            pending_groups = [live[:len(live) // 2], live[len(live) // 2:]]
            while pending_groups:
                subset = pending_groups.pop()
                if not subset:
                    continue
                alone = scratch / 'overlay-alone' / package
                if alone.exists():
                    shutil.rmtree(alone)
                for (root, path), text in splice_all(subset, places_of, derived).items():
                    write_overlay(alone, root, path, text)
                try:
                    spliced.update(accessors.describe(compiler, alone, roots,
                                                      sorted({i['job']['symbol'] for i in subset}), scratch))
                except ValueError as problem:
                    if len(subset) > 1:
                        pending_groups += [subset[:len(subset) // 2], subset[len(subset) // 2:]]
                        continue
                    item = subset[0]
                    reason = f'{compiler}: the spliced :{package} does not compile: ' + accessors.first_error(str(problem))
                    gate.diverge(types, {'type': item['type']}, 'compile', reason)
                    for element in derived[item['type']]['rows']:
                        if element != item['type']:
                            gate.diverge(elements, {'type': element}, 'compile', reason)
        for item in live:
            symbol = item['job']['symbol']
            if symbol not in spliced:
                continue
            before, after = api_by_name(hand[symbol]), api_by_name(spliced[symbol])
            if before != after:
                differing = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
                gate.diverge(types, {'type': item['type']}, 'api',
                             f'{compiler}: {len(differing)} member name(s) differ, first {differing[0] or "<type>"}')
            for element in derived[item['type']]['rows']:
                if element == item['type']:
                    continue
                member = d_member(element) if '#' in element else None
                if member is None:
                    continue
                if before.get(member) != after.get(member):
                    kind = 'attributes' if without_attributes(before.get(member, [])) == \
                        without_attributes(after.get(member, [])) else 'api'
                    detail = gate.first_difference('\n'.join(before.get(member, [])), '\n'.join(after.get(member, [])))
                    gate.diverge(elements, {'type': element}, kind, f'{compiler}: {detail}')


def splice_all(items, places_of, derived):
    """{(root, path): module text} with every item's skeleton spliced over its hand type."""
    texts = {}
    for item in items:
        root, path = places_of[item['type']]
        text = texts.get((root, path)) or path.read_text(encoding='utf-8')
        d = derived[item['type']]
        texts[(root, path)] = gate.splice_one(text, item['job']['symbol'].rsplit('.', 1)[1],
                                              with_imports(d['text'], text, d['imports']))
    return texts


def describe_each(compiler, overlay, roots, symbols, scratch):
    """({symbol: description}, {symbol: first error}): one probe for all, then one per symbol if that fails (a
    compiler crash on one type mustn't hide the rest)."""
    try:
        return accessors.describe(compiler, overlay, roots, symbols, scratch), {}
    except ValueError:
        pass
    found, failed = {}, {}
    for symbol in symbols:
        try:
            found.update(accessors.describe(compiler, overlay, roots, [symbol], scratch))
        except ValueError as problem:
            message = str(problem)
            failed[symbol] = 'compiler crash' if 'Stack dump' in message else accessors.first_error(message)
    return found, failed


def write_overlay(overlay, root, path, text):
    destination = overlay / path.relative_to(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding='utf-8')


def with_imports(text, module, used=None):
    """The type text behind the selective imports it needs that `module` lacks: rulebook types, `JavaObject` and
    every mapped D type the skeleton names (`used`, {D name: symbol})."""
    own = re.search(r'^module\s+([\w.]+)\s*;', module, re.M)
    lines = []
    for name, symbol in sorted((used or {}).items()):
        home = symbol.rsplit('.', 1)[0]
        if (own and own.group(1) == home) or re.search(rf'\bimport\s+[^;]*\b{name}\b', module) \
                or re.search(rf'\b(?:class|interface|struct|enum|alias)\s+{name}\b', module):
            continue
        lines.append(f'import {home} : {name};\n')
    if 'mixin JavaObject;' in text and not re.search(r'\bimport\s+[^;]*\bJavaObject\b', module):
        lines.append('import flint.java.lang.javaobject : JavaObject;\n')
    return ''.join(lines) + bean_types.with_imports(text, module)


def summarise(items, types, elements, skipped):
    totals = collections.Counter(r['result'] for r in types.values())
    totals['types'] = len(items)
    element_totals = collections.Counter(r['result'] for r in elements.values())
    kinds = collections.Counter(k for r in elements.values() if r['result'] == 'diverged' for k in r['kind'].split('+'))
    type_kinds = collections.Counter(k for r in types.values() if r['result'] == 'diverged' for k in r['kind'].split('+'))
    rejected = collections.Counter(re.sub(r'(base|plan kind|annotation @?)\s?\S+', r'\1 X', r['reason'])
                                   for r in types.values() if r['result'] == 'rejected')
    pending = collections.Counter(re.sub(r'type \S+ is', 'type X is', r['reason'])
                                  for r in elements.values() if r['result'] == 'pending')
    declared = element_totals['reproduced'] + element_totals['diverged']
    return {'types': dict(totals), 'elements': dict(element_totals),
            'typeRate': round(totals['reproduced'] / len(items), 4) if items else 0.0,
            'elementRate': round(element_totals['reproduced'] / declared, 4) if declared else 0.0,
            'typeDivergenceKinds': dict(type_kinds), 'elementDivergenceKinds': dict(kinds),
            'rejected': dict(rejected.most_common()), 'pending': dict(pending.most_common(40)),
            'typesNotRead': dict(skipped)}


# ---- yield --------------------------------------------------------------------------------------------------------

def deferred_types(universe):
    """Every public class and interface of a pinned, mapped upstream whose type row is not ported."""
    jobs = []
    for path in sorted((ROOT / 'api' / 'upstream').glob('*.json')):
        manifest = gate.load_json(path)
        pin = universe.pins.get((manifest['project'], manifest['version']))
        if pin is None or pin.get('repo') not in universe.classifiers or pin.get('signatures_only'):
            continue
        classifier = universe.classifiers[pin['repo']]
        for t in manifest['types']:
            if t.get('visibility') != 'public' or t['kind'] not in ('class', 'interface'):
                continue
            found = classifier.classify(t['id'])
            if found and found[1].get('status') in ('ported', 'adapted', 'excluded') \
                    and found[1].get('category') != 'deferred':
                continue
            jobs.append({'project': manifest['project'], 'tag': manifest['version'], 'type': t['id'],
                         'kind': t['kind'], 'members': len(t.get('members', ()))})
    return jobs


def yield_report(universe, helper):
    """How many deferred classes and interfaces get a skeleton, and how many of their elements it declares."""
    jobs = deferred_types(universe)
    totals, rejected, pending = collections.Counter(), collections.Counter(), collections.Counter()
    for job in jobs:
        totals['types'] += 1
        try:
            item = read(universe, helper, job)
            plan_kind = 'interface' if item['class']['kind'] == 'interface' else 'class'
            if 'final' in item['class']['modifiers'] and plan_kind == 'class':
                plan_kind = 'final class'
            d = derive({**item, 'default_plan': {'kind': plan_kind}}, universe)
        except accessors.Unsupported as problem:
            rejected[re.sub(r'(base|type|plan kind|annotation @?)\s?\S+', r'\1 X', str(problem))] += 1
            continue
        totals['skeletons'] += 1
        totals['complete' if not d['pending'] else 'partial'] += 1
        totals['declared'] += len(d['rows'])
        totals['bodies'] += len(d['bodies'])
        totals['mechanical'] += len(d['rows']) - 1 - len(d['bodies'])
        totals['pendingDeclarations'] += len(d['pending'])
        for reason in d['pending'].values():
            pending[re.sub(r'type \S+ is', 'type X is', reason)] += 1
    return {'totals': dict(totals), 'rejected': dict(rejected.most_common(25)),
            'pending': dict(pending.most_common(25))}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--helper', required=True, type=Path)
    parser.add_argument('--cache', required=True, type=Path, help='the api cache holding the pinned sources')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compare', action='store_true')
    mode.add_argument('--render', metavar='TYPE', help='print the skeleton for one Java type id')
    mode.add_argument('--yield', dest='yield_', action='store_true', help='deferred types the rules can skeleton')
    parser.add_argument('--predict', action='store_true', help='with --yield: name unmapped pinned types by R1, '
                        'as if their skeletons were generated in the same batch')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--only', action='append', help='compare one Java type id; repeatable (development)')
    args = parser.parse_args(argv)
    universe = accessors.Universe(args.cache.resolve())
    universe.predict = args.predict and args.yield_
    if args.render:
        project, tag, manifest_type = universe.types[args.render]
        job = {'project': project, 'tag': tag, 'type': args.render, 'kind': manifest_type['kind']}
        try:
            item = read(universe, args.helper, job)
            kind = 'interface' if item['class']['kind'] == 'interface' else 'class'
            d = derive({**item, 'default_plan': {'kind': kind}}, universe)
        except accessors.Unsupported as problem:
            print(f'error: {problem}', file=sys.stderr)
            return 2
        print(d['text'])
        for element, (row_status, rules) in sorted(d['rows'].items()):
            pending = ' (body pending)' if element in d['bodies'] else ''
            print(f'// row {element}: {row_status} {rules}{pending}')
        return 0
    if args.yield_:
        result = yield_report(universe, args.helper)
    else:
        with tempfile.TemporaryDirectory(prefix='flint-skeletons-') as directory:
            items, types, elements, _, skipped = compare(universe, args.helper, Path(directory),
                                                         log=lambda m: print(m, file=sys.stderr), only=args.only)
        result = summarise(items, types, elements, skipped)
        result['types'] = result.pop('types')
        result['results'] = {'types': dict(sorted(types.items())), 'elements': dict(sorted(elements.items()))}
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=1, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())
