#!/usr/bin/env python3
"""The porter's Java Beans shape: `@ConfigurationProperties` classes as boot's configuration-properties spec.

`flint-port-spring --describe` prints a Java type's declaration tree. This module derives, by fixed rules, the
`F`/`Cls`/`Enum` spec that `boot/tools/configuration_properties.py` renders into the D class, Boot's configuration
metadata and the YAML schema, so a lane reviews spec data rather than writing it. `--compare` derives every class
in boot's hand-written spec from the pinned spring-boot sources and reports, per field, whether the porter
reproduces the hand spec (porter-plan.md, M2; gate (b) for this shape).

    python3 tools/port-spring/beans.py --helper .flint/port-spring/flint-port-spring \\
        --cache "$PWD/.flint/cache/api" --compare [--json artifacts/porter/configprops.json]
    python3 tools/port-spring/beans.py --helper ... --cache ... --render JdbcProperties

A field the rules can't translate keeps a reason (`unsupported`) and is left out of the rendered class, so the
lane decides it by hand. Nothing here reads the hand spec when deriving.
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'boot', 'tools'))
import configuration_properties as cp  # noqa: E402  boot's spec types and renderer

UPSTREAM = 'spring-boot-v4.2.0'

# Java value types and their D spelling. Text-like JDK types are bound from their string form (R6 erasure, as in
# boot's hand spec: a Charset, Locale or Class<?> property holds the configured name).
SCALARS = {'boolean': 'bool', 'int': 'int', 'long': 'long', 'String': 'string', 'Duration': 'Duration'}
BOXED = {'Boolean': 'bool', 'Integer': 'int', 'Long': 'long'}
TEXT = {'Charset', 'Locale', 'TimeZone', 'InetAddress', 'Class'}
# Types with no Flint counterpart yet: the field is left to the lane.
UNSUPPORTED = {'DataSize', 'MediaType', 'Resource', 'File', 'ClassLoader', 'Character'}
LISTS = {'List', 'Set', 'Collection'}
MAPS = {'Map'}
EMPTY_COLLECTIONS = re.compile(r'new (ArrayList|LinkedHashSet|HashSet|TreeSet)<>\(\)$')
NEW_MAP = re.compile(r'new (LinkedHashMap|HashMap|TreeMap)<>\(\)$|new EnumMap<>\([A-Za-z_.]+\.class\)$')
NEW_OBJECT = re.compile(r'new ([A-Z][A-Za-z0-9_]*)\(\)$')
SETTER = re.compile(r'\{\s*this\.(\w+)\s*=\s*(\w+)\s*;\s*\}$')
GETTER = re.compile(r'\{\s*return\s+(?:this\.)?(\w+)\s*;\s*\}$')
NUMBER = re.compile(r'-?(0|[1-9][0-9_]*)[lL]?$')
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


class Unsupported(Exception):
    pass


def describe(helper, path):
    result = subprocess.run([helper, '--describe', path], capture_output=True, text=True, check=False)
    if result.returncode:
        raise Unsupported(result.stderr.strip() or f'{path}: describe failed')
    return json.loads(result.stdout)


# ---- Javadoc ----------------------------------------------------------------------------------------------------
INLINE = re.compile(r'\{@(code|literal|link|linkplain|value)\s+([^}]*)\}')


def doc_text(javadoc):
    """The Javadoc's main description as one line, with inline tags in Markdown code spans."""
    if not javadoc:
        return None
    body = javadoc[3:-2]
    lines = []
    for line in body.split('\n'):
        line = re.sub(r'^\s*\*( |$)?', '', line).strip()
        if line.startswith('@'):
            break
        lines.append(line)
    text = ' '.join(part for part in lines if part)

    def inline(match):
        tag, value = match.group(1), match.group(2).strip()
        if tag in ('link', 'linkplain'):
            target, _, label = value.partition(' ')
            value = label.strip() or target.replace('#', '.').lstrip('.')
        return f'`{value}`'
    text = INLINE.sub(inline, text)
    text = re.sub(r'</?(p|em|strong|code)>', '', text)
    return re.sub(r'\s+', ' ', text).strip() or None


# ---- types ------------------------------------------------------------------------------------------------------
def split_arguments(text):
    """Top-level comma-separated parts of a generic argument list or call."""
    parts, depth, start = [], 0, 0
    for index, char in enumerate(text):
        if char in '<([{':
            depth += 1
        elif char in '>)]}':
            depth -= 1
        elif char == ',' and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def strip_type_annotations(java):
    nullable = '@Nullable' in java
    return re.sub(r'@\w+\s*', '', java).strip(), nullable


