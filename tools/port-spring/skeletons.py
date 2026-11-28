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
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
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


STRIPPED = 'the body is not written yet (--strip-pending)'


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
        self.filled = {}    # element -> the lines a lane wrote in its port:body region (emit mode)
        self.strip = False  # --strip-pending: leave out every member whose body is still the placeholder

    def body(self, element, indent='    '):
        """The member's body region: the lane's lines when written, otherwise the placeholder, or StripPending."""
        written = self.filled.get(element)
        if written is not None:
            inner = ''.join(f'{indent}{line}\n' if line else '\n' for line in written)
            return f'{indent}// port:body {element}\n{inner}{indent}// port:end-body\n'
        if self.strip:
            raise accessors.StripPending(STRIPPED)
        return body_region(element, indent)


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
    # The function attributes a lane recorded for this member in the type's port plan (`"methods"` keyed by the
    # Java signature, e.g. `"applyRelativePath(String,String)": ["pure", "nothrow"]`). A hand port's mechanical
    # bodies often carry `pure nothrow @nogc` that no rule can infer from the Java declaration, so it is plan data
    # the way an accessor's attributes are.
    extra = plan.get('methods', {}).get(sig, ())
    suffix = (' ' + ' '.join(extra)) if extra else ''
    text = ' '.join(prefix + [head]) + suffix
    if default:
        rules.add('R3')
    if not body:
        return '\n'.join(ddoc(method) + [text + ';']), status(rules), False
    if default and ctx.interface:
        # R3: the interface declares it, and `mixin template Defaults` carries the body for implementors.
        ctx.defaults.append('\n'.join(ddoc(method, 8) + [f'{text}\n{{\n{ctx.body(element)}}}']))
        return '\n'.join(ddoc(method) + [text + ';']), status(rules), element not in ctx.filled
    return '\n'.join(ddoc(method) + [f'{text}\n{{\n{ctx.body(element)}}}']), status(rules), element not in ctx.filled


def super_call_fits(text, overloads):
    """Whether a mechanical constructor's `super(...)` call (an implicit `super()` when it has none) takes as many
    arguments as one of the landed D base's constructors accepts; `overloads` empty is D's implicit default."""
    if re.search(r'^\s*this\(.*\);$', text, re.M):
        return True
    call = re.search(r'^\s*super\((.*)\);$', text, re.M)
    count = len(accessors.split_arguments(call.group(1))) if call else 0
    return any(sum('=' not in p for p in params) <= count <= len(params) for params in overloads or [[]])


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
            if not ctx.throwable and ctx.base_overloads is not None and not super_call_fits(text, ctx.base_overloads):
                raise accessors.Unsupported('no constructor taking these arguments in the D base')
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
    return ('\n'.join(ddoc(ctor) + [f'{text}\n{{\n{ctx.body(element)}}}']), status(rules), element not in ctx.filled,
            element)


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
                    if visibility != 'private':
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
        row = accessors.mapped_row(ctx.universe, full)  # a batch type's predicted row too (emit mode)
        if ctx.d_defaults is not None and row is not None:
            if row['d'] in ctx.d_defaults:
                found.append(d_name)
            continue  # a landed D interface decides by what it declares
        entry = ctx.universe.types.get(full)
        if entry is None or ctx.universe.plans.get(full, {}).get('kind', 'interface') != 'interface':
            continue
        if any('default' in m.get('modifiers', ()) for m in entry[2].get('members', ()) if m.get('kind') == 'method'):
            found.append(d_name)
    return found


def derive(item, universe, base_overloads=None, base_members=(), d_defaults=None, filled=None, strip=False):
    """{'text', 'name', 'rows': {element: (status, rules)}, 'pending': {element: reason}, 'bodies': [element]}.

    `bodies` lists the elements whose body is still the placeholder. Emit mode passes `filled`, {element: lines} of
    the bodies lanes wrote, and `strip`, which leaves out every member whose body is not written."""
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
    ctx.filled, ctx.strip = filled or {}, strip
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
    constructors, stripped = 0, False
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
            stripped |= isinstance(problem, accessors.StripPending)
            continue
        constructors += 1
        rows[element] = row
        members.append((ctor['line'], text))
        if open_body:
            bodies.append(element)
    if computed and not decl['constructors'] and not interface:
        element = f'{type_id}#<init>()'
        try:
            members.append((decl['line'], f'this()\n{{\n{ctx.body(element)}}}'))
            if element not in ctx.filled:
                bodies.append(element)  # Java's field initializers or initializer blocks run in the implicit constructor
        except accessors.StripPending as problem:
            pending[element] = str(problem)
            stripped = True
    if stripped and not constructors and not interface:
        # Every constructor is left out: D's implicit default constructor would be API Java doesn't have.
        members.append((decl['line'], '@disable this();'))
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
    text = '\n'.join(ddoc(decl, 0) + [f'{head}\n{{\n{inner}\n}}' if inner else f'{head}\n{{\n}}'])
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
        reachable = {m for m, places in index.items() if any(r in roots for r, _ in places)}
        for item in group:
            item['scope'].reachable = reachable
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


