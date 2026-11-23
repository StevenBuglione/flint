#!/usr/bin/env python3
"""Paired cold/edit build timing: Flint (dub build) vs Go, with output checks.

Cold: fresh copy of the repository source and a fresh DUB_HOME; Go starts from a
fresh hard-linked copy of a standard-library-only primed GOCACHE.  Edit: the
repository's canonical edit (append a private enum / const) and rebuild in the
same workspace.  Every Flint and Go binary is run and its output checked after
both builds.  Trial order alternates between toolchains and applications.

--native-tree names a checkout whose dub.sdl files carry verified
`// BEGIN FLINT NATIVE` blocks (from `tools/native_build.py --emit-dub`); the
blocks are applied to each fresh copy so the REST application links the same
shared, immutable native install.
"""
import argparse, json, os, shutil, statistics, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GO = str(REPO / '.tools/go/bin')
GO_PRIME = None
EXCLUDE = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native', '.native-sanitized',
           '__pycache__', 'artifacts', 'build'}


NATIVE_TREE = None
# The executable filling the dev profile's DMD role: the forked DMD, or LDC's ldmd2 on macOS (ADR-024).
COMPILER = 'dmd'


def native_blocks():
    import re
    blocks = {}
    if NATIVE_TREE is None:
        return blocks
    for path in NATIVE_TREE.rglob('dub.sdl'):
        if '.dub' in path.parts or '.native' in path.parts:
            continue
        m = re.search(r'\n// BEGIN FLINT NATIVE\n.*?// END FLINT NATIVE\n', path.read_text(), flags=re.S)
        if m:
            blocks[path.relative_to(NATIVE_TREE)] = m.group(0)
    return blocks


BLOCKS = {}


def copy_repo(src, dst):
    import re
    def ignore(d, names):
        return [n for n in names if n in EXCLUDE] if Path(d) == src else [n for n in names if n == '__pycache__']
    shutil.copytree(src, dst, ignore=ignore)
    for rel, block in BLOCKS.items():
        path = dst / rel
        if path.exists():
            text = re.sub(r'\n// BEGIN FLINT NATIVE\n.*?// END FLINT NATIVE\n', '\n', path.read_text(), flags=re.S)
            path.write_text(text.rstrip() + '\n' + block)


def check_cli(binary, cwd, go):
    out = subprocess.run([binary, '-name' if go else '--name', 'Flint'], cwd=cwd, capture_output=True, timeout=10)
    text = out.stdout + out.stderr
    assert out.returncode == 0 and b'Hello, Flint!' in text, text[-400:]


def check_rest(binary, cwd, go):
    import socket, http.client, contextlib
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    p = subprocess.Popen([binary, '--listen', f'127.0.0.1:{port}'], cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 5
        while True:
            try:
                c = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
                c.connect()
                break
            except ConnectionRefusedError:
                assert p.poll() is None and time.monotonic() < deadline
                time.sleep(0.01)
        with contextlib.closing(c):
            for route, body in [('/health', b'ok\n'), ('/json', b'{"message":"hello","n":42}')]:
                c.request('GET', route)
                r = c.getresponse()
                assert r.status == 200 and r.read() == body
    finally:
        p.terminate()
        p.wait(timeout=5)


def run(cmd, cwd, env):
    t = time.perf_counter()
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True)
    dt = time.perf_counter() - t
    if r.returncode:
        raise RuntimeError(f'{cmd} failed in {cwd}:\n{r.stdout.decode()[-2000:]}\n{r.stderr.decode()[-3000:]}')
    return dt


