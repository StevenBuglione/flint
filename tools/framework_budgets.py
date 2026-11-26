"""Budgets of the Spring-layer modules of policy/framework.json (ADR-030 section 5), measured like the 37 packages.

ADR-019 budgets each engine package of policy/packages.json, and the measured gate requires exactly those 37. The
Spring port adds framework/<artifact> modules, listed in policy/framework.json, and each carries its own budget,
with the same keys as a package's and a probe pair, as packages/<name>/bench does:

    "core": {
      "directory": "framework/core", "module": "flint.core", ...,
      "budget": {"dmd_cold_seconds": 0.9, "dmd_incremental_seconds": 0.6, "ldc_cold_seconds": 5.4,
                 "ldc_incremental_seconds": 2.7, "incremental_linked_bytes": 262144,
                 "compiler_peak_rss_bytes": 536870912, "template_instances": 2000},
      "bench": {"fixture": "framework/core/bench", "baseline": "framework/core/bench/baseline",
                "edit_source": "framework/core/source/flint/core/env/Environment.d"}
    }

The probe follows packages' PROBE_CONTRACT.md: the fixture executes a representative public operation of the module
with observable output, and the baseline is the same program without the module. tools/measure_builds.py measures
each module as it measures a package (nine cold and nine edited-source DMD and LDC builds, compiler peak RSS, the
module's own template instances, and the larger O3/Oz difference in loadable section bytes), into the
evidence's `framework` section. tools/gates.py then requires a measurement for exactly the modules framework.json
lists, each within its budget and, against a base commit, within the regression ratios of policy/budgets.json. A module without a budget
or a probe fails: missing evidence never passes.

A module may also carry `"provisional": [<budget keys>]`: values set as placeholders until the quiet-window timings
replace them, for compile times and compiler peak RSS, which cannot be measured on a busy machine. For a provisional
key only the absolute-ceiling test is skipped; the nine-finite-samples check and the regression ratio against a base
still apply, and check() reports every module that still carries provisional keys so a placeholder never silently
becomes permanent. incremental_linked_bytes and template_instances are deterministic and are never provisional. The
list must be non-empty (omit the field instead), and each key in it still needs its value in "budget".

Finer per-module linked-bytes budgets inside one artifact stay in policy/budgets.json "module_linked_bytes"
(tools/module_budgets.py).
"""
from __future__ import annotations

import json
import math
import statistics
from pathlib import Path

KEYS = ('dmd_cold_seconds', 'dmd_incremental_seconds', 'ldc_cold_seconds', 'ldc_incremental_seconds',
        'incremental_linked_bytes', 'compiler_peak_rss_bytes', 'template_instances')
SECONDS = KEYS[:4]
DETERMINISTIC = ('incremental_linked_bytes', 'template_instances')


def require(value, message):
    if not value:
        raise ValueError(message)


def modules(root):
    path = Path(root) / 'policy' / 'framework.json'
    return json.loads(path.read_text(encoding='utf-8'))['modules'] if path.is_file() else {}


def provisional(name, meta):
    """The validated set of a module's provisional budget keys."""
    if 'provisional' not in meta:
        return set()
    keys = meta['provisional']
    require(isinstance(keys, list) and keys and len(set(keys)) == len(keys) and set(keys) <= set(KEYS),
            f'framework module {name}: "provisional" must be a non-empty list of distinct budget keys')
    fixed = sorted(set(keys) & set(DETERMINISTIC))
    require(not fixed, f'framework module {name}: {", ".join(fixed)} is measured exactly and is never provisional')
    return set(keys)


def load(root, require_budget=True):
    """{name: fixture} for measure_builds, validated; a module without a budget or a probe fails.

    `require_budget=False` (measure_builds --framework-sizes) measures the probes before their budgets exist: it
    returns every module that has a probe and leaves out, for the caller to report, a module with neither probe nor
    budget. The full measurement and the gate keep requiring both.
    """
    fixtures = {}
    for name, meta in modules(root).items():
        budget, bench = meta.get('budget'), meta.get('bench')
        if not require_budget and budget is None:
            if bench is None:
                continue
            require(isinstance(bench, dict) and {'fixture', 'baseline', 'edit_source'} <= set(bench),
                    f'framework module {name}: "bench" must name fixture, baseline and edit_source')
            fixtures[name] = {'fixture': bench['fixture'], 'baseline': bench['baseline'],
                              'edit_source': bench['edit_source'], 'directory': meta['directory'],
                              'size_basis': 'framework_over_provider_equivalent_baseline'}
            continue
        require(isinstance(budget, dict) and set(budget) == set(KEYS),
                f'framework module {name}: "budget" must hold exactly ' + ', '.join(KEYS))
        for key in KEYS:
            value = budget[key]
            require(isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0
                    and (key in SECONDS or isinstance(value, int)), f'framework module {name}: budget {key}')
        provisional(name, meta)
        require(isinstance(bench, dict) and {'fixture', 'baseline', 'edit_source'} <= set(bench),
                f'framework module {name}: "bench" must name fixture, baseline and edit_source')
        fixtures[name] = {'fixture': bench['fixture'], 'baseline': bench['baseline'], 'edit_source': bench['edit_source'],
                          'directory': meta['directory'], 'size_basis': 'framework_over_provider_equivalent_baseline'}
    return fixtures