def base_facts(universe, group, roots, scratch, compiler, overlay=None):
    """({type id: D base constructor parameter lists}, {type id: member names of the D base chain}, {D interface
    symbols that declare `mixin template Defaults`}). Emit mode passes the batch's `overlay`, so a base generated
    in the same batch (a predicted row) is described as it will land."""
    bases = {}
    for item in group:
        parent = accessors.parent_of(universe, item['type'])
        row = accessors.mapped_row(universe, parent) if parent else None
        if row:
            bases[item['type']] = row['d']
    implemented = set()
    for item in group:
        for name in accessors.split_arguments(item['class'].get('interfaces') or ''):
            try:
                full = item['scope'].resolve(accessors.strip_annotations(name)[0].split('<')[0])
            except accessors.Unsupported:
                continue
            row = accessors.mapped_row(universe, full)
            if row is not None:
                implemented.add(row['d'])
    described = {}
    for symbol in sorted(set(bases.values()) | implemented):
        try:
            described.update(accessors.describe(compiler, overlay, roots, [symbol], scratch))
        except ValueError:
            pass
    ancestors = sorted({line.split()[2] for text in described.values() for line in text.splitlines()
                        if len(line.split()) == 3 and line.split()[1] == 'base'
                        and not line.split()[2].startswith('object.')} - set(described))
    for symbol in ancestors:
        try:
            described.update(accessors.describe(compiler, overlay, roots, [symbol], scratch))
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
        if (own and own.group(1) == home) or re.search(rf'^(?:public\s+|private\s+|static\s+)*import\s[^;]*\b{name}\b',
                                                        module, re.M) \
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
            d = derive({**item, 'default_plan': default_plan(item)}, universe)
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

# ---- emit ---------------------------------------------------------------------------------------------------------

GENERATOR = 'port-skeleton/1'
PLACEHOLDER = re.compile(r'\s*assert\(0, "port:body [^"]*"\);\s*')
LICENCE_LINES = {('port-source', 'Apache-2.0'): 'Licensed under the Apache License, Version 2.0',
                 ('port-source', 'MIT'): 'Licensed under the MIT License'}


def licence_line(entry):
    """flint_tool.api.headers.licenceLine for the uses a skeleton may be generated under: source ports only."""
    if entry.get('use') == 'port-source-bsd-option':
        return 'Licensed under the BSD 3-Clause License'
    if entry.get('use') == 'port-source' and entry.get('licence', '').startswith('BSD-'):
        return 'Licensed under the BSD'
    return LICENCE_LINES.get((entry.get('use'), entry.get('licence')))


def licence_of(universe, project, tag):
    """The licence matrix entry a source port of the pin is made under, or accessors.Unsupported."""
    pin = universe.pins[(project, tag)]
    if not hasattr(universe, '_matrix'):
        universe._matrix = {e['name']: e for e in gate.load_json(ROOT / 'policy' / 'upstream-licences.json')['projects']}
    entry = universe._matrix.get(pin.get('matrix', project))
    if entry is None:
        raise accessors.Unsupported(f'{pin.get("matrix", project)} has no entry in policy/upstream-licences.json')
    if licence_line(entry) is None:
        raise accessors.Unsupported(f'{entry["name"]} is `{entry.get("use")}` ({entry.get("licence")}): skeletons '
                                    'are generated only for source ports into packages without a licence of their own')
    return entry


def default_plan(item):
    """The plan a type without a port plan entry gets: its Java kind."""
    kind = 'interface' if item['class']['kind'] == 'interface' else 'class'
    return {'kind': 'final class' if kind == 'class' and 'final' in item['class']['modifiers'] else kind}