def trial(kind, app, toolbin, scratch, combined, check):
    with tempfile.TemporaryDirectory(dir=scratch) as t:
        root = Path(t)
        env = dict(os.environ)
        for k in ('DFLAGS', 'GOFLAGS', 'DUB_HOME'):
            env.pop(k, None)
        if kind == 'go':
            w = root / 'src'
            shutil.copytree(REPO / f'examples/reference-go-{app}', w)
            shutil.copytree(GO_PRIME, root / 'gocache', copy_function=os.link)
            env.update(PATH=GO + ':' + env['PATH'], GOCACHE=str(root / 'gocache'), GOTOOLCHAIN='local', GOPROXY='off',
                       GOSUMDB='off', GOWORK='off', CGO_ENABLED='0')
            cmd = ['go', 'build', '-trimpath', '-buildvcs=false', '-ldflags=-s -w', '-o', str(root / 'app'), '.']
            cwd, binary, edit = w, root / 'app', w / 'main.go'
            line = '\nconst flintMeasureEdit uint = 1\n'
        else:
            w = root / 'src'
            copy_repo(REPO, w)
            env.update(PATH=toolbin + ':' + env['PATH'], DUB_HOME=str(w / '.dub-home'),
                       DFLAGS='-preview=dip1000 -debug -g -boundscheck=on')
            if sys.platform == 'darwin':
                # DUB treats ldmd2 as DMD, and the fork's pipeline writes ELF-style archives (ADR-024).
                env['FLINT_DUB_PIPELINE'] = '0'
            cmd = ['dub', 'build', '--compiler=' + COMPILER, '--build=plain', '--skip-registry=all'] + (['--combined'] if combined else [])
            cwd, binary = w / f'benchmarks/bench-{app}', w / f'build/bench-{app}'
            edit = cwd / 'source/app.d'
            line = '\nprivate enum uint __flint_measure_edit_1 = 1;\n'
        cold = run(cmd, cwd, env)
        if check:
            (check_cli if app == 'cli' else check_rest)(binary, cwd, kind == 'go')
        with open(edit, 'a') as f:
            f.write(line)
        time.sleep(0.01)
        ed = run(cmd, cwd, env)
        if check:
            (check_cli if app == 'cli' else check_rest)(binary, cwd, kind == 'go')
        return cold, ed


def main():
    global GO, GO_PRIME, NATIVE_TREE, BLOCKS, COMPILER
    ap = argparse.ArgumentParser()
    ap.add_argument('--toolbin', required=True)
    ap.add_argument('--compiler', default='ldmd2' if sys.platform == 'darwin' else 'dmd',
                    help='the dev-profile compiler on --toolbin: dmd, or ldmd2 on macOS (ADR-024)')
    ap.add_argument('--trials', type=int, default=9)
    ap.add_argument('--apps', default='cli,rest')
    ap.add_argument('--combined', action='store_true')
    ap.add_argument('--no-go', action='store_true')
    ap.add_argument('--no-check', action='store_true')
    ap.add_argument('--out')
    ap.add_argument('--go-bin', default=GO)
    ap.add_argument('--go-cache', required=True, help='standard-library-only primed GOCACHE to copy per trial')
    ap.add_argument('--native-tree', type=Path)
    ap.add_argument('--scratch', type=Path, default=Path(tempfile.gettempdir()))
    a = ap.parse_args()
    GO, GO_PRIME, NATIVE_TREE, COMPILER = a.go_bin, a.go_cache, a.native_tree, a.compiler
    BLOCKS = native_blocks()
    scratch = a.scratch
    scratch.mkdir(parents=True, exist_ok=True)
    rows = []
    kinds = ['flint'] + ([] if a.no_go else ['go'])
    for i in range(a.trials):
        for app in a.apps.split(','):
            order = kinds if i % 2 == 0 else kinds[::-1]
            for kind in order:
                cold, ed = trial(kind, app, a.toolbin, scratch, a.combined, not a.no_check)
                rows.append(dict(trial=i, app=app, kind=kind, cold=cold, edit=ed))
                print(json.dumps(rows[-1]), flush=True)
    if a.out:
        Path(a.out).write_text('\n'.join(json.dumps(r) for r in rows) + '\n')
    print('\nmedian ms        cold     edit')
    for app in a.apps.split(','):
        for kind in kinds:
            sel = [r for r in rows if r['app'] == app and r['kind'] == kind]
            print(f'{app:5} {kind:6} {statistics.median(r["cold"] for r in sel)*1000:8.1f} {statistics.median(r["edit"] for r in sel)*1000:8.1f}')
        if not a.no_go:
            f = [r for r in rows if r['app'] == app and r['kind'] == 'flint']
            g = [r for r in rows if r['app'] == app and r['kind'] == 'go']
            print(f'{app:5} ratio  {statistics.median(r["cold"] for r in f)/statistics.median(r["cold"] for r in g):8.3f} '
                  f'{statistics.median(r["edit"] for r in f)/statistics.median(r["edit"] for r in g):8.3f}')


if __name__ == '__main__':
    main()
