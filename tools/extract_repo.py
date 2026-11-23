#!/usr/bin/env python3
"""Extract one repo of the split from a fresh clone of the monorepo, keeping history (plan section 7, step 5).

    python3 tools/extract_repo.py framework --source git@github.com:flint-projects/flint.git --into /tmp/split

It clones the monorepo afresh (never the working checkout), keeps the paths that move to the repo with
`git filter-repo`, and commits the repo's root files: a `dub.sdl` named `flint` listing its subpackages (every
repo keeps the `flint:*` names; a workspace joins them, see tools/workspace.py dub-root), the licence files, a
README and a .gitignore. One repo is never pushed: the extracted checkout is built and gated through a workspace
first.

Until the Phase 1 cutover (ADR-030) the extracted repos are mirrors of the monorepo. One command refreshes them:

    python3 tools/extract_repo.py --all --push --into /tmp/mirrors

It clones flint's main afresh, extracts every repo that has paths using that commit's own policy, runs the
structural gate per repo through a flint.workspace/1 file of the fresh checkouts, and only then force-pushes each
mirror's main. Each mirror's commit message records the flint source commit.
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
    for tree in ('native', 'examples', 'tests'):
        if repo != 'flint' and (root / tree / repo).is_dir():
            # The repo's own tree (workspace.REPO_TREES): native/framework builds flint_ffi_framework, and
            # examples/<repo> and tests/<repo> hold its applications and suites; <tree>/ once extracted.
            paths.append(f'{tree}/{repo}')
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
    """{earlier directory: later directory} for every moving directory git saw renamed, so filter-repo keeps the
    history from before the rename too. An earlier directory is the first two components of a renamed file's
    old path (packages/web, examples/golden-tui). Its later directory is where the files below it went, keeping
    their relative paths (examples/framework/golden-tui), else the first two components of the new path."""
    log = subprocess.run(['git', 'log', '--format=', '--name-status', '-M', '--diff-filter=R', 'HEAD'], cwd=checkout,
                         capture_output=True, text=True, check=True).stdout
    votes = {}
    for line in log.splitlines():
        fields = line.split('\t')
        if len(fields) != 3:
            continue
        old, new = fields[1], fields[2]
        parts = old.split('/')
        if len(parts) < 3:
            continue
        head, relative = '/'.join(parts[:2]), '/'.join(parts[2:])
        later = new[:-len(relative) - 1] if new.endswith('/' + relative) else '/'.join(new.split('/')[:2])
        if later == head:
            continue
        counts = votes.setdefault(head, {})
        counts[later] = counts.get(later, 0) + 1
    found = {}
    for old, counts in votes.items():
        # Git pairs an occasional identical small file across directories; the directory's rename is the target
        # most of its files went to.
        new, count = max(counts.items(), key=lambda item: item[1])
        # A renamed directory is gone; one that still exists (native/ffi) only gave some files away.
        if (checkout / old).exists():
            continue
        if count * 2 > sum(counts.values()) and any(new == path or new.startswith(path + '/') for path in paths):
            found[old] = new
    return dict(sorted(found.items()))


def earlier_files(checkout, paths, earlier):
    """[(earlier file, later file)] for files git saw move into a moving directory from outside every moving and
    earlier directory, one by one (native/ffi/flint_web.c -> packages/engine-web/native/ffi/flint_web.c), so their
    history comes along too."""
    log = subprocess.run(['git', 'log', '--format=', '--name-status', '-M', '--diff-filter=R', 'HEAD'], cwd=checkout,
                         capture_output=True, text=True, check=True).stdout
    kept = list(paths) + list(earlier)
    found, claimed = {}, set()
    for line in log.splitlines():  # newest first
        fields = line.split('\t')
        if len(fields) != 3:
            continue
        old, new = fields[1], fields[2]
        if any(old == path or old.startswith(path + '/') for path in kept):
            continue
        # One earlier name per file and per earlier path, the latest move, so no two land on one name.
        if any(new.startswith(path + '/') for path in paths) and new not in claimed and old not in found:
            found[old] = new
            claimed.add(new)
    return sorted(found.items())


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
        'Mirror of `flint-projects/flint` until the Phase 1 cutover (ADR-030); do not push here directly.\n\n'
        f'Its packages keep their `flint:*` names and resolve at this repo\'s platform version, which the flint '
        f'repo\'s `platform.lock` pins. It may depend on {depends}.\n\n'
        '## Building\n\n'
        'Check out the repos it depends on and describe them in a `flint.workspace/1` file, then, from the flint '
        'repo:\n\n```bash\npython3 tools/workspace.py dub-root --workspace workspace.json --output .flint/workspace\n'
        'dub test flint:<package> --root=.flint/workspace\n'
        f'python3 tools/gates.py --gate structural --workspace workspace.json --repo {repo}\n```\n')


def extract(repo, source, commit, into, root=ROOT):
    """Clone `source` afresh into `into`/flint-<repo>, keep `repo`'s paths with their history in its layout, and
    commit the root files. Returns the summary printed as JSON."""
    paths = moving_paths(repo, root)
    if not paths:
        raise SystemExit(f'nothing moves to {repo}')
    checkout = (into / ('flint-' + repo)).resolve()
    if checkout.exists():
        raise SystemExit(f'{checkout} exists; extraction starts from a fresh clone')
    run(['git', 'clone', '--no-local', '--quiet', source, str(checkout)])
    run(['git', 'checkout', '--quiet', '-B', 'main', commit], checkout)
    source_commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=checkout, capture_output=True, text=True,
                                   check=True).stdout.strip()
    moves = renames(repo, checkout, paths, root)

    def placed(path):
        """Where a path below a moving directory lands in the extracted repo."""
        for old, new in moves:
            if path == old or path.startswith(old + '/'):
                return new + path[len(old):]
        return path
    # Earlier names come along with their history, renamed to where their later name goes.
    earlier = [(old, placed(new)) for old, new in earlier_names(checkout, paths).items()]
    files = [(old, placed(new)) for old, new in earlier_files(checkout, paths, dict(earlier))]
    run(['git', 'filter-repo', '--force', '--quiet', '--refs', 'main',
         *sum((['--path', p] for p in paths + [old for old, _ in earlier] + [old for old, _ in files]), []),
         *sum((['--path-rename', f'{old}/:{new}/'] for old, new in moves + earlier), []),
         *sum((['--path-rename', f'{old}:{new}'] for old, new in files), [])], checkout)
    rewritten = rewrite_references(checkout, moves)
    root_files(repo, checkout, root)
    run(['git', 'add', '-A'], checkout)
    run(['git', 'commit', '--quiet', '-m', f'Extract the {repo} repo from flint-projects/flint at '
         f'{source_commit[:12]}\n\nSource commit: flint-projects/flint@{source_commit}. Kept with history: '
         f'{", ".join(paths)}, in the layout of policy/repos.json ({len(moves)} directories moved, '
         f'{len(rewritten)} files\' references updated). Root files: dub.sdl (the flint namespace\'s subpackages '
         'of this repo), LICENSE, NOTICE, README.md and .gitignore.'], checkout)
    return {'repo': repo, 'checkout': str(checkout), 'source_commit': source_commit, 'paths': paths,
            'moves': dict(moves), 'earlier': dict(earlier), 'files': dict(files), 'rewritten': rewritten}


def refresh(source, commit, into, push, remote):
    """Extract every repo that has paths from one flint commit, gate each through a workspace of the fresh
    checkouts, and with `push` force-push their mains. The extracted repos are mirrors until the Phase 1 cutover
    (ADR-030), so nobody else pushes to them and a force-push loses nothing."""
    into = into.resolve()
    if into.exists():
        raise SystemExit(f'{into} exists; a refresh starts from fresh clones')
    flint = into / 'flint'
    run(['git', 'clone', '--no-local', '--quiet', source, str(flint)])
    run(['git', 'checkout', '--quiet', commit], flint)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=flint, capture_output=True, text=True,
                         check=True).stdout.strip()
    # The flint commit's own policy decides what moves where.
    policy = repo_policy(flint)['repos']
    repos = [repo for repo in sorted(policy) if repo != 'flint' and moving_paths(repo, flint)]
    summaries = [extract(repo, source, sha, into, flint) for repo in repos]
    checkouts = {'flint': {'path': 'flint', 'commit': sha}}
    for summary in summaries:
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=summary['checkout'], capture_output=True, text=True,
                              check=True).stdout.strip()
        checkouts[summary['repo']] = {'path': Path(summary['checkout']).name, 'commit': head}
    workspace = into / 'workspace.json'
    workspace.write_text(json.dumps({'schema': 'flint.workspace/1', 'checkouts': checkouts}, indent=2) + '\n')
    for repo in repos:
        run([sys.executable, str(flint / 'tools' / 'gates.py'), '--gate', 'structural', '--workspace', str(workspace),
             '--repo', repo], flint)
    pushed = []
    if push:
        for summary in summaries:
            url = remote.format(github=policy[summary['repo']]['github'])
            run(['git', 'push', '--quiet', '--force', url, 'main:main'], summary['checkout'])
            pushed.append(url)
    return {'source_commit': sha, 'workspace': str(workspace),
            'repos': {repo: checkouts[repo]['commit'] for repo in repos}, 'pushed': pushed}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('repo', nargs='?', choices=sorted(repo_policy()['repos']))
    parser.add_argument('--all', action='store_true', help='every repo with paths, gated through one workspace')
    parser.add_argument('--push', action='store_true', help='with --all: force-push each mirror\'s main')
    parser.add_argument('--remote', default='git@github.com:{github}.git', help='push URL; {github} is owner/name')
    parser.add_argument('--source', default='git@github.com:flint-projects/flint.git')
    parser.add_argument('--commit', default=None, help='the monorepo commit to extract (default: HEAD, or '
                        'origin/main with --all)')
    parser.add_argument('--into', type=Path, required=True, help='directory for the fresh clones')
    arguments = parser.parse_args()
    if arguments.all == bool(arguments.repo) or (arguments.push and not arguments.all):
        parser.error('name one repo, or --all (with --push to update the mirrors)')
    if arguments.all:
        result = refresh(arguments.source, arguments.commit or 'origin/main', arguments.into, arguments.push,
                         arguments.remote)
    else:
        result = extract(arguments.repo, arguments.source, arguments.commit or 'HEAD', arguments.into)
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