def written_bodies(text):
    """({element: lines a lane wrote}, {element of every body still holding its placeholder}) of a D source: each
    line relative to its marker's indentation."""
    filled, open_ = {}, set()
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith(gate.BODY):
            element, indent = stripped[len(gate.BODY):].strip(), lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            j = i + 1
            while j < len(lines) and lines[j].strip() != gate.BODY_END:
                j += 1
            inner = lines[i + 1:j]
            if len(inner) == 1 and PLACEHOLDER.fullmatch(inner[0]):
                open_.add(element)
            else:
                filled[element] = [line[len(indent):] if line.startswith(indent) else line.strip() for line in inner]
            i = j
        i += 1
    return filled, open_


def placeholders(text):
    """The elements whose port:body region still holds its `assert(0)` (gate (d): none may land on main)."""
    return sorted(written_bodies(text)[1])


def place_of(module, index, planned=()):
    """(root, path, whether it exists) of the file that holds a D module: its declaring file, or a new one in the
    source root of its nearest declared parent module (`package.d` when the module has children, declared or
    `planned` in the same batch)."""
    if module in index:
        root, path = index[module][0]
        return root, path, True
    parts = module.split('.')
    for cut in range(len(parts) - 1, 0, -1):
        parent = '.'.join(parts[:cut])
        if parent in index:
            root, parent_path = index[parent][0]
            if parent_path.name != 'package.d':
                raise accessors.Unsupported(f'{parent} is declared in {parent_path.name}: a module with children '
                                            'uses package.d (AGENTS.md)')
            break
    else:
        raise accessors.Unsupported(f'no source root declares a parent module of {module}')
    base = root.joinpath(*parts)
    children = any(m.startswith(module + '.') for m in [*index, *planned])
    return root, (base / 'package.d' if children else base.with_suffix('.d')), False


def hand_declares(text, type_id, name):
    """Whether a module declares `name` outside the type's own generated region."""
    for line, _, _, found, _, body in gate.regions(text):
        if found == type_id:
            lines = text.splitlines(keepends=True)
            text = ''.join(lines[:line - 1] + lines[line + len(body.splitlines()) + 1:])
    return re.search(rf'\b(?:class|interface|struct|enum|union|alias|template)\s+{re.escape(name)}\b', text) is not None


def region_of(item, d):
    """The type's generated region: marker, skeleton text and end marker (porter_gate's digest rules)."""
    body = d['text'] + '\n'
    digest = hashlib.sha256(gate.digest_text(body).encode()).hexdigest()
    job = item['job']
    return f'{gate.MARKER}{GENERATOR} {job["project"]}@{job["tag"]} {item["type"]} sha256:{digest}\n{body}{gate.END}\n'


def module_header(universe, group):
    """The new module's licence header: the first Java file's own header, the ported-from marker, the licence line
    and the modification notice (flint_tool.api.portspring's form, several files)."""
    jobs = sorted((item['job'] for item in group), key=lambda j: j['type'])
    project, tag = jobs[0]['project'], jobs[0]['tag']
    if any((j['project'], j['tag']) != (project, tag) for j in jobs):
        raise accessors.Unsupported('one module ported from two upstreams')
    entry = licence_of(universe, project, tag)
    java = Path(universe.source(project, tag, jobs[0]['type'])[0]).read_text(encoding='utf-8').lstrip()
    header = java[:java.index('*/') + 2] if java.startswith('/*') else ''.join(
        line + '\n' for line in java.splitlines() if line.startswith('//'))
    files = sorted({universe.types[j['type']][2].get('file', '') for j in jobs})
    directory = files[0].rsplit('/', 1)[0] if all(f.rsplit('/', 1)[0] == files[0].rsplit('/', 1)[0] for f in files) \
        else None
    names = [f.rsplit('/', 1)[1] for f in files] if directory else files
    lines = [f'// {line}' for line in wrap(', '.join(names), 113)]
    marker = f'// Ported from {project} {tag}: ' + (directory + '/' if directory else '')
    return (header.rstrip('\n') + '\n' + marker + '\n' + '\n'.join(lines) + '\n'
            + f'// {licence_line(entry)}\n// Modified by the Flint authors.\n\n')