def element(java, ctx):
    """The D type of a collection element or map value (never Optional)."""
    java = java.strip()
    if java in SCALARS:
        return SCALARS[java]
    if java in BOXED:
        return BOXED[java]
    return reference(java, ctx)


def reference(java, ctx):
    base = java.split('<', 1)[0]
    if base in TEXT:
        return 'string'
    last = base.rsplit('.', 1)[-1]
    if last in UNSUPPORTED or base in UNSUPPORTED:
        raise Unsupported(f'no Flint type for {java}')
    if '<' in java or not re.fullmatch(r'[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*', java):
        raise Unsupported(f'unsupported type {java}')
    return java


def d_type(java, nullable, ctx):
    """(D type, schema type or None) for a field's Java type."""
    if java.endswith('[]'):
        return element(java[:-2], ctx) + '[]', None
    if java in SCALARS:
        dtype = SCALARS[java]
        return ('Optional!Duration' if nullable and dtype == 'Duration' else dtype), None
    if java in BOXED:
        return f'Optional!{BOXED[java]}', None
    base, _, rest = java.partition('<')
    if base in LISTS:
        return element(rest[:-1], ctx) + '[]', None
    if base in MAPS:
        key, value = split_arguments(rest[:-1])
        dvalue = element(value, ctx)
        if key.strip() == 'String':
            return f'Map!(string, {dvalue})', None
        # A map keyed by an enum is held erased by constant names, so generated code shares one map type; an enum
        # value is erased the same way. The metadata and schema still describe the Java types (boot's Jackson maps).
        erased = dvalue if dvalue in SCALARS.values() else 'string'
        return f'Map!(string, {erased})', f'Map!({reference(key.strip(), ctx)}, {dvalue})'
    if base in TEXT:
        return 'string', None
    target = reference(java, ctx)
    if nullable:
        return (f'Optional!({target})' if '.' in target else f'Optional!{target}'), None
    return target, None


# ---- values -----------------------------------------------------------------------------------------------------
def string_literal(text):
    parts = [part.strip() for part in re.split(r'\+(?=(?:[^"]*"[^"]*")*[^"]*$)', text)]
    if not all(STRING.fullmatch(part) for part in parts):
        return None
    return json.dumps(''.join(json.loads(part) for part in parts))


def array_literal(values, ctx, element_type):
    items = [value_of(item, ctx, element_type) for item in split_arguments(values)]
    return '[' + ', '.join(items) + ']'


def value_of(text, ctx, dtype):
    """The D expression for a Java initializer, or Unsupported."""
    text = ' '.join(text.split())
    if text in ('true', 'false'):
        return text
    if NUMBER.fullmatch(text):
        return text.replace('_', '').rstrip('lL')
    if text == 'Integer.MAX_VALUE':
        return 'int.max'
    literal = string_literal(text)
    if literal is not None:
        return literal
    if text == 'StandardCharsets.UTF_8':
        return '"UTF-8"'
    match = re.fullmatch(r'(?:new String\[\] )?\{ ?(.*?),? ?\}', text)
    if match:
        return array_literal(match.group(1), ctx, 'string')
    match = re.fullmatch(r'new ArrayList<>\((?:List\.of|Arrays\.asList)\((.*)\)\)', text)
    if match:
        return array_literal(match.group(1), ctx, dtype[:-2])
    match = re.fullmatch(r'EnumSet\.allOf\((\w+)\.class\)', text)
    if match:
        return f'[EnumMembers!{match.group(1)}]'
    match = re.fullmatch(r'Duration\.of(Millis|Seconds|Minutes|Hours|Days)\((\d+)\)', text)
    if match:
        return f'dur!"{match.group(1).lower()}"({match.group(2)})'
    match = re.fullmatch(r'([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.([A-Z][A-Z0-9_]*)', text)
    if match and match.group(1).rsplit('.', 1)[-1] in ctx['enums'] | ctx['types']:
        return text
    if re.fullmatch(r'[A-Z][A-Z0-9_]*', text) and text in ctx['constants']:
        return value_of(ctx['constants'][text], ctx, dtype)
    raise Unsupported(f'unsupported initializer {text}')


# ---- the class tree ---------------------------------------------------------------------------------------------
def cap(name):
    return name[0].upper() + name[1:]


def body_of(methods, name, arity):
    for method in methods:
        if method['name'] == name and len(method['parameters']) == arity and 'static' not in method['modifiers']:
            return method
    return None


