#!/usr/bin/env python3
"""Module size and template caps for a merge-train candidate (coordinator, 2026-11-26 15:14Z).

The 15:02Z landing kept both apps green, yet two framework module DoDs on main went red: aop's probe nearly doubled
and security-core passed its template cap. A shared core/java change landed through other modules' closures, and
nothing re-ran their probes. This runs, for a candidate checked out here, the definition of done's `budgets` probes
(tools/measure_builds.py --framework-sizes: incremental linked bytes and template instances, deterministic, no
timing) of every framework module whose dependency closure contains a module the candidate changed against BASE.
It compares them with the caps in policy/framework.json.

A cap breach fails only when it is the candidate's: each breaching module is measured again at BASE (a temporary
worktree). A new breach fails at any size; a module already over its cap on main fails the candidate only when it
grows by more than OPEN_BREACH_GROWTH (1%). So main's own open breaches never block the submissions, its fix
included.

    python3 tools/module_probes.py --base <main commit> [--report out.json]

Exit 0: no new or worsened breach; 1: a breach the candidate causes, each named; 2: the probes could not run.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('incremental_linked_bytes', 'template_instances')


def git(*args, cwd=None):
    return subprocess.run(['git', *args], cwd=cwd or ROOT, capture_output=True, text=True, check=True).stdout


def policy_at(commit, name):
    try:
        return json.loads(git('show', f'{commit}:policy/{name}'))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return {}


def graph(commit):
    """({module or package: directory}, {name: [flint:* dependencies]}, {framework module: its entry}) at `commit`."""
    directories, edges = {}, {}
    for name, meta in policy_at(commit, 'packages.json').get('packages', {}).items():
        directories[name] = meta.get('directory', f'packages/{name}')
        edges[name] = list(meta.get('dependencies', []))
    boot = policy_at(commit, 'boot.json')
    for group in ('libraries', 'starters'):
        for name, meta in boot.get(group, {}).items():
            if meta.get('directory'):
                directories[name] = meta['directory']
            edges[name] = list(meta.get('dependencies', []))
    framework = policy_at(commit, 'framework.json').get('modules', {})
    for name, meta in framework.items():
        directories[name] = meta['directory']
        edges[name] = list(meta.get('dependencies', []))
    return directories, edges, framework


def owner(path, directories):
    """The module or package whose directory holds `path` (the longest match), or None."""
    best = None
    for name, directory in directories.items():
        prefix = directory.rstrip('/') + '/'
        if path.startswith(prefix) and (best is None or len(prefix) > len(directories[best].rstrip('/')) + 1):
            best = name
    return best


def affected(base, head='HEAD'):
    """Framework modules (with a probe) whose dependency closure contains a module the candidate changed, plus any
    whose framework.json entry (its caps) changed. Sorted."""
    directories, edges, framework = graph(head)
    changed = set()
    for path in git('diff', '--name-only', f'{base}..{head}').split():
        name = owner(path, directories)
        if name:
            changed.add(name)
    before = policy_at(base, 'framework.json').get('modules', {})
    changed |= {name for name, meta in framework.items() if before.get(name) != meta}

    def closure(name, seen=None):
        seen = set() if seen is None else seen
        for dep in edges.get(name, []):
            dep = dep.removeprefix('flint:')
            if dep not in seen:
                seen.add(dep)
                closure(dep, seen)
        return seen
    return sorted(name for name, meta in framework.items()
                  if meta.get('bench') and (name in changed or closure(name) & changed))


def measure(modules, root):
    """{module: {key: value}} from measure_builds --framework-sizes run in `root`."""
    if not modules:
        return {}
    with tempfile.TemporaryDirectory(prefix='module-probes-') as directory:
        out = Path(directory) / 'sizes.json'
        command = [sys.executable, 'tools/measure_builds.py', '--framework-sizes', '--output', str(out)]
        for module in modules:
            command += ['--framework', module]
        # A verifier links .native (and .tools) into its worktree; .gitignore's `.native/` matches only a directory,
        # so measure_builds' commit-identity check would call the link an untracked input (17:15Z train). These
        # probes are not certified evidence: exclude the two links for this run only, through git's environment.
        excludes = Path(directory) / 'excludes'
        excludes.write_text('.native\n.tools\n')
        env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.excludesFile',
                   GIT_CONFIG_VALUE_0=str(excludes))
        done = subprocess.run(command, cwd=root, capture_output=True, text=True, env=env)
        if done.returncode != 0 or not out.is_file():
            raise RuntimeError(f'measure_builds --framework-sizes failed in {root}:\n{(done.stdout + done.stderr)[-3000:]}')
        rows = json.loads(out.read_text()).get('framework', {})
    return {module: {key: rows.get(module, {}).get(key) for key in KEYS} for module in modules}


def base_tree(base, root):
    """A temporary worktree at `base` sharing `root`'s toolchains and natives."""
    directory = Path(tempfile.mkdtemp(prefix='module-probes-base-'))
    tree = directory / 'tree'
    git('worktree', 'add', '-q', '--detach', str(tree), base, cwd=root)
    for name in ('.tools', '.native', '.flint/peers', '.flint/bin'):
        source = root / name
        if source.exists():
            (tree / name).parent.mkdir(parents=True, exist_ok=True)
            (tree / name).symlink_to(source.resolve(), target_is_directory=True)
    # The same native blocks as the candidate (native_build --emit-dub writes them into each dub.sdl there): with the
    # native install linked, measure_builds requires them (17:43Z train), and both sides are then built alike.
    blocks = git('diff', 'HEAD', '--', '*dub.sdl', cwd=root)
    if blocks:
        patch = directory / 'native-blocks.patch'
        patch.write_text(blocks)
        done = subprocess.run(['git', 'apply', '--whitespace=nowarn', str(patch)], cwd=tree, capture_output=True,
                              text=True)
        if done.returncode != 0:
            raise RuntimeError(f'the native blocks do not apply at {base[:12]}: {done.stderr[-500:]}')
    return tree