def check(current, baseline, regression, compare_series):
    """Problems of the measured `framework` section against framework.json's budgets and, when given, a base."""
    problems = []
    listed = modules(Path(__file__).resolve().parents[1])
    measured = current.get('framework', {})
    if set(measured) != set(listed):
        missing, extra = sorted(set(listed) - set(measured)), sorted(set(measured) - set(listed))
        problems.append('framework modules measured do not match policy/framework.json'
                        + (f'; missing {missing}' if missing else '') + (f'; unlisted {extra}' if extra else ''))
    base = baseline.get('framework', {}) if baseline is not None else None
    for name in sorted(set(listed) & set(measured)):
        budget, row = listed[name].get('budget') or {}, measured[name]
        try:
            placeholders = provisional(name, listed[name])
        except ValueError as exc:
            problems.append(str(exc))
            placeholders = set()
        if set(budget) != set(KEYS):
            problems.append(f'framework {name}: no budget in policy/framework.json')
            continue
        old = base.get(name) if base is not None else None
        if base is not None and old is None:
            problems.append(f'framework {name}: no base measurement to compare against')
        for key in SECONDS:
            samples = row.get(key, [])
            if len(samples) < 9 or not all(isinstance(x, (int, float)) and math.isfinite(x) and x > 0 for x in samples):
                problems.append(f'framework {name}: {key} needs 9 finite samples')
                continue
            if key not in placeholders and statistics.median(samples) >= budget[key]:
                problems.append(f'framework {name}: {key} median {statistics.median(samples):.3f} s exceeds {budget[key]}')
            if old is not None:
                try:
                    compare_series(samples, old[key], regression['compile_ratio_max'], f'framework {name}: {key}')
                except ValueError as exc:
                    problems.append(str(exc))
        for key, ratio in (('compiler_peak_rss_bytes', 'compiler_rss_ratio_max'), ('template_instances', 'template_ratio_max'),
                           ('incremental_linked_bytes', 'binary_ratio_max')):
            value = row.get(key)
            floor_ok = value is not None and type(value) is int and (value > 0 if key == 'compiler_peak_rss_bytes' else value >= 0)
            if not floor_ok:
                problems.append(f'framework {name}: {key} missing or malformed')
                continue
            if key not in placeholders and value > budget[key]:
                problems.append(f'framework {name}: {key} {value} exceeds {budget[key]}')
            if old is not None and value > old[key] * regression[ratio]:
                problems.append(f'framework {name}: {key} {value} regressed past {regression[ratio]}x the base {old[key]}')
    return problems


def provisional_report(root=None):
    """{module: [provisional keys]} for the gate output, so placeholders stay visible until replaced."""
    listed = modules(root or Path(__file__).resolve().parents[1])
    return {name: sorted(provisional(name, meta)) for name, meta in sorted(listed.items()) if provisional(name, meta)}


HEADROOM = {'seconds': 1.5, 'rss': 1.25}


def apply(root, result, headroom_seconds=HEADROOM['seconds'], headroom_rss=HEADROOM['rss'], receipt=None):
    """Replace each module's provisional timed budgets with measured values plus headroom, from a production
    `measure_builds.py --framework-builds` result; returns {module: {key: (old, new)}}. Only provisional keys
    change: a budget that was already measured is never raised by this step (AGENTS.md: no raising caps)."""
    require(result.get('mode') == 'framework-builds', 'apply takes a measure_builds --framework-builds result')
    path = Path(root) / 'policy' / 'framework.json'
    document = json.loads(path.read_text(encoding='utf-8'))
    changes = {}
    for name, row in result['framework'].items():
        meta = document['modules'].get(name)
        require(meta is not None, f'{name}: measured but not listed in policy/framework.json')
        keys = [key for key in meta.get('provisional', []) if key in SECONDS or key == 'compiler_peak_rss_bytes']
        for key in keys:
            if key in SECONDS:
                samples = row[key]
                require(len(samples) >= 9, f'{name}: {key} needs 9 samples')
                value = math.ceil(statistics.median(samples) * headroom_seconds * 100) / 100
            else:
                mib = 1 << 20
                value = math.ceil(row[key] * headroom_rss / mib) * mib
            changes.setdefault(name, {})[key] = (meta['budget'][key], value)
            meta['budget'][key] = value
        remaining = [key for key in meta.get('provisional', []) if key not in keys]
        if remaining:
            meta['provisional'] = remaining
        else:
            meta.pop('provisional', None)
        if keys:
            meta['budget_source'] = {'measured': receipt or 'measure_builds --framework-builds',
                                     'headroom': {'seconds': headroom_seconds, 'compiler_peak_rss_bytes': headroom_rss}}
    path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + '\n', encoding='utf-8')
    return changes


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='framework.json budgets: apply measured timings to provisional keys')
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('apply')
    p.add_argument('result', type=Path, help='a production measure_builds --framework-builds result')
    p.add_argument('--receipt', help='the measurement queue receipt this result came from')
    p.add_argument('--headroom-seconds', type=float, default=HEADROOM['seconds'])
    p.add_argument('--headroom-rss', type=float, default=HEADROOM['rss'])
    args = parser.parse_args()
    measured = json.loads(args.result.read_text())
    for module, keys in apply(Path(__file__).resolve().parents[1], measured, args.headroom_seconds, args.headroom_rss,
                              args.receipt).items():
        for key, (old, new) in keys.items():
            print(f'{module}: {key} {old} -> {new}')
