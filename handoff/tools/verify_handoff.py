#!/usr/bin/env python3
"""Validate handoff structure and real compiler contracts, never pretend runtime exists.

Default invocation performs structural checks and uses installed compilers when found.
Explicit --dmd/--ldc paths reproduce the shipped compiler checks. A report marks every
unavailable runtime/tool check as not_run; structural-only success is labelled as such.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key: ' + str(key))
        result[key] = value
    return result


def load_json(path):
    def invalid_constant(value):
        raise ValueError('nonfinite JSON constant: ' + value)
    return json.loads(path.read_text(encoding='utf-8'),
                      object_pairs_hook=no_duplicate_keys, parse_constant=invalid_constant)


def yaml_documents(path):
    try:
        import yaml
    except ImportError as exc:
        raise ValueError('PyYAML is required: python3 -m pip install -r tools/requirements.txt') from exc
    class UniqueLoader(yaml.BaseLoader):
        pass
    def mapping(loader, node, deep=False):
        result = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in result:
                raise ValueError('duplicate YAML key in ' + str(path) + ': ' + str(key))
            result[key] = loader.construct_object(value_node, deep=deep)
        return result
    UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    return list(yaml.load_all(path.read_text(encoding='utf-8'), Loader=UniqueLoader))


SDL_TOKEN = re.compile(r'(?P<space>[ \t\r]+)|(?P<newline>\n)|(?P<comment>//[^\n]*|/\*.*?\*/)|'
                       r'(?P<string>"(?:\\.|[^"\\])*")|(?P<number>-?[0-9]+(?:\.[0-9]+)?)|'
                       r'(?P<name>[A-Za-z_][A-Za-z_0-9:.-]*)|(?P<punct>[{}=;])', re.S)


def parse_sdl(text):
    """Parse the documented canonical SDL subset used by this handoff.

    An actual DUB describe pass additionally checks semantics when DUB is available.
    Unknown token syntax is rejected, never silently skipped.
    """
    tokens, offset = [], 0
    while offset < len(text):
        match = SDL_TOKEN.match(text, offset)
        if not match:
            raise ValueError('noncanonical SDL token at byte ' + str(offset))
        offset = match.end()
        kind, value = match.lastgroup, match.group()
        if kind in ('space', 'comment'):
            continue
        if kind == 'string':
            value = json.loads(value)
        tokens.append((kind, value))
    index = 0
    def sequence(nested=False):
        nonlocal index
        nodes = []
        while index < len(tokens):
            kind, value = tokens[index]
            if kind == 'newline' or value == ';':
                index += 1
                continue
            if value == '}':
                if not nested:
                    raise ValueError('unmatched SDL closing brace')
                index += 1
                return nodes
            if kind != 'name':
                raise ValueError('SDL node must start with an identifier')
            node = {'name': value, 'values': [], 'attributes': {}, 'children': []}
            index += 1
            while index < len(tokens):
                kind, value = tokens[index]
                if kind == 'newline' or value in (';', '}'):
                    break
                if value == '{':
                    index += 1
                    node['children'] = sequence(True)
                    break
                if index + 1 < len(tokens) and tokens[index + 1][1] == '=':
                    if kind != 'name' or value in node['attributes']:
                        raise ValueError('invalid/duplicate SDL attribute')
                    key = value
                    index += 2
                    if index >= len(tokens) or tokens[index][0] not in ('string', 'name', 'number'):
                        raise ValueError('missing SDL attribute value')
                    node['attributes'][key] = tokens[index][1]
                    index += 1
                elif kind in ('string', 'number') or (kind == 'name' and value in ('true', 'false', 'null')):
                    node['values'].append(value)
                    index += 1
                else:
                    raise ValueError('invalid SDL value: ' + value)
            nodes.append(node)
        if nested:
            raise ValueError('unclosed SDL block')
        return nodes
    return sequence()


def markdown_links(path, root=ROOT):
    text = re.sub(r'(?ms)^```[^\n]*\n.*?^```\s*$', '', path.read_text(encoding='utf-8'))
    failures = []
    for match in re.finditer(r'\[[^\]\n]*\]\(([^)\n]+)\)', text):
        target = match.group(1).strip().strip('<>')
        # Titles are unnecessary for archive links; this handles the standard quoted form.
        target = re.sub(r'\s+"[^"]*"$', '', target)
        url = urlsplit(target)
        if url.scheme or target.startswith('//') or not url.path:
            continue
        local = (path.parent / unquote(url.path)).resolve()
        if not local.is_relative_to(root.resolve()):
            failures.append('link leaves archive: ' + target)
        elif not local.exists():
            failures.append('missing link target: ' + target)
    return failures


def d_blocks(path):
    for match in re.finditer(r'(?ms)^```d\s*\n(.*?)^```\s*$', path.read_text(encoding='utf-8')):
        code = match.group(1)
        if re.search(r'(?m)^\s*module\s+[A-Za-z_][\w.]*\s*;', code):
            yield code


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd=ROOT, timeout=90, env=None):
    completed = subprocess.run([str(x) for x in command], cwd=cwd, text=True,
                               capture_output=True, timeout=timeout, env=env)
    return {'command': [str(x) for x in command], 'returncode': completed.returncode,
            'stdout': completed.stdout[-20000:], 'stderr': completed.stderr[-20000:]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dmd', default=shutil.which('dmd'))
    parser.add_argument('--ldc', default=shutil.which('ldc2'))
    parser.add_argument('--dub', default=shutil.which('dub'))
    parser.add_argument('--go', default=None, help='Also execute the stdlib-only Go reference tests')
    parser.add_argument('--node', default=shutil.which('node'))
    parser.add_argument('--dfmt', default=shutil.which('dfmt'))
    parser.add_argument('--dscanner', default=shutil.which('dscanner'))
    parser.add_argument('--report', type=Path, default=ROOT / 'verification/handoff-validation.json')
    args = parser.parse_args(argv)
    report = {'schema': 1, 'checked_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'scope': 'handoff integrity, API typechecking and explicitly identified standalone probes',
              'not_claimed': ['37 package runtime implementations', 'production performance or size targets',
                              'native cross-platform runtime support', 'FFI behavior without built libraries'],
              'checks': []}
    def check(name, operation):
        try:
            detail = operation()
            report['checks'].append({'name': name, 'status': 'pass', 'detail': detail})
        except Exception as exc:
            report['checks'].append({'name': name, 'status': 'fail', 'detail': str(exc)})
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    def successful(command, cwd=ROOT, timeout=90, env=None):
        result = run(command, cwd, timeout, env)
        require(result['returncode'] == 0, json.dumps(result))
        return result
    def structure():
        required = ['README.md', 'AGENTS.md', 'MILESTONES_EXECUTION_PLAN.md',
                    'docs/RESEARCH_REPORT.md', 'docs/AGENT_D_DIALECT.md',
                    'docs/ARCHITECTURE_DAG.md', 'docs/C_FFI_PINNING_MATRIX.md',
                    'docs/CI_PERFORMANCE_BUDGETS.md', 'scaffold/dub.sdl',
                    'scaffold/.editorconfig', 'scaffold/dscanner.ini',
                    'scaffold/tools/flint.py', 'scaffold/tools/gates.py',
                    'scaffold/policy/packages.json', 'scaffold/policy/budgets.json',
                    'scaffold/tools/measure_builds.py', 'scaffold/tools/collect_evidence.py',
                    'scaffold/tools/load_bench.py', 'scaffold/tools/native_build.py',
                    'verification/VERIFICATION_REPORT.md']
        missing = [p for p in required if not (ROOT / p).is_file()]
        require(not missing, 'missing required files: ' + ', '.join(missing))
        packages = load_json(ROOT / 'scaffold/policy/packages.json')['packages']
        require(len(packages) == 37, 'exactly 37 packages required')
        for name, meta in packages.items():
            require((ROOT / f"specs/tier-{meta['tier']}/{name}.md").is_file(), 'missing spec: ' + name)
            require((ROOT / f'scaffold/packages/{name}/dub.sdl').is_file(), 'missing recipe: ' + name)
            base = ROOT / 'contracts/source' / meta['module'].replace('.', '/')
            require(base.with_suffix('.d').is_file() or (base / 'package.d').is_file(), 'missing API contract: ' + name)
        for number in range(1, 7):
            require((ROOT / f'task-prompts/milestone-{number:02}.md').is_file(), 'missing milestone prompt')
        adrs = list((ROOT / 'docs/adrs').glob('*.md'))
        require(len(adrs) >= 12, 'at least 12 numbered ADRs required')
        for name in ['golden-cli', 'golden-tui', 'golden-rest-service', 'golden-wasm-app']:
            require(any((ROOT / 'templates' / name).rglob('*.d')), 'missing golden D source: ' + name)
        require(any((ROOT / 'templates/reference-go-rest').rglob('*.go')), 'missing Go reference')
        require(any((ROOT / 'scaffold/.github/workflows').glob('*.yml')) or
                any((ROOT / 'scaffold/.github/workflows').glob('*.yaml')), 'missing CI workflows')
        return {'packages': len(packages), 'adrs': len(adrs)}
    check('required structure', structure)
    check('JSON syntax and duplicate keys', lambda: {'files': len([load_json(p) for p in ROOT.rglob('*.json') if '.dub' not in p.parts])})
    def yaml_check():
        files = list(ROOT.rglob('*.yml')) + list(ROOT.rglob('*.yaml'))
        require(files, 'no YAML workflows found')
        for path in files:
            docs = yaml_documents(path)
            require(docs, 'empty YAML: ' + str(path))
            if '.github' in path.parts and 'workflows' in path.parts:
                require(isinstance(docs[0], dict) and 'jobs' in docs[0] and 'on' in docs[0],
                        'workflow requires on/jobs: ' + str(path))
        return {'files': len(files)}
    check('YAML syntax, duplicate keys and workflow shape', yaml_check)
    def sdl_check():
        files = list(ROOT.rglob('dub.sdl'))
        for path in files:
            parse_sdl(path.read_text(encoding='utf-8'))
        return {'files': len(files), 'scope': 'canonical SDL syntax; actual DUB check is separate'}
    check('SDL canonical syntax', sdl_check)
    def link_check():
        files = list(ROOT.rglob('*.md'))
        errors = []
        for path in files:
            errors.extend(str(path.relative_to(ROOT)) + ': ' + x for x in markdown_links(path))
        require(not errors, '\n'.join(errors))
        return {'markdown_files': len(files)}
    check('internal Markdown links', link_check)
    def python_check():
        files = list(ROOT.rglob('*.py'))
        for path in files:
            compile(path.read_text(encoding='utf-8'), str(path), 'exec')
        return {'files': len(files)}
    check('Python syntax', python_check)
    check('dependency and structural guardrails', lambda: successful([sys.executable, 'tools/gates.py', '--gate', 'structural'], ROOT / 'scaffold'))
    check('validator negative fixtures', lambda: successful([sys.executable, 'tools/test_verify_handoff.py']))
    check('scaffold tooling unit tests', lambda: successful(
        [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'],
        ROOT / 'scaffold', timeout=180))
    if args.dfmt and args.dscanner:
        check('golden, benchmark and BetterC source quality', lambda: successful(
            [sys.executable, 'tools/quality.py', '--dfmt', args.dfmt, '--dscanner', args.dscanner,
             '--path', str(ROOT / 'templates'), '--path', str(ROOT / 'scaffold/benchmarks'),
             '--path', str(ROOT / 'scaffold/packages')], ROOT / 'scaffold'))
    else:
        report['checks'].append({'name': 'golden, benchmark and BetterC source quality',
                                'status': 'not_run', 'detail': 'provide both --dfmt and --dscanner'})
    if (ROOT / 'scaffold/tools/test_guards.py').exists():
        guard_env = os.environ.copy()
        if args.dmd:
            guard_env['DMD'] = args.dmd
        check('guardrail negative fixtures', lambda: successful([sys.executable, 'tools/test_guards.py'], ROOT / 'scaffold', env=guard_env))
    if (ROOT / 'scaffold/tools/test_evidence.py').exists():
        evidence_env = os.environ.copy()
        for key, value in [('DMD', args.dmd), ('LDC', args.ldc), ('DUB', args.dub)]:
            if value:
                evidence_env[key] = value
        check('measurement and evidence adversarial tests', lambda: successful(
            [sys.executable, 'tools/test_evidence.py'], ROOT / 'scaffold', timeout=180, env=evidence_env))
    compilers = [(name, value) for name, value in [('dmd', args.dmd), ('ldc2', args.ldc)] if value]
    for name, path in [('dmd', args.dmd), ('ldc2', args.ldc)]:
        if not path:
            report['checks'].append({'name': name + ' compiler checks', 'status': 'not_run', 'detail': 'compiler not supplied or installed'})
    contract_files = sorted((ROOT / 'contracts/source').rglob('*.d'))
    with tempfile.TemporaryDirectory(prefix='flint-handoff-check-') as tmpstr:
        tmp = Path(tmpstr)
        for name, compiler in compilers:
            check(name + ' version', lambda c=compiler: successful([c, '--version']))
            flags = [compiler, '-preview=dip1000', '-o-', '-I' + str(ROOT / 'contracts/source')]
            check(name + ' all contract declarations', lambda f=flags: successful(f + [str(p) for p in contract_files]))
            for probe in sorted((ROOT / 'verification/probes').glob('*.d')):
                if probe.name.startswith('wasm_abi'):
                    continue  # The dedicated real link/run probe handles this below.
                def probe_check(probe=probe, flags=flags):
                    extra = ['-betterC'] if 'betterc' in probe.name else []
                    result = run(flags + extra + [str(probe)])
                    if 'negative' in probe.name:
                        require(result['returncode'] != 0, 'negative misuse unexpectedly accepted')
                        expected = {'borrow': r'scope.*(global|escape)|escap.*scope',
                                    'storage': r'escap.*(backing|local)',
                                    'forge': r'private|accessible|not visible'}
                        pattern = next((v for k, v in expected.items() if k in probe.name), r'Error:')
                        require(re.search(pattern, result['stderr'] + result['stdout'], re.I | re.S),
                                'negative failed for unrelated reason: ' + json.dumps(result))
                    else:
                        require(result['returncode'] == 0, json.dumps(result))
                    result['source_sha256'] = sha256(probe)
                    result['scope'] = 'compile-only API/misuse check'
                    return result
                check(name + ' ' + probe.name, probe_check)
            for folder in ['golden-cli', 'golden-tui', 'golden-rest-service', 'golden-wasm-app']:
                files = sorted((ROOT / 'templates' / folder).rglob('*.d'))
                if not files:
                    continue  # Missing template was already reported in structure.
                def golden_check(files=files, folder=folder, flags=flags, name=name):
                    args2 = list(flags)
                    if folder == 'golden-wasm-app':
                        args2 += ['-betterC']
                        if name == 'ldc2':
                            args2 += ['-mtriple=wasm32-unknown-unknown-wasm']
                    for directory in sorted({p.parent for p in files}):
                        args2 += ['-I' + str(directory)]
                    result = successful(args2 + [str(p) for p in files])
                    result['scope'] = 'golden API typecheck; runtime linking waits for implemented packages'
                    return result
                check(name + ' ' + folder, golden_check)
            def betterc_fixtures(flags=flags, name=name):
                results = []
                for source in sorted((ROOT / 'scaffold/packages').glob('*/tests/betterc.d')):
                    command = flags + ['-betterC', str(source)]
                    result = successful(command)
                    result['source_sha256'] = sha256(source)
                    result['scope'] = 'fixture semantic check only; runtime assertions need actual package bodies'
                    results.append(result)
                    if name == 'ldc2':
                        result = successful(flags + ['-betterC', '-mtriple=wasm32-unknown-unknown-wasm',
                                                      '-checkaction=halt', str(source)])
                        result['source_sha256'] = sha256(source)
                        result['scope'] = 'wasm32 fixture semantic check only'
                        results.append(result)
                require(len(results) == (10 if name == 'ldc2' else 5), 'five BetterC runtime fixtures required')
                return results
            check(name + ' five BetterC behavior fixture contracts', betterc_fixtures)
            for benchmark_name in ['bench-cli', 'bench-rest']:
                benchmark = ROOT / 'scaffold/benchmarks' / benchmark_name / 'source/app.d'
                check(name + ' ' + benchmark_name + ' application contract',
                      lambda flags=flags, benchmark=benchmark: successful(flags + [str(benchmark)]))
            # Every complete D module in Markdown must independently typecheck.
            def snippets_check(flags=flags):
                count = 0
                for path in sorted(ROOT.rglob('*.md')):
                    for index, code in enumerate(d_blocks(path)):
                        source = tmp / 'snippet.d'
                        source.write_text(code, encoding='utf-8')
                        result = run(flags + [str(source)])
                        require(result['returncode'] == 0,
                                str(path.relative_to(ROOT)) + f' D block {index}: ' + json.dumps(result))
                        count += 1
                return {'complete_modules': count, 'scope': 'standalone D blocks only; context fragments are not represented as runtime tests'}
            check(name + ' standalone Markdown D modules', snippets_check)
        dub = args.dub
        if not dub:
            for _, compiler in compilers:
                candidate = Path(compiler).resolve().parent / ('dub.exe' if os.name == 'nt' else 'dub')
                if candidate.exists():
                    dub = str(candidate)
                    break
        if dub and compilers:
            def dub_check():
                workspace = tmp / 'dub-workspace'
                shutil.copytree(ROOT / 'scaffold', workspace, ignore=shutil.ignore_patterns('.dub', '__pycache__'))
                packages = load_json(ROOT / 'scaffold/policy/packages.json')['packages']
                results = []
                for package in packages:
                    result = successful([dub, 'describe', ':' + package, '--compiler=' + str(compilers[0][1])], workspace)
                    description=json.loads(result['stdout'])
                    require(description.get('rootPackage')=='flint:'+package,'DUB did not resolve the requested child: '+package)
                    names={p['name'] for p in description.get('packages',[])}
                    require('flint:'+package in names,'DUB result lacks requested package')
                    results.append(package)
                return {'packages': results, 'scope': 'real DUB manifest resolution in a temporary copy; no source-free build reported as success'}
            check('DUB manifest resolution', dub_check)
        else:
            report['checks'].append({'name': 'DUB manifest resolution', 'status': 'not_run', 'detail': 'DUB plus a D compiler required'})
        if args.ldc and args.node:
            wasm_script = ROOT / 'tools/verify_wasm.py'
            if wasm_script.exists():
                check('standalone WASM ABI link and execution', lambda: successful([sys.executable, str(wasm_script), '--ldc', args.ldc, '--node', args.node]))
            else:
                check('standalone WASM ABI probe availability', lambda: require(False, 'missing tools/verify_wasm.py'))
        else:
            report['checks'].append({'name': 'standalone WASM ABI link and execution', 'status': 'not_run', 'detail': 'LDC plus Node required'})
        if args.node:
            check('browser driver epoch, bounds, confinement and replay tests', lambda: successful(
                [args.node, str(ROOT / 'verification/probes/driver_contract_test.mjs')]))
    if args.go:
        env = os.environ.copy()
        env.update({'GOTOOLCHAIN': 'local', 'GOPROXY': 'off', 'GOSUMDB': 'off'})
        check('Go reference unit tests', lambda: successful([args.go, 'test', './...'], ROOT / 'templates/reference-go-rest', timeout=120, env=env))
    else:
        report['checks'].append({'name': 'Go reference unit tests', 'status': 'not_run', 'detail': 'provide --go to run the reference service tests'})
    failed = [x for x in report['checks'] if x['status'] == 'fail']
    skipped = [x for x in report['checks'] if x['status'] == 'not_run']
    report['status'] = 'failed' if failed else ('passed_with_explicit_not_run_checks' if skipped else 'passed')
    report['counts'] = {s: sum(x['status'] == s for x in report['checks']) for s in ('pass', 'fail', 'not_run')}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    for item in report['checks']:
        print(item['status'].upper() + ': ' + item['name'])
        if item['status'] == 'fail':
            print(str(item['detail'])[:4000])
    print(json.dumps({'status': report['status'], 'counts': report['counts'], 'report': str(args.report)}, indent=2))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
