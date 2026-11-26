#!/usr/bin/env python3
"""Audit JDK public API probes under the canonical O3 and Oz ThinLTO profiles."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from d_source import declared_module, imported_modules, tokens
from measure_builds import copy_workspace, dub_invocation, elf_loadable_bytes, native_profiles
from request_allocation_ratchet import git

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 'flint.jdk-closure/1'
PROBE_DIRECTORY = 'closure-probes'
BANNED_PHOBOS = tuple('std.' + family for family in (
    'format', 'conv', 'uni', 'regex', 'socket', 'net', 'process', 'file', 'path',
    'datetime', 'json', 'parallelism', 'concurrency',
))
JDK_ROOTS = ('flint.java', 'flint.javax')
DATA_COMPONENT = 'data'
PRIVATE_COMPONENTS = {'ffi', 'internal', 'sys'}
BASELINE = 'framework/java/closure-baseline.json'
BASELINE_SCHEMA = 'flint.jdk-closure-baseline/1'
LEGACY_RECORD = re.compile(r'link\|(java(?:-[a-z0-9-]+)?)\|(flint\.java\w*(?:\.\w+)+)\|'
                           r'([a-z][a-z0-9-]*)\|(?:O3|Oz)\|undeclared module records (flint\.java(?:\.\w+)+)')
# Temporary first-object exception approved in 64f0653bc. Remove when the compile-scope fix lands.
FIRST_OBJECT_ALLOWANCES = {
    ('java-nio', 'flint.java.nio.bufferunderflowexception', 'underflow'): {
        'profiles': ('O3', 'Oz'),
        'module': 'flint.java.nio.bufferoverflowexception',
        'member': 'flint.java.nio.bufferoverflowexception.o',
        'referrer': 'flint.java.nio.bufferunderflowexception.o',
        'trigger': '_D6object__T10RTInfoImplVAmA2i97i2728ZQBayG2m',
        'sections': {
            '.rodata._D6object__T10RTInfoImplVAmA2i97i2728ZQBayG2m': 16,
            '.data._D5flint4java3nio23bufferoverflowexception12__ModuleInfoZ': 48,
            '__minfo': 8,
        },
        'existing_probe': True,
    },
    ('java-util', 'flint.java.util.stringjoiner', 'full'): {
        'profiles': ('O3', 'Oz'),
        'module': 'flint.java.util.hexformat',
        'member': 'flint.java.util.hexformat.o',
        'referrer': 'flint.java.util.stringjoiner.o',
        'trigger': '_D6object__T10RTInfoImplVAmA2i132i2728ZQBbyG2m',
        'sections': {
            '.rodata._D6object__T10RTInfoImplVAmA2i132i2728ZQBbyG2m': 16,
            '.data._D5flint4java4util9hexformat12__ModuleInfoZ': 36,
            '__minfo': 8,
            '.text._D4core10checkedint__T4muluZQgFNaNbNiNfmmKbZm': 15,
            '.text._D4core8internal5array5utils__T12__arrayAllocTaZQrFNaNbNemZAv': 36,
            '.eh_frame': 48,
        },
    },
}
# Keep the reviewed row and its seeding mode as history when the live allowance is retired.
FIRST_OBJECT_ROWS = {
    '|'.join(('link', *probe, profile, f"undeclared module records {allowance['module']}")):
        allowance.get('existing_probe', False)
    for probe, allowance in FIRST_OBJECT_ALLOWANCES.items() for profile in allowance['profiles']
}
# The original Character generator keeps these tables beside the public functions.
# New tables belong in data modules so the checker can identify them by module owner.
CHARACTER_TABLES = {f'flint.java.character.{name}' for name in (
    'lowerRuns', 'upperRuns', 'upperCaseRanges', 'letterRanges',
    'uppercaseLetterRanges', 'lowercaseLetterRanges', 'numberRanges',
)}
SYMBOL = re.compile(r'(?<![\w])_D[0-9][\w$]*(?:\.[\w$]+)*')
IDENTIFIER = re.compile(r'[0-9]+|Q([A-Z]*[a-z])')


class BuildError(RuntimeError):
    """A probe did not produce the evidence the audit needs."""


def is_jdk_package(name):
    return name == 'java' or name.startswith('java-')


def under(name, prefix):
    return name == prefix or name.startswith(prefix + '.')


def is_jdk_module(name):
    return any(under(name, root) for root in JDK_ROOTS)


def is_data(name):
    return name in CHARACTER_TABLES or DATA_COMPONENT in name.split('.')[2:]


def source_imports(source):
    stream = list(tokens(source))
    names = set(imported_modules(stream))
    # D's imported!"module.name" idiom uses a string literal in place of an import declaration.
    values = [token.value for token in stream]
    for index in range(len(stream) - 2):
        if values[index:index + 2] != ['imported', '!']:
            continue
        literal = index + 2 + (values[index + 2] == '(')
        if literal < len(stream) and values[literal] == '<literal>':
            match = re.match(r'r?(["`])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\1', source[stream[literal].offset:])
            if match:
                names.add(match[2])
    return names


def banned_imports(source):
    return sorted(name for name in source_imports(source)
                  if name in ('std', 'std.all') or any(under(name, family) for family in BANNED_PHOBOS))


def map_symbols(text):
    """Use the live part of an ELF linker map. GNU ld lists discarded sections above it."""
    marker = 'Linker script and memory map\n'
    if marker in text:
        contents = text.split(marker, 1)[1]
    elif re.match(r'^\s*VMA\s+LMA\s+Size\s+Align\s+Out\s+In\s+Symbol\s*$', text.split('\n', 1)[0]):
        contents = text.split('\n', 1)[-1]
    else:
        raise ValueError('unrecognized ELF linker map')
    if not contents.strip():
        raise ValueError('empty ELF linker map')
    return set(SYMBOL.findall(contents))


def phobos_triggers(text, families):
    """Trace GNU ld's archive selection back to the first referring object and symbol."""
    heading = 'Archive member included to satisfy reference by file (symbol)\n'
    if not families or not text.startswith(heading):
        return {}
    section = text[len(heading):].lstrip('\n').split('\n\n', 1)[0]
    records = re.findall(r'^([^\s].*\([^()]+\))\n[ \t]+(.+) \(([^()\s]+)\)$', section, re.MULTILINE)
    prefixes = {mangle_prefix(family): family for family in families}
    causes, triggers = {}, {}
    for member, referring, symbol in records:
        referring = referring.removesuffix(' (symbol from plugin)')
        origin = causes.get(referring, (Path(referring).name, symbol))
        origin = causes.setdefault(member, origin)
        # LLVMgold sometimes names the referring archive member without the archive's path.
        causes.setdefault(member.rsplit('(', 1)[1][:-1], origin)
        for prefix, family in prefixes.items():
            if symbol.startswith(prefix):
                triggers.setdefault(family, {'object': origin[0], 'symbol': origin[1],
                                             'archive_member': Path(member).name})
    return triggers