def import_block(module_text, types_text, used):
    """The selective imports `types_text` needs that `module_text` lacks."""
    full = with_imports(types_text, module_text, used)
    return full[:len(full) - len(types_text)]


def merged(existing, regions, imports):
    """An existing module with each type's region replaced, new regions appended and missing imports added."""
    text = existing
    for type_id, region in regions.items():
        lines = text.splitlines(keepends=True)
        for line, _, _, found, _, body in gate.regions(text):
            if found == type_id:
                end = line + len(body.splitlines())  # the index of `// port:end`, counting the marker as line 1
                text = ''.join(lines[:line - 1]) + region + ''.join(lines[end + 1:])
                break
        else:
            text = text.rstrip('\n') + '\n\n' + region
    if imports:
        tops = [m for m in re.finditer(r'^(?:public\s+)?import\s[^;]*;\n', text, re.M)]
        at = tops[-1].end() if tops else re.search(r'^module\s+[\w.]+\s*;\n', text, re.M).end()
        text = text[:at] + ('' if tops else '\n') + imports + text[at:]
    return text


def render(universe, items, derived):
    """{(root, path): module text} for every derived type, grouped by destination file."""
    files = collections.defaultdict(list)
    for item in items:
        if item['type'] in derived:
            files[item['place']].append(item)
    out = {}
    for (root, path), group in sorted(files.items(), key=lambda f: str(f[0][1])):
        group.sort(key=lambda item: item['type'])
        regions = {item['type']: region_of(item, derived[item['type']]) for item in group}
        used = {}
        for item in group:
            used.update(derived[item['type']]['imports'])
        types_text = '\n'.join(regions.values())
        module = group[0]['module']
        if path.is_file():
            existing = path.read_text(encoding='utf-8')
            out[(root, path)] = merged(existing, regions, import_block(existing, types_text, used))
            continue
        java_package = universe.types[group[0]['type']][2].get('package', '')
        head = module_header(universe, group) + f'/// The Java package `{java_package}`.\nmodule {module};\n\n'
        imports = import_block(head, types_text, used)
        out[(root, path)] = head + imports + ('\n' if imports else '') + '@safe:\n\n' + '\n'.join(regions.values())
    return out


def batch_items(universe, helper, type_ids, index):
    """({type id: item with its destination}, {type id: reason it can't be emitted})."""
    universe.predict, universe.batch = True, set(type_ids)
    items, rejected = {}, {}
    planned = {row['d'].rsplit('.', 1)[0] for row in map(lambda t: accessors.mapped_row(universe, t), type_ids) if row}
    for type_id in sorted(type_ids):
        try:
            if type_id not in universe.types:
                raise accessors.Unsupported('not a type of a pinned manifest')
            project, tag, manifest_type = universe.types[type_id]
            licence_of(universe, project, tag)
            item = read(universe, helper, {'project': project, 'tag': tag, 'type': type_id,
                                           'kind': manifest_type['kind']})
            row = accessors.mapped_row(universe, type_id)
            if row is None:
                raise accessors.Unsupported('no D module: no enclosing Java package is mapped (R1)')
            module = row['d'].rsplit('.', 1)[0]
            root, path, _ = place_of(module, index, planned)
            package = gate.package_of(path)
            if package is None:
                raise accessors.Unsupported(f'no DUB package holds {path}')
            if path.is_file() and hand_declares(path.read_text(encoding='utf-8'), type_id, row['d'].rsplit('.', 1)[1]):
                raise accessors.Unsupported(f'{module} already declares {row["d"].rsplit(".", 1)[1]} by hand; map '
                                            'its rows instead')
        except accessors.Unsupported as problem:
            rejected[type_id] = str(problem)
            continue
        items[type_id] = {**item, 'default_plan': default_plan(item), 'module': module, 'symbol': row['d'],
                          'place': (root, path), 'package': package}
    return items, rejected


