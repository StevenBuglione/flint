#!/usr/bin/env python3
"""A raised per-endpoint budget needs an owner decision (owner decision 087f28a3; coordination rule 5).

    python3 tools/budget_raise_check.py [--base REV] [--head REV]

Walks every commit in `base..head` (default: the merge base with fp/main or origin/main, to HEAD) that changes a
benchmarks/spring/flint/<app>/budgets.json, and compares each endpoint's instruction budget with the parent's. A
budget raised by more than the parent's tolerance must come with a `Budget-Raise-Approved: <decision id>` trailer in
that commit's message, and the id must appear in docs/spring/phase1/decisions.md at that commit. Lowering is always
fine. Exit 1 names each unapproved raise. The Phase 2 agent never adds the trailer: it proposes a raise with its
evidence, and the coordinator takes it to the owner.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUDGETS = re.compile(r'^benchmarks/spring/flint/[^/]+/budgets\.json$')
TRAILER = re.compile(r'^Budget-Raise-Approved:\s*(\S+)\s*$', re.MULTILINE)
DECISIONS = 'docs/spring/phase1/decisions.md'


def git(*args, check=True):
    done = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)
    if check and done.returncode:
        raise SystemExit(f'git {" ".join(args)}: {done.stderr.strip()}')
    return done.stdout if done.returncode == 0 else None


def default_base():
    for ref in ('fp/main', 'origin/main', 'main'):
        base = git('merge-base', 'HEAD', ref, check=False)
        if base:
            return base.strip()
    raise SystemExit('no main branch to compare with; pass --base')


def raises(old, new):
    """[(endpoint, old, new)] for instruction budgets raised beyond the old file's tolerance."""
    if not old or not new or old.get('runner') != new.get('runner'):
        return []  # a first budget, or a re-seed on another runner class, is not a raise
    tolerance = old.get('tolerance', {}).get('instructions', 0.0)
    found = []
    for name, entry in new.get('endpoints', {}).items():
        before = old.get('endpoints', {}).get(name)
        if before is not None and entry['instructions'] > before['instructions'] * (1 + tolerance):
            found.append((name, before['instructions'], entry['instructions']))
    return found


def check(base, head):
    problems = []
    commits = git('rev-list', '--reverse', f'{base}..{head}').split()
    for commit in commits:
        changed = [path for path in git('diff-tree', '--no-commit-id', '--name-only', '-r', commit).split()
                   if BUDGETS.match(path)]
        if not changed:
            continue
        message = git('log', '-1', '--format=%B', commit)
        approvals = TRAILER.findall(message)
        decisions = git('show', f'{commit}:{DECISIONS}', check=False) or ''
        for path in changed:
            old_text = git('show', f'{commit}^:{path}', check=False)
            new_text = git('show', f'{commit}:{path}', check=False)
            found = raises(json.loads(old_text) if old_text else None, json.loads(new_text) if new_text else None)
            if not found:
                continue
            valid = [decision for decision in approvals if decision in decisions]
            if valid:
                continue
            detail = ', '.join(f'{name!r} {a:,} -> {b:,}' for name, a, b in found)
            reason = ('its Budget-Raise-Approved trailer names no entry of ' + DECISIONS) if approvals \
                else 'it has no Budget-Raise-Approved: <decision id> trailer'
            problems.append(f'{commit[:12]} raises {path}: {detail}; {reason}')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--base')
    parser.add_argument('--head', default='HEAD')
    args = parser.parse_args()
    problems = check(args.base or default_base(), args.head)
    for line in problems:
        print('budget raise: ' + line, file=sys.stderr)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