def defined_symbols(text):
    """GNU ld's map can omit local symbols after ThinLTO internalizes them."""
    rows = re.findall(r'^\s*[\da-fA-F]+\s+\w\s+(\S+)$', text, re.MULTILINE)
    if not rows:
        raise ValueError('missing defined symbols in probe executable')
    return {name for name in rows if SYMBOL.fullmatch(name)}


def first_object_placement(text, allowance):
    """Verify the admission and exact live contributions of the allowed archive member."""
    header, _, live = text.partition('Linker script and memory map\n')
    member = re.escape(allowance['member'])
    referrer = re.escape(allowance['referrer'])
    trigger = re.escape(allowance['trigger'])
    admission = rf'^\S+\({member}\)\n[ \t]+{referrer} \(symbol from plugin\) \({trigger}\)$'
    if not re.search(admission, header, re.MULTILINE):
        return None
    contributions = re.findall(r'^[ \t]+(\S+)(?:[ \t]+|\n[ \t]+)0x[0-9a-f]+[ \t]+0x([0-9a-f]+)'
                               r'[ \t]+(\S+\.o)$', live, re.MULTILINE)
    trigger_section = f".rodata.{allowance['trigger']}"
    providers = [obj for section, _, obj in contributions if section == trigger_section]
    if len(providers) != 1:
        return None
    provider = providers[0]
    rows = [(section, int(size, 16)) for section, size, obj in contributions if obj == provider]
    provider_lines = [parts for line in live.splitlines()
                      if (parts := line.split()) and parts[-1] == provider and parts[0] != 'LOAD']
    if len(rows) != len(provider_lines):
        return None
    rows = [(section, size) for section, size in rows if size and section != '.comment']
    if sorted(rows) != sorted(allowance['sections'].items()):
        return None
    return dict(rows)