def scope(decl, outer=None):
    """Names visible to initializers: the enums, nested classes and string/int constants of the enclosing types."""
    ctx = {'enums': set(), 'types': set(), 'constants': {}} if outer is None else {
        'enums': set(outer['enums']), 'types': set(outer['types']), 'constants': dict(outer['constants'])}
    for nested in decl['types']:
        (ctx['enums'] if nested['kind'] == 'enum' else ctx['types']).add(nested['name'])
    for f in decl['fields']:
        if 'static' in f['modifiers'] and 'final' in f['modifiers']:
            for d in f['declarators']:
                if d['value']:
                    ctx['constants'][d['name']] = d['value']
    return ctx


class Derived:
    """The derived spec of one class, with what the rules could not translate."""

    def __init__(self, cls, unsupported, custom_setters, notes):
        self.cls, self.unsupported, self.custom_setters, self.notes = cls, unsupported, custom_setters, notes


def derive_enum(decl):
    if any(c['arguments'] or c['body'] for c in decl['constants']) or decl['fields'] or decl['methods']:
        raise Unsupported(f'enum {decl["name"]} has members beyond its constants (R15)')
    return cp.Enum(decl['name'], doc_text(decl['javadoc']) or '',
                   [(c['name'], doc_text(c['javadoc']) or '') for c in decl['constants']])


def derive_class(decl, outer_ctx=None, external_enums=()):
    ctx = scope(decl, outer_ctx)
    ctx['enums'] |= set(external_enums)
    fields, unsupported, custom, notes = [], {}, {}, []
    for f in decl['fields']:
        if 'static' in f['modifiers']:
            continue
        java, nullable = strip_type_annotations(f['type'])
        nullable = nullable or any(a['name'] == 'Nullable' for a in f['annotations'])
        udas = [a for a in f['annotations'] if a['name'] not in ('Nullable',)]
        for d in f['declarators']:
            name = d['name']
            getter = body_of(decl['methods'], ('is' if java == 'boolean' else 'get') + cap(name), 0) or \
                body_of(decl['methods'], 'get' + cap(name), 0)
            setter = body_of(decl['methods'], 'set' + cap(name), 1)
            try:
                if getter is None:
                    raise Unsupported('no getter: private state, not a property')
                match = GETTER.fullmatch(getter['body'] or '')
                if not match or match.group(1) != name:
                    raise Unsupported(f'getter {getter["name"]} does more than return the field')
                dtype, schema = d_type(java + (d['dimensions'] or ''), nullable, ctx)
                ro = 'final' in f['modifiers']
                value = d['value']
                default = None
                if value is None:
                    default = {'bool': 'false', 'int': '0', 'long': '0'}.get(dtype)
                elif ro and NEW_OBJECT.fullmatch(value) and NEW_OBJECT.fullmatch(value).group(1) == dtype:
                    default = f'new {dtype}'
                elif NEW_OBJECT.fullmatch(value) and NEW_OBJECT.fullmatch(value).group(1) == dtype:
                    default = f'new {dtype}'  # a replaceable nested object, assigned in the constructor
                elif NEW_MAP.fullmatch(' '.join(value.split())) and dtype.startswith('Map!'):
                    default = 'new LinkedHashMap' + dtype[3:]
                elif EMPTY_COLLECTIONS.fullmatch(value) or value == 'new String[0]':
                    default = None
                else:
                    default = value_of(value, ctx, dtype)
                # A run-time value (a fresh object, map or enum set) a mutable field can't take as an initializer.
                ctor = default is not None and (default.startswith('[EnumMembers!') or
                                                (not ro and default.startswith('new ')))
                uda = None
                for annotation in udas:
                    if annotation['name'] == 'DurationUnit':
                        uda = f'@DurationUnit{annotation["arguments"]}'
                    elif annotation['name'] == 'SuppressWarnings':
                        pass  # no effect on the D declaration
                    elif annotation['name'] in ('Deprecated', 'NestedConfigurationProperty'):
                        notes.append(f'{name}: @{annotation["name"]} not carried')
                    else:
                        raise Unsupported(f'annotation @{annotation["name"]}')
                if ro and setter is not None:
                    raise Unsupported('final field with a setter')
                if not ro and setter is None:
                    raise Unsupported('mutable field without a setter')
                if setter is not None:
                    match = SETTER.fullmatch(setter['body'] or '')
                    if not match or match.group(1) != name or match.group(2) != setter['parameters'][0]['name']:
                        custom[name] = setter['body']
                fields.append(cp.F(name, dtype, default, doc_text(f['javadoc']) or '', ro=ro, uda=uda,
                                   schema=schema, ctor=ctor))
            except Unsupported as error:
                unsupported[name] = str(error)
    nested, enums, children = [], [], {}
    for inner in decl['types']:
        try:
            if inner['kind'] == 'enum':
                enums.append(derive_enum(inner))
            elif inner['kind'] == 'class' and 'static' in inner['modifiers'] and 'public' in inner['modifiers']:
                child = derive_class(inner, ctx, external_enums)
                children[inner['name']] = child
                nested.append(child.cls)
        except Unsupported as error:
            unsupported[inner['name']] = str(error)
    # An undocumented nested-object field takes its class's description, so the DDoc and metadata keep one.
    docs = {n.name: n.doc for n in nested}
    for f in fields:
        if not f.doc and f.dtype in docs:
            f.doc = docs[f.dtype]
    prefix = None
    for annotation in decl['annotations']:
        if annotation['name'] == 'ConfigurationProperties':
            match = re.fullmatch(r'\((?:(?:value|prefix)\s*=\s*)?"([^"]*)"\)', annotation['arguments'] or '')
            if not match:
                raise Unsupported(f'unsupported @ConfigurationProperties{annotation["arguments"]}')
            prefix = re.sub(r'^spring\.', 'flint.', match.group(1))
    derived = Derived(cp.Cls(decl['name'], doc_text(decl['javadoc']) or '', fields, nested, enums, prefix),
                      unsupported, custom, notes)
    derived.children = children
    return derived