def emit(universe, helper, type_ids, scratch, filled=None, strip=False, passes=8, log=None):
    """Skeletons for a batch of Java types, generated together: {'files': {(root, path): text}, 'derived': {type id:
    skeleton}, 'items', 'rejected': {type id: reason}}.

    The D facts each skeleton depends on (base constructors, the base chain's members, which interfaces declare
    `Defaults`) are read from the tree with the batch's own output overlaid, again until the output stops changing,
    so a base generated in the same batch is used as it will land and regenerating from the committed tree gives
    the same text."""
    index = gate.module_index(gate.import_roots())
    items, rejected = batch_items(universe, helper, type_ids, index)
    if filled is None:  # bodies already written in the destination files carry over
        filled = {}
        for path in sorted({item['place'][1] for item in items.values() if item['place'][1].is_file()}):
            filled.update(written_bodies(path.read_text(encoding='utf-8'))[0])
    by_package = collections.defaultdict(list)
    for item in items.values():
        by_package[item['package']].append(item)
    overlay = scratch / 'emit-overlay'
    files, derived, reasons = None, {}, {}
    for number in range(passes):
        derived, reasons = {}, {}
        for package, group in sorted(by_package.items()):
            roots = gate.import_paths(package)
            overloads, members, d_defaults = base_facts(universe, group, roots, scratch, gate.COMPILERS[0],
                                                        overlay if number else None)
            reachable = {m for m, places in index.items() if any(r in roots for r, _ in places)}
            reachable |= {i['module'] for i in items.values() if i['place'][0] in roots}
            for item in group:
                inputs = (overloads.get(item['type']), members.get(item['type'], ()), d_defaults)
                try:
                    d = derive(item, universe, *inputs, filled=filled, strip=strip)
                    unreachable = sorted({s.rsplit('.', 1)[0] for s in d['imports'].values()} - reachable)
                    if unreachable:
                        raise accessors.Unsupported(f':{package} has no DUB dependency declaring '
                                                    + ', '.join(unreachable))
                    derived[item['type']] = {**d, 'inputs': inputs}
                except accessors.Unsupported as problem:
                    reasons[item['type']] = str(problem)
        rendered = render(universe, list(items.values()), derived)
        if log:
            log(f'pass {number + 1}: {len(derived)} skeletons in {len(rendered)} modules')
        # A type the batch can't generate gets no predicted row, so its users wait too; one that derives once its
        # base is overlaid gets it back.
        changed, universe.batch = universe.batch != set(derived), set(derived)
        if rendered == files and not changed:
            break
        files = rendered
        if overlay.exists():
            shutil.rmtree(overlay)
        for (root, path), text in files.items():
            write_overlay(overlay, root, path, text)
    return {'files': files or {}, 'derived': derived, 'items': items, 'rejected': {**rejected, **reasons},
            'overlay': overlay}


def compile_check(result, scratch, compilers=None):
    """[(module, compiler, first error, {type id: the first error inside its region})] for every emitted module
    that doesn't compile against its package."""
    problems = []
    modules = {}
    for item in result['items'].values():
        if item['type'] in result['derived']:
            modules[item['module']] = (item['package'], item['place'])
    for module, (package, (root, path)) in sorted(modules.items()):
        roots = gate.import_paths(package)
        source = result['overlay'] / path.relative_to(root)
        for compiler in compilers or gate.COMPILERS:
            run = subprocess.run([compiler, '-o-', '-d', '-preview=dip1000', f'-I{result["overlay"]}',
                                  *(f'-I{r}' for r in roots), str(source)], cwd=scratch, capture_output=True,
                                 text=True, env=gate.compiler_env(), check=False)
            if run.returncode:
                spans = [(line, line + len(body.splitlines()), type_id)
                         for line, _, _, type_id, _, body in gate.regions(source.read_text(encoding='utf-8'))]
                culprits = {}
                for n, message in re.findall(rf'^{re.escape(str(source))}\((\d+)[,\d]*\): (Error: .*)$', run.stderr,
                                             re.M):
                    for start, end, type_id in spans:
                        if start < int(n) <= end:
                            culprits.setdefault(type_id, message.strip())
                problems.append((module, compiler, accessors.first_error(run.stderr), culprits))
    return problems


def member_symbol(symbol, element):
    """The D symbol a member row names: `Type.name`, `Type.this` for a constructor."""
    member = d_member(element)
    return f'{symbol}.{"this" if member == "__ctor" else member}'


def rows_of(universe, result):
    """{repo: {element: row}}: the type row and every declared element whose body is derived or written, with
    provenance. Pending members and placeholder bodies keep their deferred rows."""
    out = collections.defaultdict(dict)
    for type_id, d in sorted(result['derived'].items()):
        item = result['items'][type_id]
        repo = universe.pins[(item['job']['project'], item['job']['tag'])]['repo']
        for element, (row_status, rules) in sorted(d['rows'].items()):
            if element in d['bodies']:
                continue
            row = {'status': row_status, 'd': item['symbol'] if element == type_id
                   else member_symbol(item['symbol'], element)}
            if rules:
                row['rules'] = rules
            row['generated'] = GENERATOR
            out[repo][element] = row
    return out


