#!/usr/bin/env python3
"""Install checksum-locked official archives into a project-private directory."""
import argparse,hashlib,json,os,platform,shutil,subprocess,tarfile,urllib.request
from pathlib import Path
from tempfile import TemporaryDirectory
ROOT=Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'policy/toolchains.json').read_text())

def install(name,destination):
    a=LOCK['assets'][name];destination.mkdir(parents=True,exist_ok=True);archive=destination/name
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=a['sha256']:
        with urllib.request.urlopen(a['url'],timeout=90) as response,archive.open('wb') as out:
            while True:
                block=response.read(1048576)
                if not block:break
                out.write(block)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=a['sha256']:raise SystemExit('checksum mismatch: '+name)
    if name=='oha-linux-amd64':
        binary=destination/'oha-1.16.0/oha';binary.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(archive,binary);binary.chmod(0o755)
    elif name.endswith('.7z'):subprocess.run(['7z','x','-y',str(archive),'-o'+str(destination)],check=True)
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


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


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


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',choices=['dmd','ldc','go','oha'],required=True);ap.add_argument('--musl',action='store_true');ap.add_argument('--destination',type=Path,default=ROOT/'.tools')
    ap.add_argument('--dmd-linker', metavar='LINKER', help='Use installed ld.lld or mold for project-local 64-bit DMD links')
    ap.add_argument('--flint-fork', action='store_true',
                    help='Build the Flint DMD/DUB fork (resident toolchain compile server, parallel DUB pipeline, direct linking)')
    ap.add_argument('--no-pgo', action='store_true', help='With --flint-fork, skip profile-guided optimization of DMD')
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
    a.destination=a.destination.resolve()
    osname=platform.system();arch=platform.machine().lower();arch='aarch64' if arch in ['arm64','aarch64'] else 'x86_64' if arch in ['amd64','x86_64'] else arch
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
