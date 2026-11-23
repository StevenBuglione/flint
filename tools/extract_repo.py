#!/usr/bin/env python3
"""Extract one repo of the split from a fresh clone of the monorepo, keeping history (plan section 7, step 5).

    python3 tools/extract_repo.py framework --source git@github.com:flint-projects/flint.git --into /tmp/split

It clones the monorepo afresh (never the working checkout), keeps the paths that move to the repo with
`git filter-repo`, and commits the repo's root files: a `dub.sdl` named `flint` listing its subpackages (every
repo keeps the `flint:*` names; a workspace joins them, see tools/workspace.py dub-root), the licence files, a
README and a .gitignore. It never pushes: the extracted checkout is built and gated through a workspace first.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import re  # noqa: E402
from workspace import package_repos, repo_layout, repo_policy  # noqa: E402


def moving_paths(repo, root=ROOT):
    """The monorepo paths that move to `repo`: its packages, Boot libraries, starters and applications."""
    paths = [directory for _, (owner, directory) in sorted(package_repos(root).items()) if owner == repo]
    apps = root / 'policy' / 'apps.json'
    if apps.is_file():
        paths += [meta['directory'] for meta in json.loads(apps.read_text())['apps'].values() if meta['repo'] == repo]
    if repo == 'boot':
        # boot/ and starters/ move whole: the bill of materials and anything else under them.
        paths = ['boot', 'starters']
    if (root / 'api' / repo / 'mapping.json').is_file():
        # The repo's API mapping (flint api coverage); renamed to api/mapping.json on extraction.
        paths.append(api_mapping_dir(repo))
    return sorted(set(paths))


def api_mapping_dir(repo):
    """The monorepo directory of a repo's API mapping; an extracted repo keeps it as api/."""
    return 'api/' + repo


def renames(repo, checkout, paths, root=ROOT):
    """(monorepo path, path in the extracted repo) for every moving directory whose place changes. boot/ and
    starters/ move child by child (core/, module/, platform/ and starter/)."""
    pairs = []
    for path in paths:
        if path == api_mapping_dir(repo):
            pairs.append((path, 'api'))
            continue
        children = sorted(p.name for p in (checkout / path).iterdir() if p.is_dir()) if path in ('boot', 'starters') \
            else None
        for directory in ([f'{path}/{c}' for c in children] if children is not None else [path]):
            target = repo_layout(directory, repo, root)
            if target != directory:
                pairs.append((directory, target))
    return pairs


def earlier_names(checkout, paths):
    """{earlier directory: later directory} for every moving directory that git saw renamed within its top-level
    tree (packages/web -> packages/engine-web), so filter-repo keeps the history from before the rename too."""
    log = subprocess.run(['git', 'log', '--format=', '--name-status', '-M', '--diff-filter=R', 'HEAD'], cwd=checkout,
                         capture_output=True, text=True, check=True).stdout
    found = {}
    for line in log.splitlines():
        fields = line.split('\t')
        if len(fields) != 3:
            continue
        old, new = fields[1].split('/'), fields[2].split('/')
        if len(old) < 3 or len(new) < 3 or old[0] != new[0] or old[:2] == new[:2]:
            continue
        if any(fields[2].startswith(path + '/') for path in paths):
            found.setdefault('/'.join(old[:2]), '/'.join(new[:2]))
    return dict(sorted(found.items()))


def rewrite_references(checkout, pairs):
    """Point the extracted tree's own references (recipes, scripts, docs) at the new places; returns the files
    changed."""
    patterns = [(re.compile(r'(?<![\w.-])' + re.escape(old) + r'(?![\w-])'), new) for old, new in pairs]
    changed = []
    tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=checkout, capture_output=True, text=True,
                             check=True).stdout.split('\0')
    for name in filter(None, tracked):
        path = checkout / name
        if path.is_symlink() or not path.is_file():
            continue
        try:
            text = path.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            continue
        new = text
        for pattern, replacement in patterns:
            new = pattern.sub(replacement, new)
        if new != text:
            path.write_text(new, encoding='utf-8')
            changed.append(name)
    return changed


