#!/usr/bin/env python3
"""Install checksum-locked official archives into a project-private directory."""
import argparse,hashlib,json,os,platform,shutil,subprocess,tarfile,urllib.request
from pathlib import Path
from tempfile import TemporaryDirectory
ROOT=Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'policy/toolchains.json').read_text())

def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            digest.update(block)
    return digest.hexdigest()


def install(name,destination,keep=None):
    """Download, verify and extract a locked asset; `keep` selects archive members by name."""
    a=LOCK['assets'][name];destination.mkdir(parents=True,exist_ok=True);archive=destination/name
    if not archive.exists() or sha256_file(archive)!=a['sha256']:
        with urllib.request.urlopen(a['url'],timeout=90) as response,archive.open('wb') as out:
            while True:
                block=response.read(1048576)
                if not block:break
                out.write(block)
    if sha256_file(archive)!=a['sha256']:raise SystemExit('checksum mismatch: '+name)
    if name=='oha-linux-amd64':
        binary=destination/'oha-1.16.0/oha';binary.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(archive,binary);binary.chmod(0o755)
    elif name.endswith('.7z'):subprocess.run(['7z','x','-y',str(archive),'-o'+str(destination)],check=True)
    elif keep:
        # Stream the archive once; random access would decompress it again per member.
        with tarfile.open(archive,'r|*') as t:
            for member in t:
                if keep(member.name):t.extract(member,destination,filter='data')
    else:
        with tarfile.open(archive) as t:t.extractall(destination,filter='data')
    return destination


def identify_elf_linker(executable):
    path = shutil.which(executable)
    if path is None:
        raise ValueError(f'Cannot find executable {executable!r}')
    # LLVM selects its driver by invocation name. Keep the requested symlink.
    linker = Path(path).absolute()
    version = subprocess.check_output([str(linker), '--version'], text=True).strip()
    name = version.split(' ', 1)[0].lower()
    if name not in ('lld', 'mold'):
        raise ValueError(f'Expected ld.lld or mold, got {version!r}')
    return {'driver': name, 'path': str(linker), 'version': version,
            'sha256': hashlib.sha256(linker.read_bytes()).hexdigest()}


def configure_dmd_linker(bin_dir, linker):
    config = bin_dir / 'dmd.conf'
    original = config.read_text()
    before, marker, after = original.partition('[Environment64]\nDFLAGS=')
    if not marker:
        raise ValueError('Missing 64-bit DFLAGS in the pinned dmd.conf')
    driver_dir = bin_dir / 'flint-linker'
    driver = linker['driver']
    executable = 'ld.' + driver
    driver_dir.mkdir(exist_ok=True)
    with TemporaryDirectory(dir=driver_dir) as temporary:
        tmp = Path(temporary)
        (tmp / executable).symlink_to(linker['path'])
        (tmp / executable).replace(driver_dir / executable)
        # The compiler driver still supplies the CRT and system library paths.
        # The private -B directory selects only the ELF linker.
        line, newline, rest = after.partition('\n')
        # DMD expands %@P% before splitting DFLAGS, including for its own include paths.
        flags = ['"' + flag + '"' if '%@P%' in flag else flag for flag in line.split()]
        flags += ['"-Xcc=-B%@P%/flint-linker/"', '-Xcc=-fuse-ld=' + driver]
        updated = before + marker + ' '.join(flags) + newline + rest
        (tmp / 'dmd.conf').write_text(updated)
        (tmp / 'dmd.conf').replace(config)


FORK_DIR = ROOT / 'toolchain'
DMD_PATCH = FORK_DIR / 'dmd-2.114.0-flint.patch'
DUB_PATCH = FORK_DIR / 'dub-1.43.0-flint.patch'
PRELUDE = FORK_DIR / 'dmd-server-prelude.txt'
# Builds that train the profile-guided DMD build; they exercise the same
# compiler paths as ordinary development builds of this repository.
PGO_APPS = ('benchmarks/bench-cli', 'benchmarks/bench-rest', 'examples/golden-cli', 'examples/golden-rest-service')
PGO_TESTS = ('arena', 'conc', 'config', 'serde', 'validate', 'log', 'cli', 'web', 'http', 'reactor', 'di')


def apply_patch(patch, directory):
    subprocess.run(['patch', '-p1', '--forward', '--quiet', '-d', str(directory), '-i', str(patch)], check=True)


