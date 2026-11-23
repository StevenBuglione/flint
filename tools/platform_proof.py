#!/usr/bin/env python3
"""Prove an application outside the monorepo builds from the published repos (ADR-023 platform modules).

    python3 tools/platform_proof.py --into /tmp/platform-proof

It makes the Flint home the flint repo becomes at the cutover, then builds and runs a tiny app against it:

1. clones this checkout's commit as the home and removes every path that moves to another repo
   (tools/extract_repo.py moving_paths), keeping only the flint repo's packages in the root dub.sdl;
2. pins each extracted repo in the home's platform.lock at its mirror's current main
   (github.com/flint-projects/flint-<repo>);
3. installs the home's flint CLI, and fetches the pinned checkouts with their native DUB blocks
   (tools/platform_modules.py --fetch --native);
4. outside both, runs `flint new shop`, `flint add web`, takes the starter-web example's sources from the fetched
   flint-boot checkout, builds, starts the app and requests /api/greetings/ada.

The native libraries are copied from this checkout's install (tools/native_build.py), and the toolchain is this
checkout's .tools. The mirrors must have been refreshed from a flint commit whose policy matches this one
(tools/extract_repo.py --all --push).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from extract_repo import moving_paths  # noqa: E402
from workspace import repo_layout, repo_policy  # noqa: E402


def run(command, cwd=None, env=None):
    subprocess.run(command, cwd=cwd, env=env, check=True)


def mirror_heads(home, remote):
    heads = {}
    for repo, meta in sorted(repo_policy(home)['repos'].items()):
        if repo == 'flint' or not moving_paths(repo, home):
            continue
        listed = subprocess.run(['git', 'ls-remote', remote.format(github=meta['github']), 'main'],
                                capture_output=True, text=True, check=True).stdout.split()
        if not listed:
            raise SystemExit(f'{meta["github"]} has no main; refresh the mirrors first')
        heads[repo] = listed[0]
    return heads


def make_home(home, commit, remote):
    run(['git', 'clone', '--quiet', '--no-local', str(ROOT), str(home)])
    run(['git', 'checkout', '--quiet', '--detach', commit], home)
    heads = mirror_heads(home, remote)
    for repo in heads:
        for path in moving_paths(repo, home):
            shutil.rmtree(home / path, ignore_errors=True)
    recipe = home / 'dub.sdl'
    lines = recipe.read_text().splitlines()
    recipe.write_text('\n'.join(line for line in lines if not line.startswith('subPackage ')
                                or (home / re.search(r'"(.*)"', line)[1]).is_dir()) + '\n')
    lock_path = home / 'platform.lock'
    lock = json.loads(lock_path.read_text())
    for repo, head in heads.items():
        lock['repos'][repo] = {'github': lock['repos'][repo]['github'], 'source': 'github', 'commit': head}
    lock_path.write_text(json.dumps(lock, indent=2) + '\n')
    return heads


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--into', type=Path, required=True, help='fresh directory for the home and the app')
    parser.add_argument('--commit', default='HEAD', help='this checkout\'s commit to make the home from')
    parser.add_argument('--target', default='linux-x86_64-glibc', help='native target of this checkout\'s install')
    parser.add_argument('--remote', default='git@github.com:{github}.git', help='mirror URL; {github} is owner/name')
    parser.add_argument('--port', type=int, default=18931)
    arguments = parser.parse_args()
    into = arguments.into.resolve()
    if into.exists():
        raise SystemExit(f'{into} exists; the proof starts from a fresh directory')
    into.mkdir(parents=True)
    home, app = into / 'home', into / 'app'
    heads = make_home(home, arguments.commit, arguments.remote)
    (home / '.tools').symlink_to((ROOT / '.tools').resolve())
    shutil.copytree(ROOT / '.native' / 'install' / arguments.target, home / '.native' / 'install' / arguments.target,
                    symlinks=True)
    run([sys.executable, 'tools/install_toolchains.py', '--compiler', 'flint'], home)
    run([sys.executable, 'tools/platform_modules.py', '--fetch', '--native', arguments.target,
         '--url', arguments.remote], home)
    flint = str(home / '.flint' / 'bin' / 'flint')
    app.mkdir()
    run([flint, 'new', 'shop'], app)
    shop = app / 'shop'
    run([flint, 'add', 'web'], shop)
    boot = home / '.flint' / 'platform' / f'boot-{heads["boot"]}'
    example = boot / repo_layout('starters/web', 'boot', home) / 'example' / 'src' / 'shop'
    for source in example.glob('*.d'):
        shutil.copyfile(source, shop / 'src' / 'shop' / source.name)
    with open(shop / 'config' / 'application.toml', 'a', encoding='utf-8') as config:
        config.write(f'\n[server]\naddress = "127.0.0.1"\nport = {arguments.port}\n')
    run([flint, 'build'], shop)
    server = subprocess.Popen([str(shop / '.flint' / 'build' / 'dev' / 'shop')], cwd=shop, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)
    try:
        body = None
        for _ in range(100):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{arguments.port}/api/greetings/ada', timeout=1) as reply:
                    body = json.loads(reply.read())
                break
            except OSError:
                time.sleep(0.1)
    finally:
        server.terminate()
        server.wait(timeout=10)
    if body != {'text': 'Hello, ada!'}:
        raise SystemExit(f'the app answered {body!r}')
    lock = (shop / 'flint.lock').read_text()
    print(json.dumps({'home': str(home), 'app': str(shop), 'mirrors': heads, 'reply': body,
                      'platforms': sorted(set(re.findall(r'platform = "([^"]+)"', lock)))}, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