def run(command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def root_files(repo, checkout, root=ROOT):
    meta = repo_policy(root)['repos'][repo]
    subpackages = []
    for name, (owner, directory) in sorted(package_repos(root).items()):
        directory = repo_layout(directory, repo, root)
        if owner == repo and (checkout / directory / 'dub.sdl').is_file():
            subpackages.append('subPackage ' + json.dumps(directory))
    (checkout / 'dub.sdl').write_text('\n'.join([
        f'// {meta["github"]}: the {repo} repo of Flint. Its packages keep the flint:* names; build them in a',
        '// workspace with the repos they depend on (python3 tools/workspace.py dub-root, in the flint repo).',
        'name "flint"', 'description "Flint ' + repo + ' (' + meta['kind'] + ' repo)"', 'license "Apache-2.0"',
        'targetType "none"', *subpackages]) + '\n')
    for name in ('LICENSE', 'NOTICE'):
        shutil.copyfile(root / name, checkout / name)
    shutil.copyfile(root / '.gitignore', checkout / '.gitignore')
    depends = ', '.join(f'`{d}`' for d in meta['may_depend_on']) or 'nothing'
    (checkout / 'README.md').write_text(
        f'# {meta["github"].split("/")[1]}\n\n'
        f'The {repo} repo of [Flint](https://github.com/flint-projects/flint), a {meta["kind"]} repo. It was '
        f'extracted from the Flint monorepo with its history (ADR-030; the ADR-023 amendment on platform modules).\n\n'
        f'Its packages keep their `flint:*` names and resolve at this repo\'s platform version, which the flint '
        f'repo\'s `platform.lock` pins. It may depend on {depends}.\n\n'
        '## Building\n\n'
        'Check out the repos it depends on and describe them in a `flint.workspace/1` file, then, from the flint '
        'repo:\n\n```bash\npython3 tools/workspace.py dub-root --workspace workspace.json --output .flint/workspace\n'
        'dub test flint:<package> --root=.flint/workspace\n'
        f'python3 tools/gates.py --gate structural --workspace workspace.json --repo {repo}\n```\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('repo', choices=sorted(repo_policy()['repos']))
    parser.add_argument('--source', default='git@github.com:flint-projects/flint.git')
    parser.add_argument('--commit', default='HEAD', help='the monorepo commit to extract')
    parser.add_argument('--into', type=Path, required=True, help='directory for the fresh clone')
    arguments = parser.parse_args()
    paths = moving_paths(arguments.repo)
    if not paths:
        raise SystemExit(f'nothing moves to {arguments.repo}')
    checkout = (arguments.into / ('flint-' + arguments.repo)).resolve()
    if checkout.exists():
        raise SystemExit(f'{checkout} exists; extraction starts from a fresh clone')
    run(['git', 'clone', '--no-local', '--quiet', arguments.source, str(checkout)])
    run(['git', 'checkout', '--quiet', '-B', 'main', arguments.commit], checkout)
    source_commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=checkout, capture_output=True, text=True,
                                   check=True).stdout.strip()
    moves = renames(arguments.repo, checkout, paths)
    # Earlier names come along with their history, renamed to where their later name goes.
    earlier = [(old, dict(moves).get(new, new)) for old, new in earlier_names(checkout, paths).items()]
    run(['git', 'filter-repo', '--force', '--refs', 'main',
         *sum((['--path', p] for p in paths + [old for old, _ in earlier]), []),
         *sum((['--path-rename', f'{old}/:{new}/'] for old, new in moves + earlier), [])], checkout)
    rewritten = rewrite_references(checkout, moves)
    root_files(arguments.repo, checkout)
    run(['git', 'add', '-A'], checkout)
    run(['git', 'commit', '--quiet', '-m', f'Extract the {arguments.repo} repo from flint-projects/flint at '
         f'{source_commit[:12]}\n\nKept with history: {", ".join(paths)}, in the layout of policy/repos.json '
         f'({len(moves)} directories moved, {len(rewritten)} files\' references updated). Root files: dub.sdl '
         f'(the flint namespace\'s subpackages of this repo), LICENSE, NOTICE, README.md and .gitignore.'], checkout)
    print(json.dumps({'repo': arguments.repo, 'checkout': str(checkout), 'source_commit': source_commit,
                      'paths': paths, 'moves': dict(moves), 'earlier': dict(earlier), 'rewritten': rewritten}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
