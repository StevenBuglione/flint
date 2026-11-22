#!/usr/bin/env python3
"""Check that every public declaration of the handoff API contracts exists in the implementation.

The declaration-only contracts under `handoff/contracts/source` define the public API. For each
contract module this tool lists its public members with DMD's JSON output, generates a probe that
imports the implementation module, and has the compiler report, for every contract member and every
public member of contract aggregates, whether it exists and the mangled type of each function
overload. A function overload matches when its mangled type (parameters, return type, attributes and
linkage) equals the contract's. Templates and aliases are checked by name only.

Exit status is nonzero when a contract member is missing or no implementation overload matches.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / 'handoff/contracts/source'


def public(member):
    return member.get('protection', 'public') in ('public', 'export') and not member.get('name', '').startswith('__')


def contract_symbols(dmd):
    with tempfile.TemporaryDirectory() as temp:
        output = Path(temp) / 'contracts.json'
        files = sorted(str(p) for p in CONTRACTS.rglob('*.d'))
        subprocess.run([dmd, '-o-', '-preview=dip1000', '-I' + str(CONTRACTS), '-X', '-Xf' + str(output)] + files,
                       check=True, env=dict(os.environ, FLINT_DMD_SERVER='0'))
        return json.loads(output.read_text())


def expectations(module):
    """Yield (path, kind, deco or None) for every public member to check."""
    def walk(prefix, members):
        for m in members:
            if not public(m) or 'name' not in m:
                continue
            kind = m.get('kind')
            path = prefix + [m['name']]
            if kind in ('function', 'constructor'):
                yield path, 'function', m.get('deco')
            elif kind in ('struct', 'class', 'interface', 'union'):
                yield path, 'aggregate', None
                yield from walk(path, m.get('members', []))
            elif kind == 'enum':
                yield path, 'enum', None
                for e in m.get('members', []):
                    if 'name' in e:
                        yield path + [e['name']], 'enum member', None
            elif kind in ('template', 'alias', 'variable', 'mixin'):
                yield path, kind, None
    yield from walk([], module.get('members', []))


def probe_source(module_name, items):
    """Probe that reports existence and a structural signature for every expected member."""
    lines = ['module flint_contract_probe;', 'static import impl = ' + module_name + ';',
             'import std.traits : FunctionAttribute, functionAttributes, ParameterStorageClassTuple, Parameters, ReturnType;',
             'enum string sig(alias f) = "R=" ~ ReturnType!f.stringof ~ " P=" ~ Parameters!f.stringof',
             '    ~ " S=" ~ ParameterStorageClassTuple!f.stringof ~ " A=" ~ attrs!f;',
             'template attrs(alias f) {',
             '    enum a = functionAttributes!f;',
             '    enum string attrs = ((a & FunctionAttribute.nothrow_) ? "nothrow," : "") ~ ((a & FunctionAttribute.nogc) ? "nogc," : "")',
             '        ~ ((a & FunctionAttribute.pure_) ? "pure," : "") ~ ((a & (FunctionAttribute.safe | FunctionAttribute.trusted)) ? "safe," : "")',
             '        ~ ((a & FunctionAttribute.const_) ? "const," : "") ~ ((a & FunctionAttribute.ref_) ? "ref," : "");',
             '}', '']
    for index, (path, kind, _) in enumerate(items):
        parent = 'impl' + ''.join('.' + p for p in path[:-1])
        name = '__ctor' if path[-1] == 'this' else path[-1]
        label = '.'.join(path)
        lines.append('static if (!__traits(compiles, __traits(hasMember, %s, "%s")) || !__traits(hasMember, %s, "%s"))'
                     % (parent, name, parent, name))
        lines.append('    pragma(msg, "MISSING %d %s");' % (index, label))
        if kind == 'function':
            lines.append('else static foreach (o; __traits(getOverloads, %s, "%s", true))' % (parent, name))
            lines.append('    pragma(msg, "OVERLOAD %d ", sig!o);' % index)
    return '\n'.join(lines) + '\n'


def run_probe(dmd, module_name, items, imports):
    with tempfile.TemporaryDirectory() as temp:
        probe = Path(temp) / 'probe.d'
        probe.write_text(probe_source(module_name, items))
        run = subprocess.run([dmd, '-o-', '-preview=dip1000', *imports, str(probe)], capture_output=True, text=True,
                             env=dict(os.environ, FLINT_DMD_SERVER='0'))
    missing, overloads = set(), {}
    for line in (run.stdout + run.stderr).splitlines():
        m = re.match(r'MISSING (\d+) ', line)
        if m:
            missing.add(int(m.group(1)))
            continue
        m = re.match(r'OVERLOAD (\d+) (.*)$', line)
        if m:
            overloads.setdefault(int(m.group(1)), []).append(m.group(2).strip())
    return run, missing, overloads


def satisfies(implementation, contract):
    """Same return, parameter types and storage classes; implementation keeps every contract attribute.

    The comparison is exact except for attributes, where the implementation may add guarantees.
    Added `scope` qualifiers are reported separately by `scope_strengthened` so they stay visible.
    """
    def split(sig):
        head, _, attrs = sig.rpartition(' A=')
        return head, set(a for a in attrs.split(',') if a)
    ih, ia = split(implementation)
    ch, ca = split(contract)
    return ih == ch and ca <= ia


def scope_strengthened(implementation, contract):
    """True when the only difference is `scope` added to parameters (DIP1000 strengthening)."""
    def normal(sig):
        head, _, attrs = sig.rpartition(' A=')
        head = re.sub(r'\bscope ', '', head).replace('ParameterStorageClass.scope_', 'ParameterStorageClass.none')
        # Parameter names inside delegate and function-pointer types are not part of the type.
        head = re.sub(r'(\b[\w!()\[\]*]+) [a-z_]\w*(?=[,)])', r'\1', head)
        head = head.replace('cast(ParameterStorageClass)18u', 'ParameterStorageClass.ref_')
        return head, set(a for a in attrs.split(',') if a)
    ih, ia = normal(implementation)
    ch, ca = normal(contract)
    return ih == ch and ca <= ia


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dmd', default='dmd')
    ap.add_argument('--package', action='append', help='Contract module name such as flint.arena')
    ap.add_argument('--json', type=Path, help='Write the full report as JSON')
    a = ap.parse_args()
    imports = ['-I' + str(p / 'source') for p in sorted((ROOT / 'packages').iterdir()) if (p / 'source').is_dir()]
    report = {}
    failures = 0
    for module in contract_symbols(a.dmd):
        name = module.get('name')
        if not name or (a.package and name not in a.package):
            continue
        items = list(expectations(module))
        run, missing, overloads = run_probe(a.dmd, name, items, imports)
        _, _, expected = run_probe(a.dmd, name, items, ['-I' + str(CONTRACTS)])
        problems, notes = [], []
        if run.returncode != 0:
            problems.append({'probe_error': run.stderr.strip().splitlines()[-5:]})
        for index, (path, kind, deco) in enumerate(items):
            label = '.'.join(path)
            if index in missing:
                problems.append({'missing': label, 'kind': kind})
            elif kind == 'function':
                for want in expected.get(index, []):
                    have = overloads.get(index, [])
                    if any(satisfies(h, want) for h in have):
                        continue
                    if any(scope_strengthened(h, want) for h in have):
                        notes.append({'scope_strengthened': label, 'contract': want, 'implementation': have})
                        continue
                    problems.append({'signature': label, 'contract': want, 'implementation': have})
        report[name] = {'checked': len(items), 'problems': problems, 'scope_strengthened': notes}
        failures += len(problems)
        status = ('ok' if not problems else '%d problem(s)' % len(problems)) + ('; %d scope-strengthened' % len(notes) if notes else '')
        print('%-22s %4d members  %s' % (name, len(items), status))
        for p in problems[:12]:
            print('    ' + json.dumps(p))
    if a.json:
        a.json.write_text(json.dumps(report, indent=2) + '\n')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
