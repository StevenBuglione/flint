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


def violations(symbols, modules, leaves, data):
    """Attribute to the longest known module. A type name in a signature is only a reference."""
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
    path = f'framework/{package}/closure.json'
    if commit is None:
        source = (root / path).read_text() if (root / path).is_file() else None
    else:
        source = committed_text(root, commit, path)
    return json.loads(source)['probes'].get(leaf, {}).get(probe) if source else None


def may_seed_legacy_record(root, commit, row, existing_modules):
    # Decision 523bd5bd allows a new probe to inherit only the known flint.java.lang module metadata debt.
    record = LEGACY_RECORD.fullmatch(row)
    if not record:
        return False
    package, leaf, probe, module = record.groups()
    if module not in existing_modules:
        return False
    previous = commit + '^' if commit else 'HEAD'
    if probe_record(root, previous, package, leaf, probe) is not None:
        return False
    current = probe_record(root, commit, package, leaf, probe)
    return current is not None and 'flint.java.lang' in current.get('leaves', [])


def baseline_growth(root, current):
    """Reject new debt, except the approved legacy module records of a new probe."""
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
            if row in seen or not may_seed_legacy_record(root, commit, row, existing_modules):
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


def read_manifest(package, own_modules, all_modules=None):
    modules = own_modules if all_modules is None else all_modules
    path = package / 'closure.json'
    if not path.is_file():
        raise ValueError(f'{path}: missing JDK closure manifest')
    document = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if (not isinstance(document, dict) or set(document) != {'schema', 'probes'}
            or document['schema'] != SCHEMA or not isinstance(document['probes'], dict)):
        raise ValueError(f'{path}: expected {SCHEMA} and a probes object')
    entries = document['probes']
    expected = {name for name, public_leaf in own_modules.items() if public_leaf}
    missing, extra = sorted(expected - entries.keys()), sorted(entries.keys() - expected)
    if missing:
        raise ValueError(f'{path}: missing probes for {", ".join(missing)}')
    if extra or not expected:
        raise ValueError(f'{path}: expected probes for public API leaves only; extra: {", ".join(extra)}')
    seen = set()
    for module, probes in entries.items():
        if not isinstance(probes, dict) or not probes:
            raise ValueError(f'{path}: {module} needs at least one probe')
        for name, entry in probes.items():
            if (not re.fullmatch(r'[a-z][a-z0-9-]*', name) or not isinstance(entry, dict)
                    or set(entry) != {'source', 'leaves', 'data'} or not isinstance(entry['source'], str)):
                raise ValueError(f'{path}: invalid probe record {module}/{name}')
            check_names(entry['leaves'], modules, want_data=False)
            check_names(entry['data'], modules, want_data=True)
            source = (package / entry['source']).resolve()
            relative = source.relative_to(package.resolve()) if source.is_relative_to(package.resolve()) else None
            if not relative or relative.parts[0] not in ('closure', 'bench') or source.suffix != '.d' or not source.is_file():
                raise ValueError(f'{path}: missing or invalid probe source {entry["source"]}')
            if source in seen:
                raise ValueError(f'{path}: duplicate probe source {entry["source"]}')
            seen.add(source)
            text = source.read_text()
            imports = source_imports(text)
            jdk_imports = {name for name in imports if is_jdk_module(name)}
            if jdk_imports != {module} or banned_imports(text):
                raise ValueError(f'{source}: probe must import only the JDK leaf {module} and no banned Phobos')
    return entries


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
    with tempfile.TemporaryDirectory(prefix='flint-jdk-closure-') as temporary:
        workspace = Path(temporary) / 'workspace'
        copy_workspace(workspace)
        control = Path(temporary) / 'control.d'
        control.write_text('module app;\n@safe:\nint main(string[] args) { return cast(int) args.length & 127; }\n')
        profiles = native_profiles()
        for profile in ('O3', 'Oz'):
            control_bytes, control_symbols, _ = build_probe(
                workspace, workspace / f'.jdk-control-{profile}', None, control, profiles[profile], evidence)
            control_problems = violations(control_symbols, all_modules, set(), set())
            if control_problems:
                raise BuildError(f'{profile} control retained {", ".join(control_problems)}')
            for leaf, probes in entries.items():
                for name, entry in probes.items():
                    directory = workspace / f'.jdk-{leaf}-{name}-{profile}'
                    loadable, symbols, map_text = build_probe(workspace, directory, package,
                                                              packages[package] / entry['source'],
                                                              profiles[profile], evidence)
                    problems = violations(symbols, all_modules, {leaf, *entry['leaves']}, set(entry['data']))
                    families = {issue.removeprefix('banned Phobos ') for issue in problems
                                if issue.startswith('banned Phobos ')}
                    report.setdefault(leaf, {}).setdefault(name, {})[profile] = {
                        'loadable_bytes': loadable, 'control_bytes': control_bytes,
                        'signed_delta_bytes': loadable - control_bytes, 'violations': problems,
                        'phobos_archive_triggers': phobos_triggers(map_text, families),
                    }
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