def mangle_prefix(name):
    return '_D' + ''.join(f'{len(part)}{part}' for part in name.split('.'))


def symbol_owner(symbol, modules):
    """Find the longest module in the leading D ABI name, without parsing the signature."""
    parts, emitted = [], {}
    cursor, owner = 2, None  # Skip the _D linkage prefix.
    while token := IDENTIFIER.match(symbol, cursor):
        end = token.end()
        if backreference := token[1]:
            distance = 0
            for digit in backreference:
                distance = 26 * distance + ord(digit.lower()) - ord('a')
            identifier = emitted.get(cursor - distance)
            if identifier is None:
                break  # Type backreferences do not name a module component.
        else:
            start = end
            end += int(token[0])
            if start == end or end > len(symbol):
                break
            identifier = symbol[start:end]
            emitted[cursor] = identifier
        cursor = end
        parts.append(identifier)
        name = '.'.join(parts)
        if name in modules:
            owner = name, cursor
    return owner


def is_module_record(symbol, end):
    return symbol[end:].partition('.')[0] in ('11__moduleRefZ', '12__ModuleInfoZ')


def violations(symbols, modules, leaves, data, *, probe_module=None):
    """Attribute to the longest known module. A type name in a signature is only a reference."""
    if probe_module in modules:
        raise ValueError(f'{probe_module}: probe module is a registered JDK module')
    owners = set(modules) | {probe_module} if probe_module else modules
    families = {mangle_prefix(name): name for name in BANNED_PHOBOS}
    roots = tuple(mangle_prefix(name) for name in JDK_ROOTS)
    problems = {}
    for symbol in sorted(symbols):
        if symbol.startswith('_D3std'):
            family = next((name for prefix, name in families.items() if symbol.startswith(prefix)), None)
            if family:
                problems.setdefault(f'banned Phobos {family}', symbol)
        if not symbol.startswith(roots):
            continue
        owner = symbol_owner(symbol, owners)
        if owner is not None and owner[0] == probe_module:
            if is_module_record(symbol, owner[1]):
                continue
            owner = symbol_owner(symbol, modules)
        if owner is None:
            problems.setdefault('unrecognized JDK symbol owner', symbol)
            continue
        module, end = owner
        if is_data(module):
            if module not in data:
                problems.setdefault(f'undeclared data {module}', symbol)
        elif module not in leaves:
            kind = 'module records' if is_module_record(symbol, end) else 'leaf'
            problems.setdefault(f'undeclared {kind} {module}', symbol)
    return dict(sorted(problems.items()))


def loadable_section_bytes(text):
    """Use the package budget's ELF metric and reject missing evidence."""
    total = elf_loadable_bytes(text)
    if not total:
        raise ValueError('missing loadable ELF sections in probe executable')
    return total


def is_namespace(stream):
    """Package modules can consist of public re-exports only."""
    values = [token.value for token in stream]
    index = values.index(';') + 1
    while index < len(values):
        if values[index:index + 3] == ['@', 'safe', ':']:
            index += 3
        elif values[index:index + 2] == ['public', 'import']:
            index = values.index(';', index) + 1
        else:
            return False
    return True


