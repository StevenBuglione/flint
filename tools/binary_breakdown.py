#!/usr/bin/env python3
"""Where a linked ELF executable's bytes come from: a symbol-size breakdown by D package and by static C library.

    python3 tools/binary_breakdown.py <executable> [--libraries <dir>] [--json <out>] [--top N]

Every defined symbol's size (`nm -S`) is attributed to its D package (from the mangled name: `flint.web.servlet`,
`std.format`, `core.internal`, ...) or, for C symbols, to the static library under `--libraries` that defines it
(`libcrypto`, `libssl`, ...). `.bss` takes no file bytes and is reported apart. `.eh_frame` unwind entries are
attributed the same way through the function each one covers. The report also gives the section sizes, the bytes
strip would remove, the largest symbols, and the per-type template instances of `flint.java.util` collections, so a
size question ("why is this binary larger than Go's?") starts from measured attribution rather than guesses.
Needs binutils (`nm`, `readelf`, `strip`) and, for readable D names, `ddemangle` on PATH or next to dmd.
"""
import argparse
import bisect
import collections
import json
import pathlib
import re
import shutil
import subprocess
import tempfile

DRUNTIME_PHOBOS = ('std', 'core', 'rt', 'object', 'gc', 'ldc', 'etc')
NESTED = ('engine', 'boot', 'web', 'java', 'jackson', 'jakarta', 'core', 'context', 'beans', 'security')


