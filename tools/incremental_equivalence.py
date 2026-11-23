#!/usr/bin/env python3
"""Per-module incremental compilation against clean builds: a seeded sequence of random edits to a Spring port.

    python3 tools/incremental_equivalence.py petclinic-rest --seed 7 --steps 12

Each step makes one random edit to the port's modules, then builds it twice:
- incrementally, with `flint build`, so only the modules the edit can affect recompile;
- from clean, through DUB (`FLINT_DIRECT_BUILD=0 flint build --force`), as one whole compile.
The two executables must define the same global symbols of the port's own modules: its src/ modules, their
generated Flint AOT modules and the AOT registry. Instances of other modules' templates, such as druntime's
hashOf!int, are excluded: each separately compiled object carries its own copy, while one whole compile takes them
from the shared platform object. Both link the same program.
Every compile-time value the edits planted must be current in the incremental executable, and the port's
acceptance suite must pass against it.

The edits are interface edits (a new enum), body edits (a new private function), an added module whose function an
existing module runs at compile time, a body edit to that function, removing it again, and, when the port has
config/, a string-import edit. Every file is restored at the end, whatever happened.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402

def mangled(module):
    """The D mangling prefix of a module's symbols: org.app -> _D3org3app."""
    return '_D' + ''.join(f'{len(part)}{part}' for part in module.split('.'))


class Port:
    def __init__(self, app, work):
        self.app = app
        self.directory = ROOT / spring_bench.app_row(app)['flint']['directory']
        self.work = work
        self.originals = {}
        self.added = []  # (path, module, function, user path, version)

    def remember(self, path):
        if path not in self.originals and path.exists():
            self.originals[path] = path.read_bytes()

    def restore(self):
        for path, _module, _function, _user, _version in self.added:
            path.unlink(missing_ok=True)
        for path, data in self.originals.items():
            path.write_bytes(data)

    def modules(self):
        return sorted(p for p in (self.directory / 'src').rglob('*.d')
                      if not any(p == added[0] for added in self.added))


def module_name(path):
    found = re.search(r'^\s*module\s+([\w.]+)\s*;', path.read_text(encoding='utf-8'), re.M)
    return found.group(1)


def append(port, path, text):
    port.remember(path)
    with path.open('a', encoding='utf-8', newline='\n') as out:
        out.write(text)


def edit(port, rng, step):
    """Apply one random edit; return its description."""
    kinds = ['interface', 'body', 'ctfe-add']
    if port.added:
        kinds += ['ctfe-edit', 'remove']
    if (port.directory / 'config').is_dir():
        kinds.append('config')
    kind = rng.choice(kinds)
    target = rng.choice(port.modules())
    if kind == 'interface':
        append(port, target, f'\nenum flintEqEnum{step} = {step};\n')
    elif kind == 'body':
        append(port, target, f'\nprivate int flintEqBody{step}() {{ return {step}; }}\n')
    elif kind == 'ctfe-add':
        package = module_name(target) if target.name == 'package.d' else module_name(target).rpartition('.')[0]
        module = f'{package}.flinteq{step}' if package else f'flinteq{step}'
        path = target.parent / f'flinteq{step}.d'
        function = f'flintEqValue{step}'
        path.write_text(f'module {module};\n\n@safe:\n\n/// A compile-time value for the equivalence test.\n'
                        f'string {function}() pure {{ return "flint-eq-{step}-0"; }}\n', encoding='utf-8')
        append(port, target, f'\nimport {module} : {function};\nimmutable string flintEqUse{step} = {function}();\n')
        port.added.append((path, module, function, target, 0))
        return f'{kind} {module} used by {module_name(target)}'
    elif kind == 'ctfe-edit':
        index = rng.randrange(len(port.added))
        path, module, function, user, version = port.added[index]
        step_of = function.removeprefix('flintEqValue')
        text = path.read_text(encoding='utf-8')
        path.write_text(text.replace(f'flint-eq-{step_of}-{version}', f'flint-eq-{step_of}-{version + 1}'),
                        encoding='utf-8')
        port.added[index] = (path, module, function, user, version + 1)
        return f'{kind} {module} -> version {version + 1}'
    elif kind == 'remove':
        index = rng.randrange(len(port.added))
        path, module, function, user, _version = port.added.pop(index)
        step_of = function.removeprefix('flintEqValue')
        user.write_text(user.read_text(encoding='utf-8').replace(
            f'\nimport {module} : {function};\nimmutable string flintEqUse{step_of} = {function}();\n', ''),
            encoding='utf-8')
        path.unlink()
        return f'{kind} {module}'
    else:
        config = sorted((port.directory / 'config').glob('*.toml'))[0]
        append(port, config, f'\n# flint-eq {step}\n')
        return f'{kind} {config.name}'
    return f'{kind} {module_name(target)}'