def source_modules(package):
    modules = {}
    for path in sorted((package / 'source').rglob('*.d')):
        stream = list(tokens(path.read_text()))
        name = declared_module(stream)
        if not is_jdk_module(name) or name in modules:
            raise ValueError(f'{path}: invalid or duplicate JDK module {name}')
        private = is_data(name) or PRIVATE_COMPONENTS.intersection(name.split('.')[2:])
        aggregate = path.name == 'package.d' and is_namespace(stream)
        modules[name] = not (private or aggregate)
    if not modules:
        raise ValueError(f'{package}: no JDK source modules')
    return modules


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate manifest key {key}')
        result[key] = value
    return result


def baseline_entries(text):
    document = json.loads(text, object_pairs_hook=unique_object)
    if (not isinstance(document, dict) or set(document) != {'schema', 'source_commit', 'violations'}
            or document['schema'] != BASELINE_SCHEMA or not isinstance(document['source_commit'], str)
            or not re.fullmatch(r'[0-9a-f]{40}', document['source_commit'])):
        raise ValueError(f'invalid {BASELINE_SCHEMA} document')
    rows = document['violations']
    if not isinstance(rows, list) or any(not isinstance(row, str) or not row for row in rows) or rows != sorted(set(rows)):
        raise ValueError('JDK baseline violations must be unique sorted strings')
    return set(rows)


def baseline_at(root):
    path = root / BASELINE
    return baseline_entries(path.read_text()) if path.is_file() else set()


def committed_text(root, commit, path):
    result = git(root, 'show', f'{commit}:{path}', check=False)
    return result.stdout if result.returncode == 0 else None


def probe_record(root, commit, package, leaf, probe):
    def read(path):
        if commit is not None:
            return committed_text(root, commit, path)
        file = root / path
        return file.read_text() if file.is_file() else None

    prefix = f'framework/{package}'
    legacy = read(f'{prefix}/closure.json')
    record = json.loads(legacy, object_pairs_hook=unique_object)['probes'].get(leaf, {}).get(probe) if legacy else None
    fragment = read(f'{prefix}/{PROBE_DIRECTORY}/{leaf}/{probe}.json')
    if fragment is None:
        return record
    if record is not None:
        raise ValueError(f'{prefix}: duplicate probe record {leaf}/{probe}')
    return json.loads(fragment, object_pairs_hook=unique_object)


def may_seed_module_record(root, commit, row, existing_modules):
    # Decision 523bd5bd allows a new probe to inherit the known flint.java.lang module metadata debt.
    record = LEGACY_RECORD.fullmatch(row)
    if not record:
        return False
    package, leaf, probe, module = record.groups()
    placement = row in FIRST_OBJECT_ROWS
    if module not in existing_modules and not placement:
        return False
    previous = commit + '^' if commit else 'HEAD'
    prior_probe = probe_record(root, previous, package, leaf, probe)
    current = probe_record(root, commit, package, leaf, probe)
    if current is None:
        return False
    leaves = current.get('leaves', [])
    if placement and FIRST_OBJECT_ROWS[row]:
        return prior_probe == current and module not in leaves
    if prior_probe is not None:
        return False
    return module not in leaves if placement else 'flint.java.lang' in leaves


