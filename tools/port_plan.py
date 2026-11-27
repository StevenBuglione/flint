#!/usr/bin/env python3
"""Port plans: the per-type decisions the mechanical porter reads (docs/spring/phase2/porter-plan.md).

api/port-plan/<project>-<version>.json holds, for each Java type, the D kind, the destination module, the rules
with their IDs and, where known, whether storage is templated and whether a GC-free path is required. A lane edits
the plan, not D code, for a mechanical shape.

  --seed   writes the plans from every exact, mapped type row in api/*/mapping.json. The module and rules come
           from the row and the D kind from compiling the hand port. A lane's kind and storage choices are kept;
           module, name, status and rules follow the mapping row on every seed. Mapped types it can't classify go
           under "unresolved" with the reason.
  --check  verifies every plan: the schema, a known kind, that a mapped type's module and rules agree with its
           mapping row, and that no entry names a type its upstream manifest doesn't declare.

Seeding compiles, so run it under tools/measure_queue.py hold on venus.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from api_differences import Classifier  # noqa: E402
import porter_gate  # noqa: E402

PLANS = ROOT / 'api' / 'port-plan'
SCHEMA = 'flint.port-plan/1'
KINDS = ('struct', 'final class', 'class', 'abstract class', 'interface', 'enum', 'uda', 'functions')

PROBE = '''
string porterKind(alias S)()
{
    static if (is(S == enum))
        return "enum";
    else static if (is(S == struct) || is(S == union))
        return "struct";
    else static if (is(S == interface))
        return "interface";
    else static if (is(S == class))
        return __traits(isFinalClass, S) ? "final class" : __traits(isAbstractClass, S) ? "abstract class" : "class";
    else static if (__traits(isTemplate, S))
        return "template";
    else
        return "functions";
}
'''


def mapped_types():
    """(plan file stem, type id, row) for every exact type row that is ported or adapted with a D symbol."""
    pins = {(u['project'], u['version']): u for u in porter_gate.load_json(ROOT / 'api' / 'upstreams.json')['upstreams']}
    mappings = {p.parent.name: porter_gate.load_json(p)['elements'] for p in (ROOT / 'api').glob('*/mapping.json')}
    classifiers = {repo: Classifier(elements) for repo, elements in mappings.items()}
    for path in sorted((ROOT / 'api' / 'upstream').glob('*.json')):
        manifest = porter_gate.load_json(path)
        pin = pins.get((manifest['project'], manifest['version']))
        if pin is None or pin.get('repo') not in classifiers:
            continue
        for t in manifest['types']:
            found = classifiers[pin['repo']].classify(t['id'])
            if found and found[0] == t['id'] and found[1]['status'] in ('ported', 'adapted') and '.' in found[1].get('d', ''):
                yield f"{manifest['project']}-{manifest['version']}", t, found[1]


def probe_kinds(package, symbols, scratch):
    """{symbol: D kind} for the symbols that resolve in the package's import closure."""
    roots = porter_gate.import_paths(package)
    modules = sorted({s.rsplit('.', 1)[0] for s in symbols})
    lines = ['module porter_kinds;', PROBE]
    lines += [f'static import {m};' for m in modules]
    for symbol in symbols:
        lines.append(f'static if (__traits(compiles, {symbol})) pragma(msg, "PORTER-KIND {symbol} " ~ porterKind!({symbol}));')
    path = scratch / 'porter_kinds.d'
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    result = subprocess.run(['dmd', '-o-', '-d', '-preview=dip1000', *(f'-I{r}' for r in roots), str(path)],
                            cwd=scratch, capture_output=True, text=True, env=porter_gate.compiler_env(), check=False)
    found = dict(re.findall(r'PORTER-KIND (\S+) (\S.*)', result.stdout + result.stderr))
    if result.returncode and len(modules) > 1:
        # One module that doesn't compile in this closure shouldn't hide the others.
        found = {}
        for module in modules:
            found.update(probe_kinds(package, [s for s in symbols if s.rsplit('.', 1)[0] == module], scratch))
    return found


def entry_for(t, row, kind):
    rules = row.get('rules', [])
    entry = {'kind': 'uda' if 'R2' in rules and kind == 'struct' else kind, 'module': row['d'].rsplit('.', 1)[0],
             'd': row['d'].rsplit('.', 1)[1], 'status': row['status']}
    if rules:
        entry['rules'] = rules
    if t.get('typeParameters'):
        entry['storage'] = 'unset'
    return entry


