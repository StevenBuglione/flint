"""Repos and workspaces for the Flint repo split (plan section 7; ADR-023, platform modules).

Every flint:* package belongs to one repo (the `repo` field of policy/packages.json, policy/boot.json and policy/framework.json).
policy/repos.json says which repos each repo may depend on, so dependencies point only from portfolio repos to
boot, framework and flint, never back.

A workspace is the set of checkouts that hold those repos, at pinned commits:

    {"schema": "flint.workspace/1",
     "checkouts": {"flint": {"path": "../flint", "commit": "<sha>"},
                   "framework": {"path": "../flint-framework", "commit": "<sha>"}}}

Paths are relative to the workspace file. In the monorepo every repo is this checkout, which is the default when no
`--workspace` is given. The gate, measurement and native tools find a package's directory through the workspace.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def repo_policy(root=ROOT):
    path = Path(root) / 'policy' / 'repos.json'
    return _load(path) if path.is_file() else {'repos': {}, 'pending_edges': []}


def repo_layout(directory, repo, root=ROOT):
    """Where the monorepo directory `directory` (`packages/engine-web`, `boot/boot`) sits in `repo`'s own
    checkout, by the layout rules of policy/repos.json: `engine/web`, `core/flint-boot`. The flint repo keeps
    the monorepo layout."""
    if repo == 'flint':
        return directory
    parts = directory.split('/')
    head, rest = '/'.join(parts[:2]), parts[2:]
    for source, target in repo_policy(root).get('layout', []):
        if head == source or (source.endswith(('/', '-')) and head.startswith(source)):
            return '/'.join([target + head[len(source):], *rest])
    return directory


def package_repos(root=ROOT):
    """Every package, Boot library, starter and framework module, by name: (repo, home-relative directory)."""
    root = Path(root)
    found = {}
    for name, meta in _load(root / 'policy' / 'packages.json')['packages'].items():
        found[name] = (meta.get('repo', 'flint'), 'packages/' + name)
    boot = root / 'policy' / 'boot.json'
    if boot.is_file():
        policy = _load(boot)
        for group in ('libraries', 'starters'):
            for name, meta in policy.get(group, {}).items():
                found[name] = (meta.get('repo', 'boot'), meta['directory'])
    framework = root / 'policy' / 'framework.json'
    if framework.is_file():
        for name, meta in _load(framework)['modules'].items():
            found[name] = (meta.get('repo', 'framework'), meta['directory'])
    return found


def dependencies(root=ROOT):
    """Every package's flint:* dependencies by name."""
    root = Path(root)
    edges = {name: list(meta['dependencies']) for name, meta in _load(root / 'policy' / 'packages.json')['packages'].items()}
    boot = root / 'policy' / 'boot.json'
    if boot.is_file():
        policy = _load(boot)
        for group in ('libraries', 'starters'):
            for name, meta in policy.get(group, {}).items():
                edges[name] = list(meta['dependencies'])
    framework = root / 'policy' / 'framework.json'
    if framework.is_file():
        for name, meta in _load(framework)['modules'].items():
            edges[name] = list(meta['dependencies'])
    return edges


def app_dependencies(root=ROOT):
    """Each app's repo (policy/apps.json) and the flint:* packages its flint.toml depends on."""
    import tomllib
    root = Path(root)
    path = root / 'policy' / 'apps.json'
    apps = {}
    for name, meta in (_load(path)['apps'].items() if path.is_file() else []):
        manifest = root / meta['directory'] / 'flint.toml'
        if not manifest.is_file():
            continue
        document = tomllib.loads(manifest.read_text(encoding='utf-8'))
        names = [d[6:] for section in ('dependencies', 'test-dependencies')
                 for d in document.get(section, {}) if d.startswith('flint:')]
        apps[name] = (meta['repo'], names)
    return apps


