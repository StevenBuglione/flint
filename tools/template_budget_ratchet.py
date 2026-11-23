"""Template budgets only go down (owner decision 3, docs/spring/phase1/decisions.md, 2026-11-23).

Each package's and framework module's `template_instances` budget was reset from the corrected count (own library
plus probe) times 1.25, rounded up to 50. From then on a budget may be lowered but never raised. policy/budgets.json
names the commit after which the rule applies:

    "template_budget_ratchet": {"after": "<commit>", "decision": "..."}

The reset commit is the first commit after it. The structural gate walks every first-parent commit since then that
touched policy/packages.json or policy/framework.json, then the working tree, and refuses any budget greater than its
value in the previous version. A package or module that first appears later starts from its first budget; one
removed later is ignored. Lowering a budget and then raising it back counts as a raise.

The walk needs the history since the anchor: a shallow checkout fails rather than passing unchecked. A checkout whose
HEAD does not descend from the anchor (a base commit older than the reset) is not subject to the rule.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

FILES = ('policy/packages.json', 'policy/framework.json')
KEY = 'template_instances'


def budgets(documents):
    """{'package <name>' or 'framework <name>': template budget} from the texts of FILES (None for a missing file)."""
    found = {}
    for path, text in zip(FILES, documents):
        if text is None:
            continue
        document = json.loads(text)
        kind, rows = ('package', document.get('packages', {})) if path.endswith('packages.json') \
            else ('framework', document.get('modules', {}))
        for name, meta in rows.items():
            value = meta.get('budget', {}).get(KEY)
            if value is not None:
                found[kind + ' ' + name] = value
    return found


def raises(versions):
    """Every raise in a sequence of (label, {name: budget}) versions, as a message."""
    problems = []
    for (_, previous), (label, current) in zip(versions, versions[1:]):
        for name, value in sorted(current.items()):
            if name in previous and value > previous[name]:
                problems.append(f'{name}: {KEY} budget raised from {previous[name]} to {value} in {label}; '
                                'template budgets may only go down (owner decision 3)')
    return problems


def git(root, *arguments, check=True):
    result = subprocess.run(['git', *arguments], cwd=root, capture_output=True, text=True)
    if check and result.returncode:
        raise ValueError('git ' + ' '.join(arguments[:2]) + ' failed: ' + result.stderr.strip())
    return result


def committed(root, commit):
    texts = []
    for path in FILES:
        shown = git(root, 'show', f'{commit}:{path}', check=False)
        texts.append(shown.stdout if shown.returncode == 0 else None)
    return budgets(texts)


def working_tree(root):
    return budgets([(Path(root) / path).read_text(encoding='utf-8') if (Path(root) / path).is_file() else None
                    for path in FILES])


def check(root, policy):
    """Messages for every template budget raised since the anchor in `policy` (policy/budgets.json), or [] when the
    rule is not configured or does not apply to this checkout."""
    anchor = policy.get('template_budget_ratchet', {}).get('after')
    if not anchor:
        return []
    root = Path(root)
    if git(root, 'rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        return [f'template budget ratchet: the checkout is shallow; fetch the history since {anchor[:12]} '
                '(fetch-depth: 0) so budget raises can be checked']
    if git(root, 'cat-file', '-e', anchor + '^{commit}', check=False).returncode:
        return [f'template budget ratchet: anchor commit {anchor[:12]} is not in this checkout']
    if git(root, 'merge-base', '--is-ancestor', anchor, 'HEAD', check=False).returncode:
        return []
    commits = git(root, 'log', '--first-parent', '--reverse', '--format=%H', f'{anchor}..HEAD', '--', *FILES)
    versions = [(commit[:12], committed(root, commit)) for commit in commits.stdout.split()]
    versions.append(('the working tree', working_tree(root)))
    return raises(versions)
