#!/usr/bin/env python3
"""Flint's native resolver (ADR-021 section 4, ADR-023): native packages through an isolated, hidden Conan 2.

Conan runs only with Flint's own home (<flint>/.flint/conan: cache, profiles, settings and remotes), whose single
remote is the checked-in recipe index native/conan-index. Its output goes to a log file, never to the user: every
result, success or failure, is one JSON document on stdout in Flint's words.

    native_resolver.py resolve --target T --require zlib/1.4 [--require ...] [--sanitize] [--work DIR]
        Resolve, build when missing, and report each package's recipe revision, package ID, package revision,
        source and binary hashes, archives and link flags. flint uses this for a project's [native] packages.
    native_resolver.py deploy --target T --profile ci [--sanitize] --prefix DIR [--emit-dub]
        Resolve the workspace's provider closure, merge it into an install prefix with the same receipt layout as
        tools/native_build.py, build the Flint C shims over it and optionally emit the DUB link blocks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from conan_index import PROVIDERS, lock_rows  # noqa: E402

TOOLS = Path(os.environ.get('FLINT_TOOLCHAIN_DIR', ROOT / '.tools'))
CONAN_VERSION = json.loads((ROOT / 'policy' / 'toolchains.json').read_text())['versions']['conan']
CLANG = TOOLS / 'LLVM-22.1.8-Linux-X64' / 'bin' / 'clang'
REMOTE = 'flint'


class Failure(Exception):
    def __init__(self, code, message, fix):
        super().__init__(message)
        self.code, self.message, self.fix = code, message, fix


def conan_binary():
    binary = TOOLS / ('conan-' + CONAN_VERSION) / 'bin' / 'conan'
    if not binary.is_file():
        raise Failure('FLINT-E0818', 'the native package engine is not installed (' + str(binary) + ')',
                      'flint toolchain install')
    return binary


def home():
    return ROOT / '.flint' / 'conan'


def environment(log):
    env = {k: v for k, v in os.environ.items() if not k.startswith('CONAN_')}
    env.update(CONAN_HOME=str(home()), FLINT_HOME=str(ROOT), NO_COLOR='1', CONAN_LOGIN_USERNAME='',
               PYTHONDONTWRITEBYTECODE='1')
    rust = TOOLS / 'rust'
    if (rust / 'flint-rust-install.json').is_file():
        from install_rust import environment as rust_environment
        version = json.loads((ROOT / 'policy' / 'toolchains.json').read_text())['versions']['rust']
        env.update({k: v for k, v in rust_environment(rust, version).items() if k in ('PATH', 'RUSTUP_HOME',
                                                                                       'CARGO_HOME', 'RUSTUP_TOOLCHAIN')})
    return env


def conan(arguments, log, env, check=True):
    with log.open('a') as output:
        output.write('$ conan ' + ' '.join(arguments) + '\n')
        result = subprocess.run([str(conan_binary()), *arguments], env=env, capture_output=True, text=True)
        output.write(result.stdout + result.stderr + '\n')
    if check and result.returncode:
        raise ConanError(result.stdout + result.stderr)
    return result


class ConanError(Exception):
    pass


SETTINGS_USER = '''# Written by Flint's native resolver. Linux targets distinguish the C library.
os:
  Linux:
    libc: [null, glibc, musl]
'''

GLOBAL_CONF = '''# Written by Flint's native resolver: no prompts, no telemetry-like update checks, no other remotes.
core:non_interactive=True
core.sources:download_cache={cache}
core.download:parallel=4
'''


def prepare(log, env):
    """Make the isolated Conan home: settings, configuration and the index as its only remote."""
    root = home()
    root.mkdir(parents=True, exist_ok=True)
    (root / 'settings_user.yml').write_text(SETTINGS_USER)
    (root / 'global.conf').write_text(GLOBAL_CONF.format(cache=root / 'sources'))
    remotes = json.loads(conan(['remote', 'list', '--format=json'], log, env).stdout or '[]')
    for remote in remotes:
        if remote['name'] != REMOTE or Path(remote['url']) != ROOT / 'native' / 'conan-index':
            conan(['remote', 'remove', remote['name']], log, env)
    if not any(r['name'] == REMOTE and Path(r['url']) == ROOT / 'native' / 'conan-index' for r in remotes):
        conan(['remote', 'add', REMOTE, str(ROOT / 'native' / 'conan-index'), '--type=local-recipes-index'], log, env)


def gcc_major():
    try:
        return subprocess.run(['gcc', '-dumpversion'], capture_output=True, text=True).stdout.strip().split('.')[0]
    except OSError:
        return '13'


SYSROOT = TOOLS / 'musl-sysroot-alpine-3.22-x86_64'
MUSL_TOOLCHAIN = '''# Written by Flint's native resolver: CMake providers for linux-x86_64-musl, cross-built by the pinned clang
# against the pinned musl sysroot (ADR-023).
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER "{clang}")
set(CMAKE_C_COMPILER_TARGET x86_64-alpine-linux-musl)
set(CMAKE_CXX_COMPILER "{clang}++")
set(CMAKE_CXX_COMPILER_TARGET x86_64-alpine-linux-musl)
set(CMAKE_SYSROOT "{sysroot}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
'''


def cross_toolchain(target):
    """The CMake toolchain file of a cross target, or None when the host builds it natively."""
    import native_build
    if target == native_build.host_target():
        return None
    if target != 'linux-x86_64-musl' or native_build.host_target() != 'linux-x86_64-glibc':
        raise Failure('FLINT-E0817', 'native packages for ' + target + ' build on their own runners',
                      'build on a ' + target + ' host')
    if not (SYSROOT / 'flint-musl-sysroot.json').is_file():
        raise Failure('FLINT-E0817', 'the linux-x86_64-musl toolchain is not installed', 'flint toolchain install --musl')
    path = home() / 'toolchains' / 'linux-x86_64-musl.cmake'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(MUSL_TOOLCHAIN.format(clang=CLANG, sysroot=SYSROOT))
    return path


def profile(target, sanitize):
    os_name, arch, libc = target.split('-')
    if os_name != 'linux':
        raise Failure('FLINT-E0817', 'native packages for ' + target + ' build on their own runners',
                      'build on a ' + target + ' host')
    compiler = ['compiler=clang', 'compiler.version=22'] if sanitize else ['compiler=gcc',
                                                                          'compiler.version=' + gcc_major()]
    toolchain = cross_toolchain(target)
    if toolchain:
        compiler = ['compiler=clang', 'compiler.version=22']
    lines = ['[settings]', 'os=Linux', 'os.libc=' + libc, 'arch=' + ('armv8' if arch == 'aarch64' else arch),
             *compiler, 'compiler.libcxx=libstdc++11', 'build_type=Release', '[conf]',
             'user.flint:clang=' + str(CLANG)]
    if toolchain:
        lines.append('user.flint:cmake_toolchain=' + str(toolchain))
    if sanitize:
        lines += ['[options]', '*:sanitize=address,undefined']
    return '\n'.join(lines) + '\n'


def tree_hash(directory):
    records = []
    for path in sorted(p for p in Path(directory).rglob('*') if p.is_file()):
        relative = path.relative_to(directory).as_posix()
        if relative in ('conaninfo.txt', 'conanmanifest.txt'):
            continue
        records.append(relative + '\0' + hashlib.sha256(path.read_bytes()).hexdigest() + '\n')
    return hashlib.sha256(''.join(records).encode()).hexdigest()


def install(target, requires, sanitize, work, options=()):
    """conan install the requirements; return the resolved packages in dependency order."""
    work.mkdir(parents=True, exist_ok=True)
    log = work / 'conan.log'
    log.write_text('')
    env = environment(log)
    prepare(log, env)
    rows = lock_rows()
    for reference in requires:
        name, _, version = reference.partition('/')
        if name not in PROVIDERS or rows[name]['version'] != version:
            listed = rows[name]['version'] if name in PROVIDERS else None
            raise Failure('FLINT-E0318', 'native package ' + reference + ' is not in Flint\'s recipe index',
                          ('the index has ' + name + '/' + listed) if listed else
                          'the index has: ' + ', '.join(sorted(n + '/' + rows[n]['version'] for n in PROVIDERS)))
    (work / 'conanfile.txt').write_text('[requires]\n' + ''.join(r + '\n' for r in requires)
                                        + ('[options]\n' + ''.join(o + '\n' for o in options) if options else ''))
    (work / 'host.profile').write_text(profile(target, sanitize))
    import native_build
    build_profile = profile(native_build.host_target(), False)
    (work / 'build.profile').write_text(build_profile)
    try:
        result = conan(['install', str(work), '-pr:h', str(work / 'host.profile'), '-pr:b',
                        str(work / 'build.profile'), '--build=missing', '--remote', REMOTE, '--lockfile-out',
                        str(work / 'conan.lock'), '--format=json', '--output-folder', str(work / 'out')], log, env)
    except ConanError as error:
        raise translate(str(error), log) from None
    return packages(json.loads(result.stdout), log)


def translate(text, log):
    """A Conan failure in Flint's words; the raw output stays in the log."""
    for line in text.splitlines():
        if ' failed to build: ' in line:
            name = line.split(' failed to build: ')[0].split()[-1].strip(':')
            return Failure('FLINT-E0819', 'native package ' + name + ' failed to build', 'the build log is '
                           + str(log) + '; the provider\'s own output is in its native-build.log there')
        if 'does not support' in line and 'ConanInvalidConfiguration' in text:
            return Failure('FLINT-E0817', line.split('ERROR:')[-1].strip(), 'choose a target the provider supports')
    return Failure('FLINT-E0819', 'the native resolver failed', 'the full log is ' + str(log))


