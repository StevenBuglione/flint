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
module's own template instances, and the larger O3/Oz stripped-size difference), into the evidence's `framework`
section. tools/gates.py then requires a measurement for exactly the modules framework.json lists, each within its
budget and, against a base commit, within the regression ratios of policy/budgets.json. A module without a budget
or a probe fails: missing evidence never passes.

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


def require(value, message):
    if not value:
        raise ValueError(message)


def modules(root):
    path = Path(root) / 'policy' / 'framework.json'
    return json.loads(path.read_text(encoding='utf-8'))['modules'] if path.is_file() else {}


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
            if statistics.median(samples) >= budget[key]:
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
            if value > budget[key]:
                problems.append(f'framework {name}: {key} {value} exceeds {budget[key]}')
            if old is not None and value > old[key] * regression[ratio]:
                problems.append(f'framework {name}: {key} {value} regressed past {regression[ratio]}x the base {old[key]}')
    return problems