def flint(port, *args, env=None):
    local = ROOT / '.flint' / 'bin' / 'flint'
    command = [str(local) if local.is_file() else 'flint', 'build', *args]
    done = subprocess.run(command, cwd=port.directory, env=env or os.environ, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f'{" ".join(command)} failed:\n{done.stdout[-2000:]}{done.stderr[-3000:]}')


def executable(port, label):
    source = port.directory / '.flint' / 'build' / 'dev' / port.app
    copy = port.work / f'{port.app}-{label}'
    shutil.copyfile(source, copy)
    copy.chmod(0o755)
    return copy


def project_prefixes(port):
    names = [module_name(path) for path in port.modules()] + [added[1] for added in port.added]
    prefixes = {mangled(name) for name in names} | {mangled('flint_aot.' + name) for name in names}
    return tuple(sorted(prefixes | {mangled('flint_aot_registry')}))


def symbols(path, prefixes):
    out = subprocess.run(['nm', '--defined-only', str(path)], capture_output=True, text=True, check=True).stdout
    names = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1].isupper() and parts[2].startswith(prefixes):
            names.add(parts[2])
    return names


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def check(port, incremental, reference, accept):
    problems = []
    prefixes = project_prefixes(port)
    mine, theirs = symbols(incremental, prefixes), symbols(reference, prefixes)
    if not theirs:
        problems.append('no symbol of the port\'s modules was found: the comparison would prove nothing')
    if mine != theirs:
        problems.append(f'defined symbols differ: only incremental {sorted(mine - theirs)[:5]}, '
                        f'only clean {sorted(theirs - mine)[:5]}')
    data = incremental.read_bytes()
    for _path, _module, function, _user, version in port.added:
        step = function.removeprefix('flintEqValue')
        if f'flint-eq-{step}-{version}'.encode() not in data:
            problems.append(f'the incremental executable lacks the current value flint-eq-{step}-{version}')
        if version and f'flint-eq-{step}-{version - 1}'.encode() in data:
            problems.append(f'the incremental executable still holds the stale value flint-eq-{step}-{version - 1}')
    if accept:
        listen = free_port()
        done = subprocess.run([sys.executable, str(ROOT / 'tools' / 'spring_bench.py'), 'accept', port.app, '--start',
                               f'{incremental} --server.port={listen}', '--url', f'http://127.0.0.1:{listen}',
                               '--cwd', str(port.directory)], capture_output=True, text=True)
        if done.returncode != 0:
            problems.append('acceptance failed: ' + done.stdout[-1500:])
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('app')
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--steps', type=int, default=10)
    parser.add_argument('--accept-every', type=int, default=1, help='run the acceptance suite every N steps')
    parser.add_argument('--work', type=Path, default=ROOT / '.flint' / 'incremental-equivalence')
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    port = Port(args.app, args.work)
    rng = random.Random(args.seed)
    results = []
    try:
        flint(port)  # the baseline the first incremental step starts from
        for step in range(1, args.steps + 1):
            description = edit(port, rng, step)
            flint(port)
            incremental = executable(port, 'incremental')
            flint(port, '--force', env=dict(os.environ, FLINT_DIRECT_BUILD='0'))
            reference = executable(port, 'clean')
            problems = check(port, incremental, reference, step % args.accept_every == 0)
            results.append({'step': step, 'edit': description, 'problems': problems})
            print(json.dumps(results[-1]), flush=True)
            if problems:
                raise SystemExit(f'step {step} ({description}): ' + '; '.join(problems))
    finally:
        port.restore()
    print(json.dumps({'app': args.app, 'seed': args.seed, 'steps': args.steps, 'equivalent': True}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