def baseline_growth(root, current):
    """Reject new debt, except approved module records for exact probes."""
    if not (root / '.git').exists():
        return []
    if git(root, 'rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        return ['JDK closure ratchet requires full git history']
    commits = git(root, 'log', '--first-parent', '--reverse', '--format=%H', 'HEAD', '--', BASELINE).stdout.split()
    versions = []
    for commit in commits:
        document = committed_text(root, commit, BASELINE)
        versions.append((commit, baseline_entries(document) if document is not None else set()))
    if not versions:
        return []
    versions.append((None, current))
    seed = versions[0][1]
    existing_modules = {match[4] for row in seed if (match := LEGACY_RECORD.fullmatch(row)) and match[1] == 'java'}
    seen, problems = set(seed), []
    for (_, previous), (commit, entries) in zip(versions, versions[1:]):
        label = commit[:12] if commit else 'working tree'
        for row in sorted(entries - previous):
            if row in seen or not may_seed_module_record(root, commit, row, existing_modules):
                problems.append(f'{BASELINE}: violation added in {label}: {row}')
        seen.update(entries)
    return problems


def import_violations(package, module, source):
    return {f'import|{package}|{module}|{name}' for name in banned_imports(source)}


def package_import_violations(package, directory):
    found = set()
    for path in sorted((directory / 'source').rglob('*.d')):
        source = path.read_text()
        found.update(import_violations(package, declared_module(tokens(source)), source))
    return found


def link_violations(package, report):
    return {f'link|{package}|{leaf}|{probe}|{profile}|{issue}' for leaf, probes in report.items()
            for probe, profiles in probes.items() for profile, result in profiles.items() for issue in result['violations']}


def check_violations(observed, baseline, release=False):
    allowed = set() if release else baseline
    label = 'release violation' if release else 'new violation'
    return ([f'{label}: {entry}' for entry in sorted(observed - allowed)]
            + [f'baseline violation is gone: {entry}' for entry in sorted(baseline - observed)])


def check_names(names, modules, want_data):
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValueError('expected an array of module names')
    if len(names) != len(set(names)):
        raise ValueError('duplicate module names')
    for name in names:
        if name not in modules or is_data(name) != want_data:
            raise ValueError(f'unknown or wrongly classified module {name}')


def manifest_entries(package):
    manifest = package / 'closure.json'
    directory = package / PROBE_DIRECTORY
    fragments = sorted(directory.rglob('*.json'))
    entries = {}
    if manifest.is_file():
        document = json.loads(manifest.read_text(), object_pairs_hook=unique_object)
        if (not isinstance(document, dict) or set(document) != {'schema', 'probes'}
                or document['schema'] != SCHEMA or not isinstance(document['probes'], dict)):
            raise ValueError(f'{manifest}: expected {SCHEMA} and a probes object')
        entries = document['probes']
    elif not fragments:
        raise ValueError(f'{package}: missing JDK closure manifest')
    for fragment in fragments:
        relative = fragment.relative_to(directory)
        if len(relative.parts) != 2:
            raise ValueError(f'{fragment}: expected {PROBE_DIRECTORY}/<leaf>/<probe>.json')
        leaf, probe = relative.parts[0], fragment.stem
        probes = entries.setdefault(leaf, {})
        if not isinstance(probes, dict):
            raise ValueError(f'{manifest}: {leaf} needs at least one probe')
        if probe in probes:
            raise ValueError(f'{fragment}: duplicate probe record {leaf}/{probe}')
        probes[probe] = json.loads(fragment.read_text(), object_pairs_hook=unique_object)
    return entries


def read_manifest(package, own_modules, all_modules=None):
    modules = own_modules if all_modules is None else all_modules
    entries = manifest_entries(package)
    expected = {name for name, public_leaf in own_modules.items() if public_leaf}
    missing, extra = sorted(expected - entries.keys()), sorted(entries.keys() - expected)
    if missing:
        raise ValueError(f'{package}: missing probes for {", ".join(missing)}')
    if extra or not expected:
        raise ValueError(f'{package}: expected probes for public API leaves only; extra: {", ".join(extra)}')
    seen = set()
    for module, probes in entries.items():
        if not isinstance(probes, dict) or not probes:
            raise ValueError(f'{package}: {module} needs at least one probe')
        for name, entry in probes.items():
            if not re.fullmatch(r'[a-z][a-z0-9-]*', name) or not isinstance(entry, dict):
                raise ValueError(f'{package}: invalid probe record {module}/{name}')
            if set(entry) == {'covered_by'}:
                check_covering_probe(package, entries, module, name, entry['covered_by'])
                continue
            if set(entry) != {'source', 'leaves', 'data'} or not isinstance(entry['source'], str):
                raise ValueError(f'{package}: invalid probe record {module}/{name}')
            check_names(entry['leaves'], modules, want_data=False)
            check_names(entry['data'], modules, want_data=True)
            source = (package / entry['source']).resolve()
            relative = source.relative_to(package.resolve()) if source.is_relative_to(package.resolve()) else None
            if not relative or relative.parts[0] not in ('closure', 'bench') or source.suffix != '.d' or not source.is_file():
                raise ValueError(f'{package}: missing or invalid probe source {entry["source"]}')
            if source in seen:
                raise ValueError(f'{package}: duplicate probe source {entry["source"]}')
            seen.add(source)
            text = source.read_text()
            imports = source_imports(text)
            jdk_imports = {name for name in imports if is_jdk_module(name)}
            if jdk_imports != {module} or banned_imports(text):
                raise ValueError(f'{source}: probe must import only the JDK leaf {module} and no banned Phobos')
    return entries


def check_covering_probe(package, entries, leaf, name, covering):
    label = f'{package}: {leaf}/{name}'
    if (not isinstance(covering, dict) or set(covering) != {'leaf', 'probe', 'abstract_type', 'concrete_type'}
            or any(not isinstance(value, str) for value in covering.values())
            or any(not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', covering[key])
                   for key in ('abstract_type', 'concrete_type'))):
        raise ValueError(f'{label}: invalid covered_by record')
    probes = entries.get(covering['leaf'])
    target = probes.get(covering['probe']) if isinstance(probes, dict) else None
    if covering['leaf'] == leaf or not isinstance(target, dict) or 'source' not in target:
        raise ValueError(f'{label}: covered_by must name an existing concrete leaf probe')
    if not isinstance(target.get('leaves'), list) or leaf not in target['leaves']:
        raise ValueError(f'{label}: covering probe must declare {leaf} in its leaves')


def coverage_witness(leaf, covering):
    base, subclass = covering['abstract_type'], covering['concrete_type']
    # Keep these semantic checks out of the measured fixture. A witness import
    # must never introduce symbols into the concrete probe's closure.
    return f'''module app;
import std.traits : Unqual;
static import {leaf};
static import {covering['leaf']};
alias Base = {leaf}.{base};
alias Subclass = {covering['leaf']}.{subclass};

static assert(__traits(isAbstractClass, Base) && __traits(isSame, __traits(parent, Base), {leaf}),
              "covered_by needs an abstract class declared in its leaf");
static assert(is(Subclass : Base) && !is(Subclass == Base) && !__traits(isAbstractClass, Subclass)
              && __traits(isSame, __traits(parent, Subclass), {covering['leaf']}),
              "covered_by needs a concrete subclass declared in the covering leaf");

template IsFactory(alias candidate)
{{
    static if (is(typeof(candidate) Result == return))
        enum IsFactory = is(Unqual!Result : Base);
    else
        enum IsFactory = true; // An unconstrained return type cannot prove absence of a factory.
}}

static foreach (member; __traits(derivedMembers, Base))
    static foreach (method; __traits(getOverloads, Base, member, true))
        static if (__traits(getProtection, method) == "public" || __traits(getProtection, method) == "export")
        {{
            static assert(member != "__ctor", "covered_by abstract leaf has a public constructor");
            static if (__traits(isTemplate, method))
            {{
                static if (__traits(compiles, method!()))
                    static assert(!__traits(isStaticFunction, method!()),
                                  "covered_by abstract leaf has a possible public factory");
                else
                    static assert(false, "covered_by cannot rule out a public factory template");
            }}
            else static if (__traits(isStaticFunction, method))
                static assert(!IsFactory!method, "covered_by abstract leaf has a public factory");
        }}

static foreach (member; __traits(allMembers, {leaf}))
    static foreach (factory; __traits(getOverloads, {leaf}, member, true))
        static if (__traits(getProtection, factory) == "public" || __traits(getProtection, factory) == "export")
            static assert(!IsFactory!factory, "covered_by abstract leaf has a public factory");

@safe int main() {{ return 0; }}
'''


def covered_symbols(symbols, leaf, covering):
    base_type = f"{leaf}.{covering['abstract_type']}"
    concrete_type = f"{covering['leaf']}.{covering['concrete_type']}"
    seen = {}
    for symbol in sorted(symbols):
        owner = symbol_owner(symbol, {base_type, concrete_type})
        if owner:
            seen.setdefault(owner[0], symbol)
    for qualified_type in (base_type, concrete_type):
        if qualified_type not in seen:
            raise BuildError(f'covered_by has no retained {qualified_type.rsplit(".", 1)[1]} symbols')
    return seen[base_type]


def run(command, cwd, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        output = (result.stdout + '\n' + result.stderr).strip().splitlines()
        raise BuildError(f'{command[0]} exited {result.returncode} in {cwd}:\n' + '\n'.join(output[-18:]))
    return result.stdout


def build_probe(workspace, directory, package, source, flags, evidence):
    directory.mkdir()
    shutil.copyfile(source, directory / 'app.d')
    link_map = directory / 'link.map'
    dependency = f'dependency "flint:{package}" path=".."\n' if package else ''
    (directory / 'dub.sdl').write_text('name "jdk-closure-probe"\ntargetName "probe"\n'
        'targetType "executable"\nsourcePaths "."\nimportPaths "."\ntargetPath "build"\n'
        f'lflags "-Map={link_map}"\n{dependency}')
    command, cwd, env = dub_invocation('dub', workspace, directory.name, 'ldc2', flags, os.environ)
    build_log = run(command + ['-v'], cwd, env)
    binary = directory / 'build' / 'probe'
    if not link_map.is_file() or not binary.is_file():
        raise BuildError(f'{directory.name}: missing linker map or executable')
    sections = run(['readelf', '-SW', str(binary)], cwd)
    symbols = run(['nm', '--defined-only', '-a', str(binary)], cwd)
    if evidence:
        destination = evidence / directory.name
        destination.mkdir()
        for filename, text in (('build.log', build_log), ('sections.txt', sections), ('symbols.txt', symbols)):
            (destination / filename).write_text(text)
        shutil.copyfile(link_map, destination / link_map.name)
    map_text = link_map.read_text()
    return loadable_section_bytes(sections), map_symbols(map_text) | defined_symbols(symbols), map_text


def audit(package, evidence):
    if not sys.platform.startswith('linux'):
        raise BuildError('JDK link-closure probes require the Linux ELF toolchain')
    policy = json.loads((ROOT / 'policy/framework.json').read_text())['modules']
    packages = {name: ROOT / entry['directory'] for name, entry in policy.items()
                if is_jdk_package(name) and (ROOT / entry['directory']).is_dir()}
    if package not in packages:
        raise ValueError(f'unknown JDK package flint:{package}')
    inventory = {name: source_modules(directory) for name, directory in packages.items()}
    all_modules = set()
    for modules in inventory.values():
        if all_modules.intersection(modules):
            raise ValueError('a JDK module is defined by more than one package')
        all_modules.update(modules)
    if 'flint.java.character' in all_modules:
        all_modules.update(CHARACTER_TABLES)
    entries = read_manifest(packages[package], inventory[package], all_modules)
    if evidence:
        evidence.mkdir(parents=True, exist_ok=True)
    report = {}
    coverage = {}
    for leaf, probes in entries.items():
        for name, entry in probes.items():
            if covering := entry.get('covered_by'):
                coverage.setdefault((covering['leaf'], covering['probe']), []).append((leaf, name, covering))
    with tempfile.TemporaryDirectory(prefix='flint-jdk-closure-') as temporary:
        workspace = Path(temporary) / 'workspace'
        copy_workspace(workspace)
        control = Path(temporary) / 'control.d'
        control.write_text('module app;\n@safe:\nint main(string[] args) { return cast(int) args.length & 127; }\n')
        profiles = native_profiles()
        for covered in coverage.values():
            for leaf, name, covering in covered:
                witness = Path(temporary) / 'coverage.d'
                witness.write_text(coverage_witness(leaf, covering))
                build_probe(workspace, workspace / f'.jdk-{leaf}-{name}-coverage', package, witness,
                            profiles['O3'], evidence)
        for profile in ('O3', 'Oz'):
            control_bytes, control_symbols, _ = build_probe(
                workspace, workspace / f'.jdk-control-{profile}', None, control, profiles[profile], evidence)
            control_problems = violations(control_symbols, all_modules, set(), set())
            if control_problems:
                raise BuildError(f'{profile} control retained {", ".join(control_problems)}')
            for leaf, probes in entries.items():
                for name, entry in probes.items():
                    if 'covered_by' in entry:
                        continue
                    directory = workspace / f'.jdk-{leaf}-{name}-{profile}'
                    source = packages[package] / entry['source']
                    fixture_module = declared_module(tokens(source.read_text()))
                    loadable, symbols, map_text = build_probe(workspace, directory, package, source,
                                                              profiles[profile], evidence)
                    problems = violations(symbols, all_modules, {leaf, *entry['leaves']}, set(entry['data']),
                                          probe_module=fixture_module)
                    families = {issue.removeprefix('banned Phobos ') for issue in problems
                                if issue.startswith('banned Phobos ')}
                    result = {
                        'loadable_bytes': loadable, 'control_bytes': control_bytes,
                        'signed_delta_bytes': loadable - control_bytes, 'violations': problems,
                        'phobos_archive_triggers': phobos_triggers(map_text, families),
                    }
                    allowance = FIRST_OBJECT_ALLOWANCES.get((package, leaf, name))
                    if allowance and profile in allowance['profiles']:
                        module = allowance['module']
                        record = f'undeclared module records {module}'
                        if record in problems:
                            if placement := first_object_placement(map_text, allowance):
                                result['first_object_contributions'] = placement
                            else:
                                problems[f'unexpected first-object contributions from {module}'] = problems[record]
                    if covered := coverage.get((leaf, name)):
                        result['covers'] = {
                            f'{base}/{case}': covered_symbols(symbols, base, covering)
                            for base, case, covering in covered
                        }
                    report.setdefault(leaf, {}).setdefault(name, {})[profile] = result
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, help='DUB subpackage name, e.g. java')
    parser.add_argument('--evidence', type=Path, help='keep linker maps and build logs in this directory')
    parser.add_argument('--release', action='store_true', help='fail on all retained violations')
    args = parser.parse_args()
    try:
        report = audit(args.package, args.evidence)
        baseline = baseline_at(ROOT)
        current = {row for row in baseline if row.startswith(f'link|{args.package}|')}
        problems = baseline_growth(ROOT, baseline)
        problems += check_violations(link_violations(args.package, report), current, args.release)
        for leaf, probes in report.items():
            for probe, profiles in probes.items():
                for profile, result in profiles.items():
                    for family, trigger in result['phobos_archive_triggers'].items():
                        row = f'link|{args.package}|{leaf}|{probe}|{profile}|banned Phobos {family}'
                        if args.release or row not in current:
                            problems.append(f'{leaf}/{probe} ({profile}) {family}: '
                                            f'{trigger["object"]} requested {trigger["symbol"]}, '
                                            f'reaching {trigger["archive_member"]}')
        if args.release:
            policy = json.loads((ROOT / 'policy/framework.json').read_text())['modules']
            directory = ROOT / policy[args.package]['directory']
            problems.extend(f'banned import: {entry}' for entry in sorted(package_import_violations(args.package, directory)))
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    except (BuildError, OSError) as error:
        print(error, file=sys.stderr)
        return 2
    print(json.dumps({'probes': report, 'problems': problems}, indent=2))
    return int(bool(problems))


if __name__ == '__main__':
    sys.exit(main())
