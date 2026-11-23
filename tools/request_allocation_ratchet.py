"""Per-request allocation budgets only go down (owner decision 9a9aefa0, work-queue item 28).

policy/request-allocations.json holds, per Phase 1 app and suite request, a budget of GC allocations and bytes that
the app's request-allocation test enforces. A budget may be lowered but never raised: the structural gate walks every
first-parent commit that touched the file, then the working tree, and refuses any `allocations` or `bytes` budget
greater than its value in the previous version. A request that first appears later starts from its first budget; one
removed later is ignored. Lowering a budget and raising it back counts as a raise.

A tree that is not a git checkout of its own has no history to walk; `not_applicable` says so and the structural gate
prints that on stderr rather than passing silently.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

FILE = 'policy/request-allocations.json'
KEYS = ('allocations', 'bytes')


def budgets(text):
    """{(app, request, key): budget} from the file's text (empty for a missing file)."""
    if text is None:
        return {}
    found = {}
    for app, row in json.loads(text).get('apps', {}).items():
        for request, budget in row.get('requests', {}).items():
            for key in KEYS:
                if key in budget:
                    found[(app, request, key)] = budget[key]
    return found


def raises(versions):
    """Every raise in a sequence of (label, budgets) versions, as a message."""
    problems = []
    for (_, previous), (label, current) in zip(versions, versions[1:]):
        for name, value in sorted(current.items()):
            if name in previous and value > previous[name]:
                app, request, key = name
                problems.append(f'{app} "{request}": {key} budget raised from {previous[name]} to {value} in {label}; '
                                'per-request allocation budgets may only go down (owner decision 9a9aefa0)')
    return problems


def git(root, *arguments, check=True):
    result = subprocess.run(['git', *arguments], cwd=root, capture_output=True, text=True)
    if check and result.returncode:
        raise ValueError('git ' + ' '.join(arguments[:2]) + ' failed: ' + result.stderr.strip())
    return result


def not_applicable(root):
    """Why the rule cannot be checked in `root`, or None: `root` is not the top of a git checkout."""
    top = git(root, 'rev-parse', '--show-toplevel', check=False)
    if top.returncode or Path(top.stdout.strip()).resolve() != Path(root).resolve():
        return f'{FILE}: not a git checkout, so the budget ratchet has no history to check'
    return None


def check(root):
    """Messages for every budget raise in the file's first-parent history and the working tree."""
    if not_applicable(root):
        return []
    if git(root, 'rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        return [f'{FILE}: a shallow checkout cannot show the budget history; fetch it in full']
    commits = git(root, 'log', '--first-parent', '--reverse', '--format=%H', '--', FILE).stdout.split()
    versions = []
    for commit in commits:
        shown = git(root, 'show', f'{commit}:{FILE}', check=False)
        versions.append((commit[:12], budgets(shown.stdout if shown.returncode == 0 else None)))
    path = Path(root) / FILE
    versions.append(('the working tree', budgets(path.read_text(encoding='utf-8') if path.is_file() else None)))
    return raises(versions)