_INDEX = {}


def source_index(cache):
    """Every main source file of the pinned upstream: simple type name -> sorted paths, and package -> names."""
    root = os.path.join(cache, UPSTREAM)
    if root not in _INDEX:
        by_name, by_package = {}, {}
        marker = f'{os.sep}src{os.sep}main{os.sep}java{os.sep}'
        for directory, dirs, files in os.walk(root):
            dirs.sort()
            if marker not in directory + os.sep:
                continue
            package = (directory + os.sep).split(marker, 1)[1].strip(os.sep).replace(os.sep, '.')
            for file in sorted(files):
                if file.endswith('.java'):
                    by_name.setdefault(file[:-5], []).append(os.path.join(directory, file))
                    by_package.setdefault(package, set()).add(file[:-5])
        _INDEX[root] = by_name, by_package
    return _INDEX[root]


def java_source(cache, name):
    found = source_index(cache)[0].get(name, [])
    if len(found) != 1:
        raise Unsupported(f'{name}: {len(found)} candidate sources in {UPSTREAM}')
    return found[0]


def derive(helper, cache, name):
    tree = describe(helper, java_source(cache, name))
    return derive_class(tree['type'], external_enums=imported_enums(cache, tree))


def imported_enums(cache, tree):
    """Explicitly imported and same-package types that are enums, so their constants may initialize fields."""
    by_name, by_package = source_index(cache)
    imports = {}
    for i in tree['referenceImports']:
        if not i['static'] and not i['wildcard']:
            imports[i['path'].rsplit('.', 1)[-1]] = i['path']
    package = tree['package']
    candidates = {name: f'{package}.{name}' for name in by_package.get(package, ())}
    candidates.update(imports)
    enums = set()
    for name, qualified in sorted(candidates.items()):
        suffix = os.sep + qualified.replace('.', os.sep) + '.java'
        for path in by_name.get(name, []):
            if path.endswith(suffix):
                with open(path, encoding='utf-8') as source:
                    if re.search(rf'\bpublic enum {name}\b', source.read()):
                        enums.add(name)
    return enums


# ---- comparison with boot's hand spec ---------------------------------------------------------------------------
ATTRIBUTES = ('dtype', 'default', 'ro', 'uda', 'schema', 'ctor')


def compare_class(hand, derived, path, report):
    porter = {f.name: f for f in derived.cls.fields}
    entry = {'class': path, 'docMatch': hand.doc == derived.cls.doc, 'fields': {}, 'handOnly': [], 'javaOnly': [],
             'unsupported': {}, 'customSetters': sorted(derived.custom_setters)}
    for f in hand.fields:
        if f.name in derived.unsupported:
            entry['unsupported'][f.name] = derived.unsupported[f.name]
            continue
        if f.name not in porter:
            entry['handOnly'].append(f.name)
            continue
        p = porter[f.name]
        diffs = {a: {'hand': getattr(f, a), 'porter': getattr(p, a)} for a in ATTRIBUTES
                 if getattr(f, a) != getattr(p, a)}
        hand_custom = bool(f.setter or f.setter_body)
        if hand_custom != (f.name in derived.custom_setters):
            diffs['customSetter'] = {'hand': hand_custom, 'porter': f.name in derived.custom_setters}
        entry['fields'][f.name] = {'exact': not diffs, 'docMatch': f.doc == p.doc, 'diffs': diffs}
        if f.doc != p.doc:
            entry['fields'][f.name]['doc'] = {'hand': f.doc, 'porter': p.doc}
    hand_names = {f.name for f in hand.fields}
    entry['javaOnly'] = sorted(n for n in list(porter) + list(derived.unsupported)
                               if n not in hand_names and n not in derived.children)
    report.append(entry)
    for nested in hand.nested:
        child = derived.children.get(nested.name)
        if child is None:
            missing = derived.unsupported.get(nested.name, 'not in the Java class')
            report.append({'class': f'{path}.{nested.name}', 'missing': missing})
        else:
            compare_class(nested, child, f'{path}.{nested.name}', report)


