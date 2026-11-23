#!/usr/bin/env python3
"""Linked size of unused classes with and without ModuleInfo.localClasses (Phase 0 binary-size levers).

D lists every class of a module in its ModuleInfo, so the linker's --gc-sections keeps every class's
TypeInfo_Class, vtable and virtual methods whether or not code uses the class. `-fno-moduleinfo-localclasses`
(LDC upstream, and the Flint DMD fork) leaves that list empty. This tool generates a class-heavy program
(by default 2,000 classes in 40 modules, of which main instantiates 50), builds it with each compiler with
and without the switch, strips it and prints the sizes as JSON. It also checks that the program prints the
same result in every build.

    python3 tools/measure_class_gc.py --dmd dmd --ldc ldc2 --output result.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

import profiles

SWITCH = '-fno-moduleinfo-localclasses'


def generate(directory, classes, modules, used):
    """Write the fixture's modules and main; returns the expected program output."""
    per_module = classes // modules
    source = directory / 'source'
    (source / 'fixture').mkdir(parents=True)
    names = []
    for m in range(modules):
        lines = ['module fixture.m%d;' % m, '', 'import fixture.base : Shape;', '']
        for c in range(per_module):
            index = m * per_module + c
            name = 'C%d' % index
            names.append(('fixture.m%d' % m, name, index))
            # Enough virtual code per class that a kept class is visible in the linked size.
            lines += ['final class %s : Shape' % name, '{',
                      '    private long state = %d;' % index,
                      '    override long area(long x) { long s = state; foreach (i; 0 .. x) s = s * 31 + i ^ %d; return s; }'
                      % index,
                      '    override string label() { return "%s"; }' % name,
                      '    override long scale(long x, long y) { return (x * %d + y) %% (state + 7); }' % (index + 3),
                      '}', '']
        (source / 'fixture' / ('m%d.d' % m)).write_text('\n'.join(lines))
    (source / 'fixture' / 'base.d').write_text('module fixture.base;\n\nabstract class Shape\n{\n'
                                   '    abstract long area(long x);\n    abstract string label();\n'
                                   '    abstract long scale(long x, long y);\n}\n')
    step = max(1, len(names) // used)
    chosen = names[::step][:used]
    body = ['module app;', '', 'import core.stdc.stdio : printf;', 'import fixture.base : Shape;']
    for module, name, _ in chosen:
        body.append('import %s : %s;' % (module, name))
    body += ['', 'int main()', '{', '    long total;', '    Shape[] shapes;']
    for _, name, _ in chosen:
        body.append('    shapes ~= new %s;' % name)
    body += ['    foreach (shape; shapes)', '        total += shape.area(5) + shape.scale(3, 4) + shape.label.length;',
             '    // Exception handling must survive --gc-sections.',
             '    try',
             '        throw new Exception("gc");',
             '    catch (Exception e)',
             '        total += e.msg.length;',
             '    printf("%lld\\n", total);', '    return 0;', '}', '']
    (source / 'app.d').write_text('\n'.join(body))
    expected = len('gc')
    mask = (1 << 64) - 1
    for _, name, index in chosen:
        s = index
        for i in range(5):
            s = ((s * 31 + i) ^ index) & mask
        signed = s - (1 << 64) if s >> 63 else s
        expected += signed + (3 * (index + 3) + 4) % (index + 7) + len(name)
    return sorted(str(p.relative_to(directory)) for p in source.rglob('*.d')), expected


def dmd_conf_without_export_dynamic(compiler, directory):
    """A copy of the compiler's dmd.conf without -L--export-dynamic, with %@P% made absolute."""
    executable = Path(shutil.which(compiler) or compiler).resolve()
    text = (executable.parent / 'dmd.conf').read_text()
    if '-L--export-dynamic' not in text:
        raise SystemExit('expected -L--export-dynamic in ' + str(executable.parent / 'dmd.conf'))
    path = directory / 'dmd-gc.conf'
    path.write_text(text.replace(' -L--export-dynamic', '').replace('%@P%', str(executable.parent)))
    return path


def build(compiler, flags, directory, files, output):
    command = [compiler] + flags + ['-of=' + str(output), '-I=source'] + files
    built = subprocess.run(command, cwd=directory, capture_output=True, text=True)
    if built.returncode:
        raise SystemExit(shlex.join(command) + '\n' + built.stdout + built.stderr)
    return command


def measure(compiler, flags, directory, files, label, strip):
    output = directory / ('app-' + label)
    command = build(compiler, flags, directory, files, output)
    run = subprocess.run([str(output)], check=True, capture_output=True, text=True)
    stripped = directory / ('stripped-' + label)
    subprocess.run([strip, '--strip-all', '-o', str(stripped), str(output)], check=True)
    data = stripped.read_bytes()
    return {'command': command, 'stripped_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'output': run.stdout.strip()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--dmd', help='the Flint DMD fork (omit to skip DMD)')
    parser.add_argument('--ldc', help='LDC 1.43 ldc2 (omit to skip LDC)')
    parser.add_argument('--strip', default='strip')
    parser.add_argument('--classes', type=int, default=2000)
    parser.add_argument('--modules', type=int, default=40)
    parser.add_argument('--used', type=int, default=50)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    if args.classes % args.modules:
        raise SystemExit('--classes must be a multiple of --modules')
    policy = profiles.load()
    plans = []
    if args.dmd:
        # The dev profile without debug information; size matters only for its relative change.
        dev = [f for f in policy['dev']['dflags'] if f not in ('-g', '-debug')] + ['-O', '-release']
        plans.append(('dmd', args.dmd, dev))
        # DMD links without --gc-sections and its dmd.conf exports every symbol (--export-dynamic, which
        # druntime's backtraces use for function names), and either one keeps every class alive. This
        # variant links as LDC does: a configuration without --export-dynamic, plus --gc-sections.
        plans.append(('dmd-gc', args.dmd, dev + ['-L--gc-sections']))
    if args.ldc:
        for name in ('release', 'size'):
            flags = [f for f in policy[name]['dflags'] if f != SWITCH]
            plans.append(('ldc-' + name, args.ldc, flags))
    if not plans:
        raise SystemExit('give --dmd and/or --ldc')
    result = {'schema': 1, 'producer': 'tools/measure_class_gc.py', 'classes': args.classes,
              'modules': args.modules, 'used': args.used, 'switch': SWITCH, 'builds': {}}
    with tempfile.TemporaryDirectory(prefix='flint-class-gc-') as temporary:
        directory = Path(temporary)
        files, expected = generate(directory, args.classes, args.modules, args.used)
        result['expected_output'] = str(expected)
        for label, compiler, flags in plans:
            if label == 'dmd-gc':
                flags = ['-conf=' + str(dmd_conf_without_export_dynamic(compiler, directory))] + flags
            row = {}
            for variant, extra in (('with_localclasses', []), ('without_localclasses', [SWITCH])):
                row[variant] = measure(compiler, flags + extra, directory, files, label + '-' + variant, args.strip)
                if row[variant]['output'] != str(expected):
                    raise SystemExit('%s %s printed %s, expected %d' % (label, variant, row[variant]['output'], expected))
            row['saved_bytes'] = row['with_localclasses']['stripped_bytes'] - row['without_localclasses']['stripped_bytes']
            result['builds'][label] = row
            print('%-12s with %9d  without %9d  saved %9d' % (label, row['with_localclasses']['stripped_bytes'],
                  row['without_localclasses']['stripped_bytes'], row['saved_bytes']), flush=True)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