def merge_rows(path, rows):
    """Write rows into a mapping.json (one element per line): an existing key's line is replaced, a new key goes
    after the last line of its type, or at the end. A hand row that is ported or adapted is never replaced; the
    refused elements are returned."""
    lines = path.read_text(encoding='utf-8').split('\n')
    start = next(n for n, line in enumerate(lines) if line.startswith('"elements":'))

    def is_element(n, line):
        return n > start and line.startswith('"') and '":{' in line

    element_lines = [n for n, line in enumerate(lines) if is_element(n, line)]
    keys = {json.loads(lines[n].split('":{', 1)[0] + '"'): n for n in element_lines}
    by_type = collections.defaultdict(list)
    for key, n in keys.items():
        by_type[re.split(r'[#*]', key, 1)[0]].append(n)
    refused, inserts = [], collections.defaultdict(list)
    for element, row in sorted(rows.items()):
        text = json.dumps(element) + ':' + json.dumps(row, separators=(',', ':'))
        if element in keys:
            old = json.loads('{' + lines[keys[element]].rstrip(',') + '}')[element]
            if old.get('status') in ('ported', 'adapted') and not old.get('generated'):
                refused.append(element)
            else:
                lines[keys[element]] = text
            continue
        anchors = by_type.get(element.split('#', 1)[0])
        inserts[max(anchors) if anchors else element_lines[-1]].append(text)
    out = []
    for n, line in enumerate(lines):
        out.append(line)
        out += inserts.get(n, [])
    last = max(n for n, line in enumerate(out) if is_element(n, line))
    out = [(line.rstrip(',') + (',' if n < last else '')) if is_element(n, line) else line
           for n, line in enumerate(out)]
    path.write_text('\n'.join(out), encoding='utf-8')
    return refused


def emit_types(universe, selectors):
    """The public top-level classes and interfaces a list of Java packages or type ids names that are deferred or
    already carry a skeleton (re-emission)."""
    deferred = {j['type'] for j in deferred_types(universe)}
    deferred |= {t for t, row in universe.rows.items() if str(row.get('generated', '')).startswith('port-skeleton/')}
    found = set()
    for selector in selectors:
        if selector in universe.types:
            found.add(selector)
            continue
        found |= {t for t in deferred if universe.types[t][2].get('package') == selector
                  and t == f'{selector}.{t[len(selector) + 1:]}' and '.' not in t[len(selector) + 1:]}
    return sorted(found)


def regenerate(universe, helper, found, scratch):
    """Gate (a)/(d) for committed skeleton regions: each file's regions derived again from the tree, with the bodies
    the file holds; a placeholder-free region is derived with --strip-pending. Returns failures."""
    failures = []
    by_file = collections.defaultdict(list)
    for rel, line, version, upstream, type_id, body in found:
        by_file[rel].append((line, version, type_id, body))
    for rel, entries in sorted(by_file.items()):
        text = (ROOT / rel).read_text(encoding='utf-8')
        filled, open_ = written_bodies(text)
        type_ids = [type_id for _, _, type_id, _ in entries]
        result = emit(universe, helper, type_ids, scratch, filled=filled, strip=not open_, passes=1)
        for line, version, type_id, body in entries:
            d = result['derived'].get(type_id)
            if d is None:
                failures.append(f'{rel}:{line}: {type_id} no longer gets a skeleton: '
                                + result['rejected'].get(type_id, 'unknown'))
                continue
            again = region_of(result['items'][type_id], d)
            if version != GENERATOR or gate.digest_text(again.split('\n', 1)[1].rsplit(gate.END, 1)[0]) \
                    != gate.digest_text(body):
                failures.append(f'{rel}:{line}: regenerating {type_id} with {GENERATOR} differs from the committed '
                                'region; regenerate it (skeletons.py --emit --in-place) in the same commit as the '
                                'porter or plan change')
    return failures