def packages(graph, log):
    nodes = graph['graph']['nodes']
    found = []
    for key in sorted(nodes, key=int):
        node = nodes[key]
        if key == '0' or not node.get('ref'):
            continue
        folder = Path(node['package_folder'])
        document = json.loads((folder / 'flint-native-package.json').read_text())
        reference = node['ref']
        name_version, _, rrev = reference.partition('#')
        name, _, version = name_version.partition('/')
        found.append({'name': name, 'version': version, 'recipe_revision': rrev or node.get('rrev', ''),
                      'package_id': node['package_id'], 'package_revision': node.get('prev') or '',
                      'source_sha256': lock_rows()[name]['archive_sha256'], 'binary_sha256': tree_hash(folder),
                      'license': lock_rows()[name]['license_selected'], 'package_folder': str(folder),
                      'dependencies': [nodes[d]['ref'].split('/')[0] for d in node.get('dependencies', {})
                                       if nodes[d].get('ref')],
                      'record': document['record']})
    return order(found)


def order(found):
    by_name = {p['name']: p for p in found}
    result, seen = [], set()

    def visit(name):
        if name in seen:
            return
        seen.add(name)
        for dependency in by_name[name]['dependencies']:
            visit(dependency)
        result.append(by_name[name])
    for name in sorted(by_name):
        visit(name)
    return result