def copy_sources(destination):
    excluded = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native', '.native-sanitized',
                '__pycache__', 'artifacts', 'build'}
    shutil.copytree(ROOT, destination, ignore=lambda d, names: [n for n in names if n in excluded])


def build_fork_dmd(dmd_root, ldc_bin, work, instrument=False, profile=None):
    """Build the patched DMD from the pinned release's bundled compiler source."""
    stage = work / 'dmd'
    if stage.exists():
        shutil.rmtree(stage)
    (stage / 'compiler').mkdir(parents=True)
    shutil.copytree(dmd_root / 'src' / 'dmd', stage / 'compiler' / 'src')
    shutil.copyfile(dmd_root / 'src' / 'VERSION', stage / 'VERSION')
    apply_patch(DMD_PATCH, stage / 'compiler' / 'src')
    env = dict(os.environ, PATH=str(ldc_bin) + os.pathsep + os.environ['PATH'])
    command = [str(ldc_bin / 'ldmd2'), '-run', 'build.d', 'HOST_DMD=ldmd2', 'ENABLE_RELEASE=1', 'ENABLE_LTO=1',
               '-j' + str(min(os.cpu_count() or 2, 16))]
    # DFLAGS is split on spaces, so profile paths stay relative to the build directory.
    if instrument:
        command.append('DFLAGS=-fprofile-instr-generate')
    elif profile:
        for where in (stage / 'compiler', stage / 'compiler' / 'src'):
            shutil.copyfile(profile, where / 'flint-dmd.profdata')
        command.append('DFLAGS=-fprofile-instr-use=flint-dmd.profdata')
    subprocess.run(command + ['dmd'], cwd=stage / 'compiler' / 'src', env=env, check=True, stdout=subprocess.DEVNULL)
    return stage / 'generated' / 'linux' / 'release' / '64' / 'dmd'