def run(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def identifiers(mangled, limit=4):
    """The leading qualified-name identifiers of a D mangled symbol (`_D5flint3web...` -> ['flint', 'web', ...])."""
    rest, out = mangled[2:], []
    while len(out) < limit:
        match = re.match(r'(\d+)', rest)
        if not match:
            break
        length = int(match.group(1))
        rest = rest[len(match.group(1)):]
        ident, rest = rest[:length], rest[length:]
        if not ident or not re.match(r'[A-Za-z_]', ident):
            break
        out.append(ident)
    return out


def d_package(mangled):
    parts = identifiers(mangled)
    if not parts:
        return 'D (other)'
    if parts[0].startswith('TypeInfo_'):
        return 'TypeInfo'
    if parts[0] in ('std', 'core'):
        return '.'.join(parts[:2])
    if parts[0] in DRUNTIME_PHOBOS:
        return parts[0]
    if parts[0] == 'flint' and len(parts) > 1:
        return '.'.join(parts[:3] if parts[1] in NESTED and len(parts) > 2 else parts[:2])
    return parts[0]


def library_symbols(directory):
    """Symbol name -> the archive defining it. A name several archives define (compiler locals such as `__func__.0`
    or `CSWTCH.29`, or the same routine bundled twice) can't be attributed and maps to 'C (ambiguous)'."""
    owners = collections.defaultdict(set)
    for archive in sorted(pathlib.Path(directory).glob('*.a')):
        listing = subprocess.run(['nm', '--defined-only', str(archive)], capture_output=True, text=True).stdout
        for line in listing.splitlines():
            fields = line.split()
            if len(fields) >= 3:
                owners[fields[2]].add(archive.stem)
    return {name: next(iter(found)) if len(found) == 1 else 'C (ambiguous)' for name, found in owners.items()}


def symbols(executable):
    table = []
    for line in run(['nm', '-S', '--size-sort', str(executable)]).splitlines():
        fields = line.split()
        if len(fields) == 4:
            table.append((int(fields[0], 16), int(fields[1], 16), fields[2], fields[3]))
    return table


def origin(name, owner):
    if name.startswith('_D'):
        return 'D'
    return owner.get(name, 'C (unattributed)')


def sections(executable):
    out = {}
    for line in run(['readelf', '-S', '--wide', str(executable)]).splitlines():
        match = re.match(r'\s*\[\s*\d+\]\s+(\S+)\s+(\S+)\s+[0-9a-f]+\s+[0-9a-f]+\s+([0-9a-f]+)', line)
        if match and match.group(1) != 'NULL':
            out[match.group(1)] = int(match.group(3), 16)
    return out


def unwind(executable, table, owner):
    """`.eh_frame` FDE bytes by origin, through the function each FDE covers."""
    functions = sorted((address, address + size, name) for address, size, kind, name in table if kind in 'tTwW')
    starts = [entry[0] for entry in functions]
    totals = collections.Counter()
    dump = subprocess.run(['readelf', '--debug-dump=frames', str(executable)], capture_output=True, text=True).stdout
    for line in dump.splitlines():
        match = re.match(r'[0-9a-f]+ ([0-9a-f]+) [0-9a-f]+ FDE cie=[0-9a-f]+ pc=([0-9a-f]+)\.\.', line)
        if not match:
            continue
        length, address = int(match.group(1), 16) + 4, int(match.group(2), 16)
        index = bisect.bisect_right(starts, address) - 1
        covered = functions[index][2] if index >= 0 and functions[index][0] <= address < functions[index][1] else ''
        totals[origin(covered, owner) if covered else 'unknown'] += length
    return dict(totals.most_common())


def demangle(names):
    tool = shutil.which('ddemangle')
    if not tool:
        return list(names)
    return subprocess.run([tool], input='\n'.join(names), capture_output=True, text=True).stdout.splitlines()


def collection_instances(table):
    """`flint.java.util` code by collection template and type argument: per-type copies of the same algorithm."""
    rows = [(size, name) for _, size, kind, name in table if kind not in 'bB' and name.startswith('_D5flint4java4util')]
    by_template, instances = collections.Counter(), collections.defaultdict(set)
    for (size, _), readable in zip(rows, demangle(name for _, name in rows)):
        match = re.search(r'flint\.java\.util\.(\w+)!(\((?:[^()]|\([^()]*\))*\)|[\w.]+)', readable)
        if match:
            by_template[match.group(1)] += size
            instances[match.group(1)].add(match.group(2))
    return {name: {'bytes': size, 'instances': len(instances[name])} for name, size in by_template.most_common()}


def breakdown(executable, libraries, top):
    owner = library_symbols(libraries) if libraries else {}
    table = symbols(executable)
    by_origin, by_package, bss = collections.Counter(), collections.Counter(), collections.Counter()
    kinds = collections.Counter()
    for _, size, kind, name in table:
        where = origin(name, owner)
        if kind in 'bB':
            bss[d_package(name) if where == 'D' else where] += size
            continue
        by_origin[where] += size
        if where == 'D':
            by_package[d_package(name)] += size
            kinds['vtbl' if '6__vtblZ' in name else 'ClassInfo' if '7__ClassZ' in name
                  else 'TypeInfo or __init' if 'TypeInfo' in name or '6__initZ' in name else 'code and data'] += size
    largest = sorted(((size, name) for _, size, kind, name in table if kind not in 'bB'), reverse=True)[:top]
    with tempfile.TemporaryDirectory() as temporary:
        stripped = pathlib.Path(temporary) / 'stripped'
        shutil.copyfile(executable, stripped)
        subprocess.run(['strip', '--strip-all', str(stripped)], check=True)
        stripped_bytes = stripped.stat().st_size
    return {
        'schema': 'flint.binary-breakdown/1',
        'executable': str(executable),
        'file_bytes': pathlib.Path(executable).stat().st_size,
        'stripped_bytes': stripped_bytes,
        'sections': sections(executable),
        'symbol_bytes_by_origin': dict(by_origin.most_common()),
        'd_bytes_by_package': dict(by_package.most_common()),
        'd_bytes_by_kind': dict(kinds.most_common()),
        'bss_bytes': dict(bss.most_common()),
        'eh_frame_bytes_by_origin': unwind(executable, table, owner),
        'java_util_collections': collection_instances(table),
        'largest_symbols': [{'bytes': size, 'symbol': readable}
                            for (size, _), readable in zip(largest, demangle(name for _, name in largest))],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('executable')
    parser.add_argument('--libraries', help='directory of the static C libraries the executable linked')
    parser.add_argument('--json', help='write the full report here')
    parser.add_argument('--top', type=int, default=25)
    args = parser.parse_args()
    report = breakdown(args.executable, args.libraries, args.top)
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['executable']}: {report['file_bytes']:,} bytes, {report['stripped_bytes']:,} stripped")
    for title, key, limit in (('By origin', 'symbol_bytes_by_origin', 12), ('D by package', 'd_bytes_by_package', 25),
                              ('.eh_frame by origin', 'eh_frame_bytes_by_origin', 8),
                              ('D by kind', 'd_bytes_by_kind', 5)):
        print(f'\n{title}:')
        for name, size in list(report[key].items())[:limit]:
            print(f'  {size:>10,}  {name}')
    print('\nflint.java.util collections (bytes, type instances):')
    for name, row in list(report['java_util_collections'].items())[:10]:
        print(f"  {row['bytes']:>10,}  {row['instances']:>4}  {name}")
    print('\nLargest symbols:')
    for row in report['largest_symbols']:
        print(f"  {row['bytes']:>10,}  {row['symbol'][:110]}")


if __name__ == '__main__':
    main()