def link_flags(resolved):
    """Static archives, dependents before dependencies, then each provider's recorded system link flags."""
    archives, extra = [], []
    for package in reversed(resolved):
        folder = Path(package['package_folder'])
        for item in package['record'].get('archives', []):
            archives.append(str(folder / item['path']))
    for package in reversed(resolved):
        metadata = package['record'].get('system_link_metadata')
        for flag in (metadata or {}).get('flags', []):
            if flag not in extra:
                extra.append('-lpthread' if flag == '-pthread' else flag)
    return archives + extra + ['-lpthread', '-ldl', '-lm']


def command_resolve(args):
    work = Path(args.work) if args.work else ROOT / '.flint' / 'native' / (args.target + ('-sanitize' if args.sanitize else ''))
    options = ['curl/*:smtp=' + ('True' if args.curl_smtp else 'False')] if any(
        r.startswith('curl/') for r in args.require) else []
    resolved = install(args.target, args.require, args.sanitize, work, options)
    includes = [str(Path(p['package_folder']) / 'include') for p in resolved]
    return {'ok': True, 'target': args.target, 'sanitize': args.sanitize, 'conan_version': CONAN_VERSION,
            'log': str(work / 'conan.log'), 'packages': [{k: v for k, v in p.items() if k != 'record'}
                                                        for p in resolved],
            'include_dirs': includes, 'link_flags': link_flags(resolved)}