def emit_main(args, universe):
    types = emit_types(universe, args.emit)
    if not types:
        print('error: no deferred public class or interface matches', file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix='flint-skeleton-emit-') as directory:
        scratch = Path(directory)
        dropped, places = {}, {}
        for _ in range(6):
            result = emit(universe, args.helper, [t for t in types if t not in dropped], scratch,
                          strip=args.strip_pending, log=lambda m: print(m, file=sys.stderr))
            places.update((t, i['place']) for t, i in result['items'].items() if t not in places)
            problems = compile_check(result, scratch)
            if not problems or not any(found for _, _, _, found in problems):
                break
            # A type the errors point into (a stripped member its interface needs, a base constructor D lacks)
            # stays out of the batch; every other type is generated again without it.
            for _, compiler, _, found in problems:
                for type_id, error in found.items():
                    dropped.setdefault(type_id, f'does not compile ({compiler}): {error}')
        result['rejected'].update(dropped)
        kept = sorted(t for t in result['rejected'] if t in places and places[t][1].is_file()
                      and any(found == t for _, _, _, found, _, _ in
                              gate.regions(places[t][1].read_text(encoding='utf-8'))))
        rows = rows_of(universe, result)
        open_bodies = sorted(e for d in result['derived'].values() for e in d['bodies'])
        summary = {'types': len(types), 'skeletons': len(result['derived']), 'modules': len(result['files']),
                   'declared': sum(len(d['rows']) for d in result['derived'].values()),
                   'openBodies': len(open_bodies), 'rows': sum(len(r) for r in rows.values()),
                   'pending': sum(len(d['pending']) for d in result['derived'].values()),
                   'rejected': dict(sorted(result['rejected'].items())),
                   'compileErrors': [f'{m} ({c}): {e}' for m, c, e, _ in problems],
                   'keptRegions': kept}
        print(json.dumps(summary, indent=1))
        if problems:
            print('error: the skeletons do not compile; nothing written', file=sys.stderr)
            return 1
        if args.in_place:
            refused = []
            for (root, path), text in result['files'].items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8')
            if not args.strip_pending:
                print('note: a draft writes no mapping rows; emit with --strip-pending once the bodies are written '
                      '(only that output lands)', file=sys.stderr)
            for repo, repo_rows in (rows.items() if args.strip_pending else ()):
                refused += merge_rows(ROOT / 'api' / repo / 'mapping.json', repo_rows)
            if refused:
                print('warning: hand rows left alone: ' + ', '.join(refused), file=sys.stderr)
        else:
            out = args.output
            for (root, path), text in result['files'].items():
                destination = out / path.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(text, encoding='utf-8')
            for repo, repo_rows in rows.items():
                (out / 'api' / repo).mkdir(parents=True, exist_ok=True)
                (out / 'api' / repo / 'mapping-fragment.json').write_text(
                    json.dumps({'elements': repo_rows}, indent=1, sort_keys=True) + '\n', encoding='utf-8')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--helper', required=True, type=Path)
    parser.add_argument('--cache', required=True, type=Path, help='the api cache holding the pinned sources')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compare', action='store_true')
    mode.add_argument('--render', metavar='TYPE', help='print the skeleton for one Java type id')
    mode.add_argument('--yield', dest='yield_', action='store_true', help='deferred types the rules can skeleton')
    mode.add_argument('--emit', action='append', metavar='PACKAGE_OR_TYPE',
                      help='generate the modules for these Java packages (their deferred public classes and '
                      'interfaces) or type ids, together; repeatable')
    parser.add_argument('--output', type=Path, help='with --emit: write the modules and mapping fragments under '
                        'this new directory, at their repository paths')
    parser.add_argument('--in-place', action='store_true', help='with --emit: write into the tree and api/*/mapping.json')
    parser.add_argument('--strip-pending', action='store_true', help='with --emit: leave out every member whose body '
                        'is not written; its row stays deferred (what lands on main)')
    parser.add_argument('--predict', action='store_true', help='with --yield: name unmapped pinned types by R1, '
                        'as if their skeletons were generated in the same batch')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--only', action='append', help='compare one Java type id; repeatable (development)')
    args = parser.parse_args(argv)
    universe = accessors.Universe(args.cache.resolve())
    universe.predict = args.predict and args.yield_
    if args.emit:
        if bool(args.output) == args.in_place:
            parser.error('--emit needs exactly one of --output DIR and --in-place')
        if args.output and args.output.exists():
            parser.error(f'{args.output} exists; the output directory must be new')
        return emit_main(args, universe)
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