def train_profile(bin_dir, instrumented, work, profiles):
    """Run representative repository builds with an instrumented compiler."""
    toolchain = work / 'train-toolchain'
    if toolchain.exists():
        shutil.rmtree(toolchain)
    shutil.copytree(bin_dir.parents[1], toolchain / "dmd2", symlinks=True)
    train_bin = toolchain / "dmd2" / bin_dir.relative_to(bin_dir.parents[1])
    shutil.copyfile(instrumented, train_bin / 'dmd')
    (train_bin / 'dmd').chmod(0o755)
    source = work / 'train-src'
    if source.exists():
        shutil.rmtree(source)
    copy_sources(source)
    env = dict(os.environ, PATH=str(train_bin) + os.pathsep + os.environ['PATH'], DUB_HOME=str(source / '.dub-home'),
               DFLAGS='-preview=dip1000 -debug -g -boundscheck=on', FLINT_DMD_SERVER='0', FLINT_DMD_DIRECT_LINK='0',
               FLINT_DUB_PIPELINE='0', LLVM_PROFILE_FILE=str(profiles / 'dmd-%p.profraw'))
    dub = [str(train_bin / 'dub'), '--skip-registry=all']
    for app in PGO_APPS:
        for extra in ([], ['--combined', '--force']):
            subprocess.run([dub[0], 'build', '--compiler=dmd', '--build=plain', dub[1]] + extra, cwd=source / app, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for package in PGO_TESTS:
        subprocess.run([dub[0], 'test', ':' + package, '--compiler=dmd', dub[1]], cwd=source, env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install_flint_fork(bin_dir, destination, pgo):
    """Replace the pinned DMD and DUB executables with the Flint toolchain fork.

    The upstream executables stay beside them as dmd.upstream and dub.upstream.
    """
    ldc_root = install('ldc2-1.43.0-linux-x86_64.tar.xz', destination) / 'ldc2-1.43.0-linux-x86_64'
    ldc_bin = ldc_root / 'bin'
    dmd_root = bin_dir.parents[1]
    work = destination / 'flint-fork-build'
    work.mkdir(parents=True, exist_ok=True)
    for name in ('dmd', 'dub'):
        upstream = bin_dir / (name + '.upstream')
        if not upstream.exists():
            shutil.copy2(bin_dir / name, upstream)

    if pgo:
        profiles = work / 'profiles'
        if profiles.exists():
            shutil.rmtree(profiles)
        profiles.mkdir()
        instrumented = build_fork_dmd(dmd_root, ldc_bin, work, instrument=True)
        kept = work / 'dmd-instrumented'
        shutil.copyfile(instrumented, kept)
        train_profile(bin_dir, kept, work, profiles)
        raws = sorted(profiles.glob('*.profraw'))
        if not raws:
            raise SystemExit('profile training produced no data')
        merged = work / 'dmd.profdata'
        subprocess.run([str(ldc_bin / 'ldc-profdata'), 'merge', '-o', str(merged)] + [str(r) for r in raws], check=True)
        built = build_fork_dmd(dmd_root, ldc_bin, work, profile=merged)
    else:
        built = build_fork_dmd(dmd_root, ldc_bin, work)

    dub_src = install('dub-1.43.0.tar.gz', work / 'dub-src') / 'dub-1.43.0'
    stage = work / 'dub'
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(dub_src, stage)
    apply_patch(DUB_PATCH, stage)
    env = dict(os.environ, PATH=str(ldc_bin) + os.pathsep + os.environ['PATH'], DMD='ldmd2', GITVER='1.43.0')
    subprocess.run([str(ldc_bin / 'ldmd2'), '-run', 'build.d', '-O3', '-release'], cwd=stage, env=env, check=True,
                   stdout=subprocess.DEVNULL)

    for name, source in (('dmd', built), ('dub', stage / 'bin' / 'dub')):
        with TemporaryDirectory(dir=bin_dir) as temporary:
            target = Path(temporary) / name
            shutil.copyfile(source, target)
            target.chmod(0o755)
            target.replace(bin_dir / name)
    shutil.copyfile(PRELUDE, bin_dir / 'dmd-server-prelude.txt')
    return {'dmd_patch_sha256': sha256_file(DMD_PATCH), 'dub_patch_sha256': sha256_file(DUB_PATCH),
            'prelude_sha256': sha256_file(PRELUDE), 'pgo': pgo,
            'dmd_sha256': sha256_file(bin_dir / 'dmd'), 'dub_sha256': sha256_file(bin_dir / 'dub')}


FLINT_APP = ROOT / 'apps' / 'flint'
FLINT_PROFILES = ('dev', 'release', 'size', 'sanitize')


def sdl_string(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def flint_recipe(manifest, home=ROOT):
    """The DUB recipe flint generates for a project with only Flint core dependencies.

    It must equal flint_tool.build.recipe.renderRecipe byte for byte; tests/test_flint_cli.py compares them.
    """
    project = manifest['project']
    name = project['name']
    artifact = manifest.get('build', {}).get('executable', name)
    kind = project.get('type', 'executable')
    for section in ('dependencies', 'test-dependencies'):
        for dependency, spec in manifest.get(section, {}).items():
            if not dependency.startswith('flint:') or spec != {}:
                raise SystemExit('the bootstrap recipe supports Flint core dependencies only: ' + dependency)
    lines = ['// Generated by flint from flint.toml. Do not edit: flint rewrites it on every build.',
             'name ' + sdl_string(name)]
    if project.get('description'):
        lines.append('description ' + sdl_string(project['description']))
    lines += ['targetName ' + sdl_string(artifact), 'targetType ' + sdl_string(kind),
              'sourcePaths "../../../src"', 'importPaths "../../../src"', 'dflags "-preview=dip1000"']
    lines += ['dependency ' + sdl_string(d) + ' path=' + sdl_string(str(home)) for d in manifest.get('dependencies', {})]
    for profile in FLINT_PROFILES:
        lines += ['configuration ' + sdl_string(profile) + ' {', '    targetPath ' + sdl_string('../../build/' + profile), '}']
    lines += ['configuration "unittest" {', '    targetType "executable"', '    targetName ' + sdl_string(artifact + '-test'),
              '    targetPath "../../build/test"', '    sourcePaths "../../../test"', '    importPaths "../../../test"',
              '    buildOptions "unittests" "debugInfo"'] + (['    dflags "-main"'] if kind == 'library' else [])
    lines += ['    dependency ' + sdl_string(d) + ' path=' + sdl_string(str(home)) for d in manifest.get('test-dependencies', {})]
    return '\n'.join(lines) + '\n}\n'


def bootstrap_flint(toolchain):
    """ADR-018 bootstrap: DUB builds the first flint, which rebuilds itself and verifies its own receipt."""
    import tomllib
    import profiles
    manifest = tomllib.loads((FLINT_APP / 'flint.toml').read_text())
    bin_dir = toolchain / 'dmd2' / 'linux' / 'bin64'
    dmd, dub = bin_dir / 'dmd', bin_dir / 'dub'
    for tool in (dmd, dub):
        if not tool.is_file():
            raise SystemExit('pinned toolchain missing: ' + str(tool) + '; install it with --compiler dmd --flint-fork first')
    recipe_dir = FLINT_APP / '.flint' / 'generated' / 'dub'
    recipe_dir.mkdir(parents=True, exist_ok=True)
    recipe = recipe_dir / 'dub.sdl'
    text = flint_recipe(manifest)
    if not recipe.is_file() or recipe.read_text() != text:
        recipe.write_text(text)
    env = {k: v for k, v in os.environ.items() if k not in ('DFLAGS', 'DUB_HOME')}
    env.update(PATH=str(bin_dir) + os.pathsep + env.get('PATH', ''), DUB_HOME=str(FLINT_APP / '.flint' / 'dub'),
               DFLAGS=' '.join(profiles.dflags('dev')))
    subprocess.run([str(dub), 'build', '--root=' + str(recipe_dir), '--config=dev', '--compiler=' + str(dmd),
                    '--build=plain', '--skip-registry=all'], cwd=FLINT_APP, env=env, check=True)
    artifact = manifest.get('build', {}).get('executable', manifest['project']['name'])
    stage1 = FLINT_APP / '.flint' / 'bootstrap' / artifact
    stage1.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(FLINT_APP / '.flint' / 'build' / 'dev' / artifact, stage1)
    clean = {k: v for k, v in os.environ.items() if k not in ('DFLAGS', 'FLINT_HOME')}
    clean['FLINT_TOOLCHAIN_DIR'] = str(toolchain)
    # Stage 1 rebuilds flint from scratch through flint itself, then the result checks its own receipt.
    subprocess.run([str(stage1), 'build', '--project', str(FLINT_APP), '--force'], env=clean, check=True)
    built = FLINT_APP / '.flint' / 'build' / 'dev' / artifact
    subprocess.run([str(built), 'version', '--verify'], env=clean, check=True, stdout=subprocess.DEVNULL)
    installed = ROOT / '.flint' / 'bin'
    installed.mkdir(parents=True, exist_ok=True)
    for source in (built, built.with_name(artifact + '.receipt.json')):
        shutil.copy2(source, installed / source.name)
    return {'compiler': 'flint', 'version': manifest['project']['version'], 'bin': str(installed),
            'sha256': sha256_file(installed / artifact), 'receipt': str(installed / (artifact + '.receipt.json'))}


LLVM_ARCHIVE = 'LLVM-22.1.8-Linux-X64.tar.xz'
LLVM_ROOT = 'LLVM-22.1.8-Linux-X64'
# The sanitizer lane needs the compiler driver, its resource directory (headers
# and compiler-rt) and the symbolizer. The rest of the 1.9 GB release is unused.
# clang-tidy is the fixed static-analysis profile for embedded C (ADR-021 section 5, ADR-023).
LLVM_MEMBERS = ('bin/clang', 'bin/clang++', 'bin/clang-22', 'bin/clang-tidy', 'bin/llvm-symbolizer', 'lib/clang/22/')


def keep_llvm_member(name):
    prefix = LLVM_ROOT + '/'
    if not name.startswith(prefix):
        return False
    relative = name[len(prefix):]
    return any(relative == item or (item.endswith('/') and relative.startswith(item)) for item in LLVM_MEMBERS)


def install_clang(destination):
    """Install the subset of the pinned official LLVM release the sanitizer lane uses."""
    install(LLVM_ARCHIVE, destination, keep=keep_llvm_member)
    bin_dir = destination / LLVM_ROOT / 'bin'
    version = subprocess.check_output([str(bin_dir / 'clang'), '--version'], text=True)
    if 'clang version ' + LOCK['versions']['clang'] + ' ' not in version:
        raise SystemExit('pinned LLVM archive did not provide clang ' + LOCK['versions']['clang'])
    return bin_dir


MUSL_SYSROOT_RECEIPT = 'flint-musl-sysroot.json'


def apk_members(data):
    """Yield (member, tarfile) for the data members of an Alpine package: three concatenated gzip tars."""
    import gzip, io
    archive = tarfile.open(fileobj=io.BytesIO(gzip.decompress(data)), ignore_zeros=True)
    for member in archive:
        if not member.name.startswith('.'):
            yield member, archive


def musl_sysroot_inputs():
    lock = LOCK['musl_sysroot']
    return {'packages': {p['name'] + '-' + p['version']: p['sha256'] for p in lock['packages']}, 'drop': lock['drop']}


def install_musl_sysroot(destination):
    """Assemble the static musl sysroot from checksum-pinned Alpine packages (no container, no apk)."""
    import posixpath
    lock = LOCK['musl_sysroot']
    output = destination / lock['directory']
    receipt_path = output / MUSL_SYSROOT_RECEIPT
    try:
        if json.loads(receipt_path.read_text()).get('inputs') == musl_sysroot_inputs():
            return json.loads(receipt_path.read_text())
    except (OSError, ValueError):
        pass
    downloads = destination / 'musl-sysroot-downloads'
    downloads.mkdir(parents=True, exist_ok=True)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for package in lock['packages']:
        archive = downloads / (package['name'] + '-' + package['version'] + '.apk')
        if not archive.exists() or sha256_file(archive) != package['sha256']:
            with urllib.request.urlopen(package['url'], timeout=90) as response:
                archive.write_bytes(response.read())
        if sha256_file(archive) != package['sha256']:
            raise SystemExit('checksum mismatch: ' + archive.name)
        for member, tar in apk_members(archive.read_bytes()):
            if any(member.name == d.rstrip('/') or member.name.startswith(d) for d in lock['drop']):
                continue
            if member.issym() and member.linkname.startswith('/'):
                # Keep absolute links inside the sysroot.
                member.linkname = posixpath.relpath(member.linkname.lstrip('/'), posixpath.dirname(member.name))
            tar.extract(member, output, filter='data')
    files = sorted(str(path.relative_to(output)) for path in output.rglob('*') if path.is_file() and not path.is_symlink())
    tree = hashlib.sha256()
    for relative in files:
        tree.update(relative.encode() + b'\0' + sha256_file(output / relative).encode() + b'\n')
    receipt = {'compiler': 'musl-sysroot', 'target': lock['target'], 'triple': lock['triple'], 'sysroot': str(output),
               'inputs': musl_sysroot_inputs(), 'files': len(files), 'tree_sha256': tree.hexdigest()}
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


SANITIZER_RUNTIME = 'ldc-1.43.0-sanitizer-runtime'
SANITIZER_RUNTIME_RECEIPT = 'flint-sanitizer-runtime.json'
# Upstream runtime CMake options. RT_SUPPORT_SANITIZERS adds -d-version=SupportSanitizers:
# GC scanning of ASan fake stacks and fiber-switch notifications. The runtime itself
# stays uninstrumented, exactly like the shipped libraries.
SANITIZER_RUNTIME_CMAKE = ('BUILD_SHARED_LIBS=OFF', 'BUILD_LTO_LIBS=OFF', 'RT_SUPPORT_SANITIZERS=ON')
# Distinct library names: a stale or missing directory fails the link instead of
# silently resolving to the shipped runtime earlier on the search path.
SANITIZER_LIBRARIES = {'druntime-ldc': 'druntime-ldc-sanitizers', 'phobos2-ldc': 'phobos2-ldc-sanitizers'}
SANITIZER_DEFAULTLIB = SANITIZER_LIBRARIES['phobos2-ldc'] + ',' + SANITIZER_LIBRARIES['druntime-ldc']
FAKE_STACK_SCANNER = b'scanStackForASanFakeStack'


def sanitizer_runtime_inputs():
    return {'ldc_archive_sha256': LOCK['assets']['ldc2-1.43.0-linux-x86_64.tar.xz']['sha256'],
            'ldc_source_sha256': LOCK['assets']['ldc-1.43.0-src.tar.gz']['sha256'],
            'cmake': list(SANITIZER_RUNTIME_CMAKE)}


def verified_sanitizer_runtime(output):
    """Return the receipt when the installed runtime matches the lock and its own hashes."""
    try:
        receipt = json.loads((output / SANITIZER_RUNTIME_RECEIPT).read_text())
    except (OSError, ValueError):
        return None
    if receipt.get('inputs') != sanitizer_runtime_inputs():
        return None
    for name in SANITIZER_LIBRARIES.values():
        item = receipt.get('libraries', {}).get(name)
        path = output / 'lib' / ('lib' + name + '.a')
        if not item or not path.is_file() or sha256_file(path) != item['sha256']:
            return None
    return receipt


def build_sanitizer_runtime(destination, build_root=None, jobs=None):
    """Build druntime/Phobos with fake-stack GC scanning into a separate directory.

    The shipped LDC runtime is never modified. Only sanitizer-lane test binaries
    link the result, through -defaultlib with the distinct names above.
    """
    output = destination / SANITIZER_RUNTIME
    receipt = verified_sanitizer_runtime(output)
    if receipt:
        return receipt
    for tool in ('cmake', 'ninja'):
        if shutil.which(tool) is None:
            raise SystemExit(tool + ' is required to build the LDC sanitizer runtime')
    ldc_root = install('ldc2-1.43.0-linux-x86_64.tar.xz', destination) / 'ldc2-1.43.0-linux-x86_64'
    if build_root is not None:
        build_root.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix='flint-ldc-sanitizer-runtime-', dir=build_root) as temporary:
        work = Path(temporary)
        if any(character.isspace() for character in str(work)):
            raise SystemExit('the LDC runtime build rules do not quote paths; use a --build-dir without whitespace')
        # Upstream archive rules pass the compiler path unquoted to the shell.
        compiler = work / 'ldc2-1.43.0-linux-x86_64'
        compiler.symlink_to(ldc_root, target_is_directory=True)
        source = install('ldc-1.43.0-src.tar.gz', work / 'download') / 'ldc-1.43.0-src'
        build = work / 'build'
        command = [str(compiler / 'bin' / 'ldc-build-runtime'), '--ldc=' + str(compiler / 'bin' / 'ldc2'),
                   '--ldcSrcDir=' + str(source), '--buildDir=' + str(build), '--ninja',
                   '-j' + str(jobs or os.cpu_count() or 2), *SANITIZER_RUNTIME_CMAKE]
        subprocess.run(command, check=True)
        built = {name: build / 'lib' / ('lib' + upstream + '.a') for upstream, name in SANITIZER_LIBRARIES.items()}
        if FAKE_STACK_SCANNER not in built['druntime-ldc-sanitizers'].read_bytes():
            raise SystemExit('built druntime lacks ASan fake-stack scanning; RT_SUPPORT_SANITIZERS was not applied')
        destination.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(prefix='.' + SANITIZER_RUNTIME + '-', dir=destination) as staging:
            stage = Path(staging) / SANITIZER_RUNTIME
            (stage / 'lib').mkdir(parents=True)
            libraries = {}
            for name, path in built.items():
                target = stage / 'lib' / ('lib' + name + '.a')
                shutil.copyfile(path, target)
                libraries[name] = {'sha256': sha256_file(target), 'size': target.stat().st_size}
            receipt = {'schema': 1, 'runtime': SANITIZER_RUNTIME, 'inputs': sanitizer_runtime_inputs(),
                       'd_version': 'SupportSanitizers', 'libraries': libraries,
                       'defaultlib': SANITIZER_DEFAULTLIB,
                       'command': [Path(command[0]).name, *command[4:]]}
            (stage / SANITIZER_RUNTIME_RECEIPT).write_text(json.dumps(receipt, indent=2) + '\n')
            if output.exists():
                shutil.rmtree(output)
            stage.rename(output)
    return receipt


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',choices=['dmd','ldc','go','oha','clang','ldc-sanitizer-runtime','musl-sysroot','flint'],required=True);ap.add_argument('--musl',action='store_true');ap.add_argument('--destination',type=Path,default=ROOT/'.tools')
    ap.add_argument('--dmd-linker', metavar='LINKER', help='Use installed ld.lld or mold for project-local 64-bit DMD links')
    ap.add_argument('--flint-fork', action='store_true',
                    help='Build the Flint DMD/DUB fork (resident toolchain compile server, parallel DUB pipeline, direct linking)')
    ap.add_argument('--no-pgo', action='store_true', help='With --flint-fork, skip profile-guided optimization of DMD')
    ap.add_argument('--build-dir', type=Path,
                    help='With --compiler ldc-sanitizer-runtime, parent of the disposable build directory')
    a=ap.parse_args()
    if a.flint_fork and a.compiler != 'dmd':
        ap.error('--flint-fork applies only to --compiler dmd')
    linker = None
    if a.dmd_linker:
        if a.compiler != 'dmd':
            ap.error('--dmd-linker applies only to --compiler dmd')
        try:
            linker = identify_elf_linker(a.dmd_linker)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            ap.error(str(error))
    if a.build_dir and a.compiler != 'ldc-sanitizer-runtime':
        ap.error('--build-dir applies only to --compiler ldc-sanitizer-runtime')
    a.destination=a.destination.resolve()
    if a.compiler=='flint':
        if a.flint_fork or a.dmd_linker or a.musl:ap.error('--compiler flint takes only --destination (the installed toolchain)')
        print(json.dumps(bootstrap_flint(a.destination)))
        return
    osname=platform.system();arch=platform.machine().lower();arch='aarch64' if arch in ['arm64','aarch64'] else 'x86_64' if arch in ['amd64','x86_64'] else arch
    if a.compiler == 'musl-sysroot':
        if (osname,arch)!=('Linux','x86_64'):raise SystemExit('the musl sysroot pin is for Linux x86_64 hosts')
        print(json.dumps(install_musl_sysroot(a.destination)))
        return
    if a.compiler in ('clang','ldc-sanitizer-runtime'):
        if (osname,arch)!=('Linux','x86_64') or a.musl:raise SystemExit('the sanitizer lane toolchain pin is Linux x86_64 glibc')
        if a.compiler=='clang':
            bin_dir=install_clang(a.destination)
            receipt={'compiler':'clang','version':LOCK['versions']['clang'],'bin':str(bin_dir),'sha256':LOCK['assets'][LLVM_ARCHIVE]['sha256']}
        else:
            runtime=build_sanitizer_runtime(a.destination,a.build_dir.resolve() if a.build_dir else None)
            receipt={'compiler':'ldc-sanitizer-runtime','version':LOCK['versions']['ldc'],
                     'lib':str(a.destination/SANITIZER_RUNTIME/'lib'),**runtime}
        print(json.dumps(receipt))
        return
    if a.compiler=='dmd':
        if (osname,arch)!=('Linux','x86_64') or a.musl:raise SystemExit('DMD development pin supports Linux x86_64 glibc; use LDC for this target')
        name='dmd.2.114.0.linux.tar.xz';relative='dmd2/linux/bin64'
    elif a.compiler=='oha':
        if (osname,arch)!=('Linux','x86_64'):raise SystemExit('oha benchmark pin is Linux x86_64')
        name='oha-linux-amd64';relative='oha-1.16.0'
    elif a.compiler=='go':
        if (osname,arch)!=('Linux','x86_64'):raise SystemExit('Go reference benchmark pin is Linux x86_64')
        name='go1.27.4.linux-amd64.tar.gz';relative='go/bin'
    else:
        suffix={'Linux':('alpine' if a.musl else 'linux')+'-'+arch,'Darwin':'osx-arm64','Windows':'windows-x64'}.get(osname)
        if suffix is None:raise SystemExit('unsupported host '+osname)
        if osname=='Darwin' and arch!='aarch64':raise SystemExit('macOS contract is arm64')
        if osname=='Windows' and arch!='x86_64':raise SystemExit('Windows contract is x86_64')
        stem='ldc2-1.43.0-'+suffix;name=stem+('.7z' if osname=='Windows' else '.tar.xz');relative=stem+'/bin'
    install(name,a.destination);binary_path=a.destination/relative
    if not binary_path.is_dir():raise SystemExit('archive layout did not contain '+str(binary_path))
    receipt = {'compiler':a.compiler,'version':LOCK['versions'][a.compiler],'bin':str(binary_path),'sha256':LOCK['assets'][name]['sha256']}
    if linker:
        configure_dmd_linker(binary_path, linker)
        receipt['linker'] = linker
    if a.flint_fork:
        receipt['flint_fork'] = install_flint_fork(binary_path, a.destination, not a.no_pgo)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(binary_path)+'\n')
    print(json.dumps(receipt))
if __name__=='__main__':main()
