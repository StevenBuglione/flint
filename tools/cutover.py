#!/usr/bin/env python3
"""The repo-split cutover as one scripted operation (ADR-030; plan section 7), and its rehearsal.

    python3 tools/cutover.py --into /tmp/cutover            # rehearse: nothing leaves this machine
    python3 tools/cutover.py --into /tmp/cutover --push     # the real cutover, on the coordinator's call

It needs `git filter-repo` on PATH. Both run the same steps:

1. **Extract.** It clones flint at `--commit` (default: origin/main of `--source`) and extracts every repo that has
   paths (tools/extract_repo.py refresh), gated through a workspace of the fresh checkouts.
2. **Cut.** The pre-port Boot libraries and starters take legacy names (flint:legacy-boot, ...,
   flint:legacy-starter-web), in the extracted flint-boot (one commit) and in the flint clone, which records them
   in policy/renamed-packages.json so flint names the new name where an old one is used. On a `cutover` branch of
   that flint clone it removes every path that moved, keeps only the remaining subpackages in the root dub.sdl,
   and pins each extracted repo in platform.lock at its extracted commit, as "source": "github". Then it commits.
3. **Fetch.** As a Flint home it installs its flint CLI and fetches the pinned repos with their native DUB blocks
   (tools/platform_modules.py --fetch), from the local extracted checkouts: the real cutover pushes exactly those
   commits, and only after every check passes.
4. **Check.** It checks that everything still in flint builds against the fetched repos:
   - the structural gate (gates.py and flint check) through the fetched workspace;
   - every flint package's unittests;
   - `flint build` of every app, example and benchmark project (flint.toml);
   - the Python suite.
   It writes `report.json` with each check's result and the failures' output tails.

It is reversible:
- the extracted repos are force-pushed mirrors until the cutover, so pushing them again replaces nothing anybody
  else wrote;
- the cut is one commit on the `cutover` branch of a scratch clone, so nothing touches flint main.

With `--push` it refuses unless the preconditions hold (policy/unregistered-packages.json is empty and
framework/p1-interim is gone; a rehearsal reports them in report.json instead) and unless every check passes; then
it force-pushes the extracted repos. It leaves the `cutover` commit for the coordinator to push to flint main, or
to throw away.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from extract_repo import moving_paths, refresh  # noqa: E402
from workspace import repo_policy  # noqa: E402

PYTHON = sys.executable


def run(command, cwd=None, env=None, check=True):
    return subprocess.run(command, cwd=cwd, env=env, check=check, capture_output=not check, text=True)


def preconditions(flint):
    """What must hold before the real cutover (coordinator's decision 6): every DUB package under framework/ and
    boot/ is registered (policy/unregistered-packages.json empty) and the Phase 1 interim module is gone."""
    problems = []
    allowlist = flint / 'policy' / 'unregistered-packages.json'
    if allowlist.is_file():
        document = json.loads(allowlist.read_text())
        entries = document.get('paths', []) if isinstance(document, dict) else document
        if entries:
            problems.append(f'policy/unregistered-packages.json still lists {len(entries)} packages')
    if (flint / 'framework' / 'p1-interim').exists():
        problems.append('framework/p1-interim still exists')
    return problems


# Coordinator's decision 5: the pre-port Boot libraries and starters take legacy names at the cutover, so Spring
# Boot's flint:boot and its starters' names are free. flint names the new name where an old one is used
# (policy/renamed-packages.json, FLINT-E0301).
LEGACY = {'boot': 'legacy-boot', 'boot-autoconfigure-web': 'legacy-boot-autoconfigure-web',
          'boot-autoconfigure-data': 'legacy-boot-autoconfigure-data', 'boot-actuator': 'legacy-boot-actuator',
          'starter': 'legacy-starter', 'starter-web': 'legacy-starter-web',
          'starter-actuator': 'legacy-starter-actuator', 'starter-data-jdbc': 'legacy-starter-data-jdbc'}
LEGACY_DIRECTORIES = ('boot/boot', 'boot/autoconfigure-', 'boot/actuator', 'starters/')
UNTOUCHED = ('docs/adr/', 'docs/spring/', 'handoff/', 'CHANGELOG.md')


# Once the pre-port flint:boot is flint:legacy-boot, Spring Boot's core takes Spring's artifact name, spring-boot ->
# flint:boot (boot's request; registered until then as flint:boot-core). Likewise spring-boot-actuator ->
# flint:boot-actuator once the pre-port actuator is flint:legacy-boot-actuator (registered until then as
# flint:boot-actuate).
SPRING = {'boot-core': 'boot', 'boot-actuate': 'boot-actuator'}


def legacy_names(flint):
    """The cutover's renames: LEGACY for the packages policy/boot.json still has in their pre-port directories, and
    SPRING for the Spring Boot packages that take the names those free. One map, applied in one pass, so boot-core
    -> boot and boot -> legacy-boot never chain."""
    policy = json.loads((flint / 'policy' / 'boot.json').read_text())
    found = {}
    for group in ('libraries', 'starters'):
        for name, meta in policy.get(group, {}).items():
            if name in LEGACY and meta['directory'].startswith(LEGACY_DIRECTORIES):
                found[name] = LEGACY[name]
    for group in ('libraries', 'starters'):
        for name in policy.get(group, {}):
            if name in SPRING and SPRING[name] in found:
                found[name] = SPRING[name]
    return found


def rename_references(checkout, names):
    """flint:<old> -> flint:<new> in every tracked text file but the historical records; returns the files."""
    pattern = re.compile(r'(?<![\w-])flint:(' + '|'.join(sorted(map(re.escape, names), key=len, reverse=True))
                         + r')(?![\w-])')
    changed = []
    for name in run(['git', 'ls-files'], checkout, check=False).stdout.split():
        path = checkout / name
        if name.startswith(UNTOUCHED) or path.is_symlink() or not path.is_file():
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        new = pattern.sub(lambda match: 'flint:' + names[match[1]], text)
        if new != text and path.name == 'flint.lock':
            new = sort_lock(new)
        if new != text:
            path.write_text(new)
            changed.append(name)
    return changed


def sort_lock(text):
    """A renamed flint.lock in the order flint writes one (project/lock.d): [[package]] tables by name, then the
    [[native]] tables, and every dependencies list sorted."""
    def sorted_list(match):
        items = [item.strip() for item in match[1].split(',') if item.strip()]
        return 'dependencies = [' + ', '.join(sorted(items, key=lambda item: item.strip('"'))) + ']'
    text = re.sub(r'^dependencies = \[(.*)\]$', sorted_list, text, flags=re.M)
    head, *tables = re.split(r'\n(?=\[\[(?:package|native)\]\]\n)', text)
    packages = [table for table in tables if table.startswith('[[package]]')]
    natives = [table for table in tables if table.startswith('[[native]]')]
    packages.sort(key=lambda table: re.search(r'^name = "(.*)"$', table, re.M)[1])
    return '\n'.join([head, *packages, *natives])


def rename_recipes(checkout, flint, names):
    """`name "<old>"` -> `name "<new>"` in each renamed package's dub.sdl in the extracted boot checkout."""
    from workspace import repo_layout
    policy = json.loads((flint / 'policy' / 'boot.json').read_text())
    for group in ('libraries', 'starters'):
        for name, meta in policy.get(group, {}).items():
            if name in names:
                recipe = checkout / repo_layout(meta['directory'], 'boot', flint) / 'dub.sdl'
                text = recipe.read_text()
                recipe.write_text(re.sub(r'^name "' + re.escape(name) + r'"$', f'name "{names[name]}"', text,
                                         count=1, flags=re.M))


def rename_boot_policy(flint, names):
    path = flint / 'policy' / 'boot.json'
    policy = json.loads(path.read_text())
    for group in ('libraries', 'starters'):
        renamed = {}
        for name, meta in policy.get(group, {}).items():
            for key in ('dependencies', 'autoconfiguration'):
                if isinstance(meta.get(key), list):
                    meta[key] = [names.get(item, item) for item in meta[key]]
            renamed[names.get(name, name)] = meta
        policy[group] = renamed
    path.write_text(json.dumps(policy, indent=2) + '\n')
    (flint / 'policy' / 'renamed-packages.json').write_text(json.dumps(
        {'schema': 'flint.renamed/1', 'note': 'Packages the repo split renamed (ADR-030 cutover); flint names the new '
         'name where an old one is used (FLINT-E0301). Written by tools/cutover.py.', 'renamed': names},
        indent=2) + '\n')


def push_mirrors(summary, remote, policy):
    for repo in summary['repos']:
        checkout = Path(summary['workspace']).parent / f'flint-{repo}'
        run(['git', 'push', '--quiet', '--force', remote.format(github=policy[repo]['github']), 'main:main'], checkout)


def cut(flint, extracted, github):
    """Remove the moved paths, keep the remaining subpackages, pin platform.lock and commit."""
    run(['git', 'checkout', '--quiet', '-B', 'cutover'], flint)
    removed = []
    for repo in extracted:
        for path in moving_paths(repo, flint):
            if (flint / path).exists():
                run(['git', 'rm', '-r', '--quiet', path], flint)
                removed.append(path)
    recipe = flint / 'dub.sdl'
    recipe.write_text('\n'.join(line for line in recipe.read_text().splitlines()
                                if not line.startswith('subPackage ')
                                or (flint / re.search(r'"(.*)"', line)[1]).is_dir()) + '\n')
    names = legacy_names(flint)
    if names:
        rename_boot_policy(flint, names)
        rename_references(flint, names)
    lock_path = flint / 'platform.lock'
    lock = json.loads(lock_path.read_text())
    for repo, commit in extracted.items():
        lock['repos'][repo] = {'github': lock['repos'][repo]['github'], 'source': 'github', 'commit': commit}
    lock_path.write_text(json.dumps(lock, indent=2) + '\n')
    run([PYTHON, 'tools/platform_modules.py', '--write'], flint)
    run(['git', 'add', '-A'], flint)
    run(['git', '-c', 'user.name=flint cutover', '-c', 'user.email=cutover@flint.invalid', 'commit', '--quiet', '-m',
         'Cutover: the extracted repos leave the monorepo (ADR-030)\n\n'
         f'Removed {len(removed)} paths that moved: {", ".join(removed)}. platform.lock pins '
         + ', '.join(f'{github[r]}@{c[:12]}' for r, c in sorted(extracted.items())) + '.'], flint)
    return removed


CHECK_TIMEOUT = 3600


def check(name, command, cwd, env, results, timeout=None):
    timeout = timeout or CHECK_TIMEOUT
    try:
        done = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        ok, tail = done.returncode == 0, (done.stdout + done.stderr)[-3000:]
    except subprocess.TimeoutExpired:
        ok, tail = False, f'timed out after {timeout}s'
    results.append({'check': name, 'ok': ok, 'cwd': str(cwd), 'tail': '' if ok else tail})
    print(('PASS ' if ok else 'FAIL ') + name, flush=True)
    return ok


def skeleton(project):
    spec = project / 'flint-spring.json'
    try:
        return spec.is_file() and json.loads(spec.read_text()).get('status') == 'skeleton'
    except ValueError:
        return False


def checks(flint, target):
    env = dict(os.environ)
    tools = (flint / '.tools').resolve()
    host = {'darwin': 'osx', 'win32': 'windows'}.get(sys.platform, 'linux')
    env['PATH'] = os.pathsep.join([str(tools / 'dmd2' / host / 'bin64'), str(tools / 'bin'), env['PATH']])
    # SDL's offscreen driver needs EGL, which macOS lacks; its headless driver there is dummy (ADR-024).
    env.setdefault('SDL_VIDEODRIVER', 'dummy' if sys.platform == 'darwin' else 'offscreen')
    # platform.lock alone resolves the fetched repos; FLINT_WORKSPACE would also redirect the suites' own homes.
    workspace = flint / '.flint' / 'platform' / 'workspace.json'
    flint_bin = str(flint / '.flint' / 'bin' / 'flint')
    results = []
    check('gates.py structural (fetched workspace)', [PYTHON, 'tools/gates.py', '--gate', 'structural', '--workspace',
                                                      str(workspace)], flint, env, results)
    check('flint check structural', [flint_bin, 'check', '--gate', 'structural'], flint, env, results)
    check('platform outputs', [PYTHON, 'tools/platform_modules.py', '--check'], flint, env, results)
    for line in (flint / 'dub.sdl').read_text().splitlines():
        if line.startswith('subPackage '):
            directory = flint / re.search(r'"(.*)"', line)[1]
            name = re.search(r'^name "(.*)"', (directory / 'dub.sdl').read_text(), re.M)[1]
            check(f'dub test :{name}', ['dub', 'test', ':' + name, '--compiler=dmd', '--skip-registry=all'], flint, env,
                  results)
    projects = run(['git', 'ls-files', '*flint.toml'], flint, check=False).stdout.split()
    for manifest in sorted(projects):
        project = (flint / manifest).parent
        # tests/ holds fixtures the suites compile themselves (tests/aot/*), not buildable applications; a Spring
        # side-by-side port whose flint-spring.json says "skeleton" is not written yet (proof-harness).
        if project == flint or manifest.startswith('tests/') or skeleton(project):
            continue
        check(f'flint build {project.relative_to(flint)}', [flint_bin, 'build'], project, env, results)
    for recipe in sorted(flint.glob('examples/*/dub.sdl')):
        check(f'dub build {recipe.parent.relative_to(flint)}', ['dub', 'build', '--root', str(recipe.parent),
                                                                '--compiler=dmd', '--skip-registry=all'],
              flint, env, results)
    # The extracted repos' examples build against the fetched workspace: DUB examples through workspace.py
    # build-example, a browser example through its own build.py against FLINT_ROOT.
    checkouts = json.loads(workspace.read_text())['checkouts']
    for repo, entry in sorted(checkouts.items()):
        if repo == 'flint':
            continue
        for recipe in sorted((workspace.parent / entry['path']).glob('examples/*/dub.sdl')):
            example = recipe.parent
            name = f'{repo} example {example.name}'
            if (example / 'build.py').is_file():
                check(name, [PYTHON, str(example / 'build.py'), '--ldc', 'ldc2', '--output',
                             str(flint / '.flint' / 'cutover' / example.name / 'app.wasm')], flint,
                      dict(env, FLINT_ROOT=str(flint)), results)
            else:
                check(name, [PYTHON, 'tools/workspace.py', 'build-example', str(example), '--workspace',
                             str(workspace), '--output', str(flint / '.flint' / 'cutover' / example.name)],
                      flint, env, results)
    check('python suite', [PYTHON, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'], flint, env, results)
    # Each extracted repo's own suites, run by the flint repo's tooling (coordinator's decision 3).
    for repo, entry in sorted(checkouts.items()):
        suites = workspace.parent / entry['path'] / 'tests'
        if repo != 'flint' and suites.is_dir():
            check(f'{repo} suites', [PYTHON, '-m', 'unittest', 'discover', '-s', str(suites), '-p', 'test_*.py'],
                  flint, dict(env, FLINT_ROOT=str(flint)), results)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--into', type=Path, required=True, help='fresh directory for the clones and the report')
    parser.add_argument('--source', default='git@github.com:flint-projects/flint.git')
    parser.add_argument('--commit', default=None, help='flint commit to cut over (default: origin/main)')
    parser.add_argument('--push', action='store_true', help='the real cutover: force-push the extracted repos')
    parser.add_argument('--remote', default='git@github.com:{github}.git')
    parser.add_argument('--target', default='linux-x86_64-glibc', help='native target of this checkout\'s install')
    parser.add_argument('--skip-checks', action='store_true', help='stop after the fetch')
    parser.add_argument('--check-timeout', type=int, default=3600,
                        help='seconds each check may take (the Python suite needs more on a small Windows VM)')
    arguments = parser.parse_args()
    global CHECK_TIMEOUT
    CHECK_TIMEOUT = arguments.check_timeout
    into = arguments.into.resolve()
    if run(['git', 'filter-repo', '--version'], check=False).returncode != 0:
        raise SystemExit('tools/cutover.py needs git filter-repo on PATH (pip install git-filter-repo, or brew install '
                         'git-filter-repo)')
    # Extract and gate without pushing; the mirrors are pushed only once the preconditions hold.
    summary = refresh(arguments.source, arguments.commit or 'origin/main', into / 'extract', False, arguments.remote)
    extracted = summary['repos']
    source_flint = into / 'extract' / 'flint'
    blocked = preconditions(source_flint)
    if arguments.push and blocked:
        raise SystemExit('refusing the cutover: ' + '; '.join(blocked))
    names = legacy_names(source_flint)
    boot = into / 'extract' / 'flint-boot'
    if names and boot.is_dir():
        rename_recipes(boot, source_flint, names)
        rename_references(boot, names)
        run(['git', 'add', '-A'], boot)
        run(['git', '-c', 'user.name=flint cutover', '-c', 'user.email=cutover@flint.invalid', 'commit', '--quiet',
             '-m', 'Cutover: the pre-port Boot libraries and starters take legacy names (ADR-030)\n\n'
             + ', '.join(f'flint:{old} -> flint:{new}' for old, new in sorted(names.items()))
             + '. Spring Boot takes flint:boot and the starters\' names.'], boot)
        extracted['boot'] = run(['git', 'rev-parse', 'HEAD'], boot, check=False).stdout.strip()
    flint = into / 'flint'
    run(['git', 'clone', '--quiet', '--no-local', str(source_flint), str(flint)])
    run(['git', 'checkout', '--quiet', '--detach', summary['source_commit']], flint)
    policy = repo_policy(flint)['repos']
    github = {repo: policy[repo]['github'] for repo in extracted}
    removed = cut(flint, extracted, github)
    (flint / '.tools').symlink_to((ROOT / '.tools').resolve())
    shutil.copytree(ROOT / '.native' / 'install' / arguments.target, flint / '.native' / 'install' / arguments.target,
                    symlinks=True)
    run([PYTHON, 'tools/install_toolchains.py', '--compiler', 'flint'], flint)
    # Always fetch the local extracted commits; the real cutover pushes exactly those, and only after every check.
    url = str(into / 'extract') + '/flint-{repo}'
    run([PYTHON, 'tools/platform_modules.py', '--fetch', '--native', arguments.target, '--url', url], flint)
    results = [] if arguments.skip_checks else checks(flint, arguments.target)
    if arguments.push:
        if arguments.skip_checks or not all(result['ok'] for result in results):
            raise SystemExit('refusing to push the mirrors: the checks did not all pass (see the results above)')
        push_mirrors(summary, arguments.remote, repo_policy(source_flint)['repos'])
        summary['pushed'] = sorted(extracted)
    report = {'source_commit': summary['source_commit'], 'extracted': extracted, 'pushed': summary['pushed'],
              'preconditions': blocked, 'renamed': names,
              'cutover_commit': run(['git', 'rev-parse', 'HEAD'], flint, check=False).stdout.strip(),
              'removed': removed, 'passed': sum(r['ok'] for r in results),
              'failed': [r['check'] for r in results if not r['ok']], 'results': results}
    (into / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('source_commit', 'extracted', 'cutover_commit', 'preconditions',
                                             'passed', 'failed')},
                     indent=2))
    return 0 if not report['failed'] else 1


if __name__ == '__main__':
    sys.exit(main())