def seed():
    index = porter_gate.module_index(porter_gate.import_roots())
    by_package = collections.defaultdict(list)
    rows, owner = {}, {}
    for stem, t, row in mapped_types():
        rows[t['id']] = (stem, t, row)
        module = row['d'].rsplit('.', 1)[0]
        owners = [porter_gate.package_of(p) for _, p in index.get(module, ())]
        by_package[owners[0] if owners and owners[0] else None].append(row['d'])
        owner[row['d']] = owners[0] if owners and owners[0] else None
    kinds = {}
    with tempfile.TemporaryDirectory(prefix='flint-port-plan-') as directory:
        for package, symbols in sorted(by_package.items(), key=lambda item: str(item[0])):
            if package is not None:
                kinds.update(probe_kinds(package, sorted(set(symbols)), Path(directory)))
    plans = collections.defaultdict(dict)
    pending = collections.defaultdict(dict)
    for type_id, (stem, t, row) in sorted(rows.items()):
        kind = kinds.get(row['d'])
        if kind in KINDS:
            plans[stem][type_id] = entry_for(t, row, kind)
            continue
        module = row['d'].rsplit('.', 1)[0]
        if owner[row['d']] is None:
            pending[stem][type_id] = f'no registered package declares {module}'
        elif kind is None:
            pending[stem][type_id] = f'{row["d"]} does not resolve in :{owner[row["d"]]}\'s import closure'
        else:
            pending[stem][type_id] = f'{row["d"]} is a D {kind}, which a plan kind does not describe yet'
    unresolved = sum(len(v) for v in pending.values())
    PLANS.mkdir(parents=True, exist_ok=True)
    written = {}
    for stem in sorted(set(plans) | set(pending)):
        path = PLANS / f'{stem}.json'
        existing = porter_gate.load_json(path)['types'] if path.is_file() else {}
        merged = dict(existing)
        for type_id, fresh in plans[stem].items():
            # The mapping row owns module, name, status and rules; a lane's kind and storage choices stay.
            kept = {k: v for k, v in existing.get(type_id, {}).items() if k not in ('module', 'd', 'status', 'rules')}
            merged[type_id] = {**fresh, **kept}
            if 'rules' not in fresh:
                merged[type_id].pop('rules', None)
        merged = dict(sorted(merged.items()))
        # Mapped types the seed couldn't classify stay listed with the reason, so a lane resolves them.
        waiting = {k: v for k, v in sorted(pending[stem].items()) if k not in merged}
        document = {'schema': SCHEMA, 'upstream': stem, 'types': merged}
        if waiting:
            document['unresolved'] = waiting
        path.write_text(json.dumps(document, indent=0) + '\n', encoding='utf-8')
        written[stem] = len(merged)
    return written, unresolved


def check():
    failures = []
    pins = {(u['project'], u['version']): u for u in porter_gate.load_json(ROOT / 'api' / 'upstreams.json')['upstreams']}
    manifests = {f"{m['project']}-{m['version']}": m for m in
                 (porter_gate.load_json(p) for p in (ROOT / 'api' / 'upstream').glob('*.json'))}
    mappings = {p.parent.name: Classifier(porter_gate.load_json(p)['elements']) for p in (ROOT / 'api').glob('*/mapping.json')}
    for path in sorted(PLANS.glob('*.json')):
        plan = porter_gate.load_json(path)
        if plan.get('schema') != SCHEMA or plan.get('upstream') != path.stem:
            failures.append(f'{path.name}: needs schema {SCHEMA} and upstream {path.stem}')
            continue
        manifest = manifests.get(path.stem)
        if manifest is None:
            failures.append(f'{path.name}: no pinned manifest api/upstream/{path.stem}.json')
            continue
        declared = {t['id'] for t in manifest['types']}
        for type_id in set(plan.get('unresolved', {})) & set(plan['types']):
            failures.append(f'{path.name}: {type_id} is both planned and unresolved; remove it from "unresolved"')
        classifier = mappings.get(pins[(manifest['project'], manifest['version'])].get('repo'))
        for type_id, entry in plan['types'].items():
            where = f'{path.name}: {type_id}'
            if type_id not in declared:
                failures.append(f'{where}: not declared by the pinned manifest')
            if entry.get('kind') not in KINDS or not str(entry.get('module', '')).startswith('flint.'):
                failures.append(f'{where}: needs a kind ({", ".join(KINDS)}) and a flint.* module')
            found = classifier.classify(type_id) if classifier else None
            if found and found[0] == type_id and found[1]['status'] in ('ported', 'adapted') and found[1].get('d'):
                row = found[1]
                if row['d'] != entry['module'] + '.' + entry.get('d', ''):
                    failures.append(f'{where}: plan says {entry["module"]}.{entry.get("d")}, mapping says {row["d"]}')
                if row.get('rules', []) != entry.get('rules', []):
                    failures.append(f'{where}: plan rules {entry.get("rules", [])} differ from mapping {row.get("rules", [])}')
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--seed', action='store_true')
    group.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    if args.seed:
        written, unresolved = seed()
        print(json.dumps({'plans': written, 'types': sum(written.values()), 'unresolved': unresolved}, indent=1))
        return 0
    failures = check()
    for failure in failures:
        print('PORT PLAN:', failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