def closure(profile_name, target):
    import native_build
    names = list(native_build.PROFILES[profile_name])
    if profile_name == 'ci':
        names.append('wasmtime')
    if target.startswith('linux'):
        names.append('liburing')
    rows = lock_rows()
    return native_build.dependency_order(names, rows, False)


def command_deploy(args):
    names = closure(args.profile, args.target)
    rows = lock_rows()
    work = ROOT / '.flint' / 'native' / ('workspace-' + args.target + ('-sanitize' if args.sanitize else ''))
    requires = [n + '/' + rows[n]['version'] for n in names]
    resolved = install(args.target, requires, args.sanitize, work, ['curl/*:smtp=True'])
    prefix = Path(args.prefix).resolve()
    if prefix.exists():
        shutil.rmtree(prefix)
    prefix.mkdir(parents=True)
    receipt = {'schema': 1, 'target': args.target, 'libraries': {}, 'provider': {
        'engine': 'conan', 'conan_version': CONAN_VERSION, 'recipe_index': 'native/conan-index',
        'packages': {p['name']: {k: p[k] for k in ('version', 'recipe_revision', 'package_id', 'package_revision',
                                                    'source_sha256', 'binary_sha256')} for p in resolved}}}
    for package in resolved:
        folder = Path(package['package_folder'])
        shutil.copytree(folder, prefix, symlinks=True, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('conaninfo.txt', 'conanmanifest.txt', 'flint-native-package.json'))
        record = json.loads(json.dumps(package['record']))
        for item in record.get('archives', []):
            item['path'] = str(prefix / item['path'])
        metadata = record.get('system_link_metadata')
        if metadata and metadata.get('path'):
            metadata['path'] = str(prefix / metadata['path'])
        receipt['libraries'][package['name']] = record
    (prefix / 'flint-native-install.json').write_text(json.dumps(receipt, indent=2) + '\n')
    shims = [sys.executable, str(ROOT / 'tools' / 'native_build.py'), '--shims-only', '--profile', args.profile,
             '--target', args.target, '--phase', 'build', '--prefix', str(prefix), '--work-dir', str(work / 'shims')]
    if args.sanitize:
        shims += ['--sanitize', 'address,undefined', '--cc', str(CLANG), '--cxx', str(CLANG) + '++']
    if args.emit_dub:
        shims.append('--emit-dub')
    log = work / 'conan.log'
    with log.open('a') as output:
        result = subprocess.run(shims, capture_output=True, text=True, env=environment(log))
        output.write('$ ' + ' '.join(shims) + '\n' + result.stdout + result.stderr)
    if result.returncode:
        raise Failure('FLINT-E0819', 'the Flint C shims failed to build over the deployed providers',
                      'the log is ' + str(log))
    return {'ok': True, 'target': args.target, 'prefix': str(prefix), 'log': str(log), 'libraries': names,
            'packages': [{k: v for k, v in p.items() if k not in ('record',)} for p in resolved]}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    resolve = sub.add_parser('resolve')
    resolve.add_argument('--target', required=True)
    resolve.add_argument('--require', action='append', default=[])
    resolve.add_argument('--sanitize', action='store_true')
    resolve.add_argument('--curl-smtp', action='store_true')
    resolve.add_argument('--work')
    deploy = sub.add_parser('deploy')
    deploy.add_argument('--target', required=True)
    deploy.add_argument('--profile', default='ci')
    deploy.add_argument('--sanitize', action='store_true')
    deploy.add_argument('--prefix', required=True)
    deploy.add_argument('--emit-dub', action='store_true')
    args = parser.parse_args()
    try:
        document = command_resolve(args) if args.command == 'resolve' else command_deploy(args)
    except Failure as failure:
        document = {'ok': False, 'error': {'code': failure.code, 'message': failure.message, 'fix': failure.fix}}
    print(json.dumps(document, indent=2))
    return 0 if document['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
