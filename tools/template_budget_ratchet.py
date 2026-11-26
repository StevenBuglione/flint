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

A raise is allowed only in a commit whose message carries the trailer `Budget-Raise-Approved: <id>`, where <id> is
a rule named in policy/budget-raise-rules.json (new-module-rule, api-growth-rule, jdk-leaf-rule; a rule's `not_for`
patterns exclude budgets, such as engines from api-growth-rule) or the hash of an earlier commit that changed
docs/spring/phase1/decisions.md, where the owner's decision is recorded. Each accepted raise is reported. The
trailer cannot approve a raise that is only in the working tree: commit it with the trailer.

A tree that is not a git checkout of its own (a copied workspace, such as flint check's parity tests use) has no
history to walk. `not_applicable` says so, and the structural gate prints that on stderr rather than passing
silently. Every git checkout, CI's included, is checked.
"""
from __future__ import annotations

import fnmatch
import json
import re
import subprocess
from pathlib import Path

FILES = ('policy/packages.json', 'policy/framework.json')
KEY = 'template_instances'
RULES = 'policy/budget-raise-rules.json'
DECISIONS = 'docs/spring/phase1/decisions.md'
TRAILER = re.compile(r'^Budget-Raise-Approved:[ \t]*(\S+)[ \t]*$', re.MULTILINE)


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


def raises(versions, approve=None):
    """(problems, accepted) for a sequence of (label, {name: budget}) versions: every raise as a message, refused
    unless `approve(label, name)` returns the approving id (else a reason it does not, or None)."""
    problems, accepted = [], []
    for (_, previous), (label, current) in zip(versions, versions[1:]):
        for name, value in sorted(current.items()):
            if name in previous and value > previous[name]:
                verdict = approve(label, name) if approve else None
                change = f'{name}: {KEY} budget raised from {previous[name]} to {value} in {label}'
                if verdict and verdict[0]:
                    accepted.append(f'{change}, approved by {verdict[0]}')
                    continue
                reason = verdict[1] if verdict else 'it has no Budget-Raise-Approved: <id> trailer'
                problems.append(f'{change}; template budgets may only go down (owner decision 3) unless the commit '
                                f'carries an approved Budget-Raise-Approved trailer: {reason}')
    return problems, accepted


def load_rules(root):
    """{rule id: rule} from policy/budget-raise-rules.json, or {} when the file is missing."""
    path = Path(root) / RULES
    return json.loads(path.read_text(encoding='utf-8')).get('rules', {}) if path.is_file() else {}


def approver(root, rules):
    """approve(commit, name) for raises(): the commit's trailer must name a rule that covers `name`, or a commit
    before it (or it) that changed decisions.md."""
    def approve(commit, name):
        message = git(root, 'log', '-1', '--format=%B', commit, check=False)
        if message.returncode:
            return None, 'it is not a commit, so it has no trailer (commit it with the trailer)'
        ids = TRAILER.findall(message.stdout)
        if not ids:
            return None, 'it has no Budget-Raise-Approved: <id> trailer'
        reasons = []
        for decision in ids:
            rule = rules.get(decision)
            if rule is not None:
                if any(fnmatch.fnmatchcase(name, pattern) for pattern in rule.get('not_for', [])):
                    reasons.append(f'{decision} does not cover {name}')
                    continue
                return decision, None
            if re.fullmatch(r'[0-9a-f]{7,40}', decision) and recorded_decision(root, decision, commit):
                return decision, None
            reasons.append(f'{decision!r} is neither a rule in {RULES} nor a commit that changed {DECISIONS}')
        return None, '; '.join(reasons)
    return approve


def recorded_decision(root, decision, commit):
    """Whether `decision` is a commit, at or before `commit`, that changed decisions.md."""
    resolved = git(root, 'rev-parse', '--verify', '--quiet', decision + '^{commit}', check=False)
    if resolved.returncode:
        return False
    full = resolved.stdout.strip()
    if git(root, 'merge-base', '--is-ancestor', full, commit, check=False).returncode:
        return False
    changed = git(root, 'diff-tree', '--no-commit-id', '--name-only', '-r', '--root', full, check=False)
    return DECISIONS in changed.stdout.split()


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


def not_applicable(root, policy):
    """Why the rule cannot be checked in `root`, or None when it can (or is not configured): `root` is not the top of
    a git checkout, so there is no history to walk."""
    anchor = policy.get('template_budget_ratchet', {}).get('after')
    if not anchor:
        return None
    try:
        top = git(root, 'rev-parse', '--show-toplevel', check=False)
    except OSError:
        return f'template budget ratchet not applicable: no git history (git is not installed); anchor {anchor[:12]}'
    if top.returncode or Path(top.stdout.strip()).resolve() != Path(root).resolve():
        return f'template budget ratchet not applicable: no git history ({root} is not a git checkout); anchor {anchor[:12]}'
    return None


def check(root, policy):
    """Messages for every template budget raised without approval since the anchor in `policy`
    (policy/budgets.json), or [] when the rule is not configured or does not apply to this checkout."""
    return report(root, policy)[0]


def report(root, policy):
    """(problems, accepted raises) since the anchor in `policy`; ([], []) when the rule does not apply."""
    anchor = policy.get('template_budget_ratchet', {}).get('after')
    if not anchor or not_applicable(root, policy):
        return [], []
    root = Path(root)
    if git(root, 'rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
        return [f'template budget ratchet: the checkout is shallow; fetch the history since {anchor[:12]} '
                '(fetch-depth: 0) so budget raises can be checked'], []
    if git(root, 'cat-file', '-e', anchor + '^{commit}', check=False).returncode:
        return [f'template budget ratchet: anchor commit {anchor[:12]} is not in this checkout'], []
    if git(root, 'merge-base', '--is-ancestor', anchor, 'HEAD', check=False).returncode:
        return [], []
    commits = git(root, 'log', '--first-parent', '--reverse', '--format=%H', f'{anchor}..HEAD', '--', *FILES)
    versions = [(commit[:12], committed(root, commit)) for commit in commits.stdout.split()]
    versions.append(('the working tree', working_tree(root)))
    return raises(versions, approver(root, load_rules(root)))