def edge_violations(root=ROOT):
    """(from, to, message) for every dependency that points the wrong way between repos. Pending edges that
    policy/repos.json lists with a reason are reported separately and do not fail."""
    policy = repo_policy(root)
    repos = policy.get('repos', {})
    owners = package_repos(root)
    pending = {(e['from'], e['to']) for e in policy.get('pending_edges', [])}
    violations, deferred = [], []
    for name, targets in sorted(dependencies(root).items()):
        source = owners[name][0]
        if source not in repos:
            violations.append((name, '', f'{name}: repo {source!r} is not in policy/repos.json'))
            continue
        for target in targets:
            if target not in owners:
                continue
            destination = owners[target][0]
            if destination == source or destination in repos[source]['may_depend_on']:
                continue
            message = f'{name} ({source}) -> {target} ({destination}): {source} may not depend on {destination}'
            (deferred if (name, target) in pending else violations).append((name, target, message))
    for name, (source, targets) in sorted(app_dependencies(root).items()):
        for target in targets:
            destination = owners[target][0] if target in owners else None
            if destination is None or destination == source or destination in repos.get(source, {}).get('may_depend_on', []):
                continue
            violations.append((name, target, f'app {name} ({source}) -> {target} ({destination}): {source} may not '
                               f'depend on {destination}'))
    return violations, deferred


class Workspace:
    """Where each repo's checkout is; the monorepo when no workspace file is given."""

    def __init__(self, path=None):
        self.file = Path(path).resolve() if path else None
        self.checkouts = {}
        if self.file:
            document = _load(self.file)
            if document.get('schema') != 'flint.workspace/1':
                raise ValueError(f'{self.file}: schema must be flint.workspace/1')
            for repo, entry in document['checkouts'].items():
                self.checkouts[repo] = ((self.file.parent / entry['path']).resolve(), entry.get('commit'))

    def checkout(self, repo):
        if not self.file:
            return ROOT
        if repo not in self.checkouts:
            raise ValueError(f'the workspace has no checkout of the {repo} repo')
        return self.checkouts[repo][0]

    def package_dir(self, name, root=ROOT):
        repo, directory = package_repos(root)[name]
        return self.locate(repo, directory, root)

    def locate(self, repo, directory, root=ROOT):
        """`directory` in `repo`'s checkout: the monorepo path when the checkout has it, else the path in the
        extracted repo's layout (repo_layout)."""
        checkout = self.checkout(repo)
        same = checkout / directory
        return same if same.exists() else checkout / repo_layout(directory, repo, root)

    def verify(self):
        """Every checkout exists and sits at its pinned commit; returns the problems."""
        problems = []
        for repo, (path, commit) in sorted(self.checkouts.items()):
            if not path.is_dir():
                problems.append(f'{repo}: checkout {path} is missing')
                continue
            if commit:
                head = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'], capture_output=True, text=True)
                if head.returncode != 0 or not head.stdout.strip().startswith(commit):
                    problems.append(f'{repo}: {path} is at {head.stdout.strip() or "no commit"}, not {commit}')
        return problems


def packages_of(repo, root=ROOT):
    return sorted(name for name, (owner, _) in package_repos(root).items() if owner == repo)


def dub_root(workspace, output, root=ROOT):
    """Write `output/dub.sdl`: one DUB package named `flint` whose subpackages are every package, Boot library
    and starter at its repo's checkout, so `dub test flint:engine-web --root=<output>` builds a repo's packages against
    the other repos' checkouts. Every repo keeps the `flint:*` names; the workspace joins them."""
    import os
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    lines = ['// Generated by tools/workspace.py from the workspace\'s checkouts. Do not edit.', 'name "flint"',
             'targetType "none"']
    for name, (repo, directory) in sorted(package_repos(root).items()):
        path = workspace.locate(repo, directory, root)
        if (path / 'dub.sdl').is_file():
            lines.append('subPackage ' + json.dumps(os.path.relpath(path, output)))
    (output / 'dub.sdl').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return output / 'dub.sdl'


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Repo split workspaces (plan section 7).')
    parser.add_argument('command', choices=['verify', 'dub-root', 'edges'])
    parser.add_argument('--workspace', type=Path, help='flint.workspace/1 file; default: this monorepo')
    parser.add_argument('--output', type=Path, help='dub-root: directory for the generated dub.sdl')
    arguments = parser.parse_args()
    workspace = Workspace(arguments.workspace)
    if arguments.command == 'verify':
        problems = workspace.verify()
        for problem in problems:
            print('WORKSPACE:', problem)
        return 1 if problems else 0
    if arguments.command == 'dub-root':
        if not arguments.output:
            parser.error('dub-root needs --output')
        print(dub_root(workspace, arguments.output))
        return 0
    violations, deferred = edge_violations()
    for _, _, message in violations + deferred:
        print(message)
    return 1 if violations else 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