# A module main already has over its cap fails a candidate only past this growth: a shared core change moves such a
# module by tens of bytes (5a2d60f43: web, webmvc, jdbc and framework-test each +80 B), which is not the candidate's
# breach. A new breach (main within the cap) fails at any size.
OPEN_BREACH_GROWTH = 0.01


def judge(head, caps, base_values, notices=None):
    """[(module, key, head value, cap, base value)] for each breach the candidate causes: new (main within the cap),
    or an open breach on main grown by more than OPEN_BREACH_GROWTH. Smaller growth of an open breach goes to
    `notices` (a list), if given."""
    found = []
    for module, values in head.items():
        for key in KEYS:
            value, cap = values.get(key), caps.get(module, {}).get(key)
            if value is None or cap is None or value <= cap:
                continue
            before = base_values.get(module, {}).get(key)
            if before is not None and before > cap:  # main's own open breach
                if value <= before * (1 + OPEN_BREACH_GROWTH):
                    if notices is not None and value > before:
                        notices.append((module, key, value, cap, before))
                    continue
            found.append((module, key, value, cap, before))
    return found


def main(argv=None):
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--base', required=True, help='the main commit the candidate is judged against')
    parser.add_argument('--report', type=Path, help='write the JSON report here too')
    parser.add_argument('--root', type=Path, default=ROOT, help='the candidate checkout (default: this one)')
    args = parser.parse_args(argv)
    ROOT = args.root.resolve()
    base = git('rev-parse', args.base).strip()
    modules = affected(base)
    _, _, framework = graph('HEAD')
    caps = {name: meta.get('budget', {}) for name, meta in framework.items()}
    report = {'schema': 'flint.module-probes/1', 'base': base, 'modules': modules, 'head': {}, 'base_values': {},
              'breaches': []}
    print(f'module probes: {len(modules)} module(s) whose closure the candidate touches: {" ".join(modules) or "-"}')
    try:
        report['head'] = measure(modules, ROOT)
        over = sorted({m for m, values in report['head'].items() for key in KEYS
                       if values.get(key) is not None and caps.get(m, {}).get(key) is not None
                       and values[key] > caps[m][key]})
        if over:
            tree = base_tree(base, ROOT)
            try:
                report['base_values'] = measure(over, tree)
            finally:
                subprocess.run(['git', 'worktree', 'remove', '--force', str(tree)], cwd=ROOT, capture_output=True)
                subprocess.run(['rm', '-rf', str(tree.parent)])
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f'module probes could not run: {error}', file=sys.stderr)
        return 2
    for module, values in report['head'].items():
        print(f'  {module}: ' + ', '.join(f'{key} {values.get(key)} (cap {caps.get(module, {}).get(key)})' for key in KEYS))
    notices = []
    for module, key, value, cap, before in judge(report['head'], caps, report['base_values'], notices):
        line = (f'module-cap: {module}: {key} {value:,} exceeds its cap {cap:,} (policy/framework.json); main '
                + (f'{before:,}' if before is not None else 'within its cap'))
        report['breaches'].append(line)
        print(line)
    for module, key, value, cap, before in notices:
        print(f'notice: {module}: {key} {value:,} over its cap {cap:,} already on main ({before:,}); grew '
              f'{value - before:,}, within {OPEN_BREACH_GROWTH:.0%}')
    report['notices'] = [list(row) for row in notices]
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    return 1 if report['breaches'] else 0


if __name__ == '__main__':
    sys.exit(main())