def hand_classes():
    classes = []
    for unit in cp.UNITS:
        for item in unit.items:
            if isinstance(item, cp.Cls):
                classes.append(item)
    return classes


def compare(helper, cache, reverse=False):
    report = []
    for hand in (reversed if reverse else iter)(hand_classes()):
        try:
            compare_class(hand, derive(helper, cache, hand.name), hand.name, report)
        except Unsupported as error:
            report.append({'class': hand.name, 'missing': str(error)})
    report.sort(key=lambda entry: entry['class'])
    totals = {'classes': 0, 'fields': 0, 'exact': 0, 'docMatch': 0, 'unsupported': 0, 'handOnly': 0,
              'javaOnly': 0, 'missingClasses': 0, 'classDocMatch': 0}
    for entry in report:
        if 'missing' in entry:
            totals['missingClasses'] += 1
            continue
        totals['classes'] += 1
        totals['classDocMatch'] += entry['docMatch']
        totals['fields'] += len(entry['fields'])
        totals['exact'] += sum(f['exact'] for f in entry['fields'].values())
        totals['docMatch'] += sum(f['docMatch'] for f in entry['fields'].values())
        totals['unsupported'] += len(entry['unsupported'])
        totals['handOnly'] += len(entry['handOnly'])
        totals['javaOnly'] += len(entry['javaOnly'])
    return {'upstream': UPSTREAM, 'totals': totals, 'classes': report}


def summary(result):
    t = result['totals']
    hand_fields = t['fields'] + t['unsupported'] + t['handOnly']
    lines = [f'configuration properties ({result["upstream"]}): {t["classes"]} classes, {hand_fields} hand fields',
             f'  reproduced exactly (type, default, read-only, UDA, schema): {t["exact"]}/{hand_fields}',
             f'  field doc identical: {t["docMatch"]}/{hand_fields}; class doc identical: '
             f'{t["classDocMatch"]}/{t["classes"]}',
             f'  unsupported by a rule: {t["unsupported"]}; Flint additions (hand only): {t["handOnly"]}; '
             f'Java fields not in the hand spec: {t["javaOnly"]}; classes not derived: {t["missingClasses"]}']
    for entry in result['classes']:
        if 'missing' in entry:
            lines.append(f'  {entry["class"]}: not derived: {entry["missing"]}')
            continue
        for name, f in sorted(entry['fields'].items()):
            if not f['exact']:
                diffs = '; '.join(f'{a} hand {d["hand"]!r} porter {d["porter"]!r}' for a, d in f['diffs'].items())
                lines.append(f'  {entry["class"]}.{name}: {diffs}')
        for name, reason in sorted(entry['unsupported'].items()):
            lines.append(f'  {entry["class"]}.{name}: unsupported: {reason}')
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--helper', required=True)
    parser.add_argument('--cache', required=True, help='the api cache holding the pinned sources (absolute)')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compare', action='store_true', help="derive boot's hand-spec classes and compare")
    mode.add_argument('--render', metavar='CLASS', help='print the D class derived for a Java class')
    parser.add_argument('--json', help='write the comparison report here')
    args = parser.parse_args(argv)
    if args.render:
        try:
            derived = derive(args.helper, args.cache, args.render)
        except Unsupported as error:
            print(f'error: {error}', file=sys.stderr)
            return 2
        print(cp.render_class(derived.cls))
        for name, reason in sorted(derived.unsupported.items()):
            print(f'// port: {name} left to the lane: {reason}')
        return 0
    result = compare(args.helper, args.cache)
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        with open(args.json, 'w', encoding='utf-8') as out:
            json.dump(result, out, indent=2, sort_keys=True)
            out.write('\n')
    print(summary(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
