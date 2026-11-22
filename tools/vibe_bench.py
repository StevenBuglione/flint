#!/usr/bin/env python3
"""The vibe-coding benchmark (ADR-021 section 11, ADR-027 section 6).

A coding agent gets a task statement and an empty project, builds the program, and the task's black-box acceptance
test scores it. The same acceptance test scores Flint, Go and Spring Boot solutions.

    vibe_bench.py list
    vibe_bench.py prepare <task> --language flint --dir <workspace>
    vibe_bench.py accept <task> --language flint --dir <workspace> [--json <file>]
    vibe_bench.py reference [<task>...] [--language flint]
    vibe_bench.py run <task> --language flint --agent claude [--runs 3] [--model <id>] [--out benchmarks/vibe/results]
    vibe_bench.py report <result.json>...

What is scored, per run:
- success: every acceptance check passes; the share of passing checks is kept too.
- build-fix iterations: the builds and test runs the agent started, from `flint mcp --log` for Flint and from
  logging shims of `go`, `mvn`, `./mvnw` and `gradle` for the others, and how many of them failed.
- wall time of the agent run.
- review size: source lines (non-blank, non-comment) and attributes (D UDAs, Java annotations, Go struct tags).

Agent runs cost model usage, so `run` only starts when asked; `accept` and `reference` cost nothing.
"""
import argparse
import importlib.util
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'benchmarks' / 'vibe'
TASKS = BENCH / 'tasks'
LANGUAGES = ('flint', 'go', 'spring')
EXECUTABLES = {'rest-notes': 'notes', 'cli-todo': 'todo', 'queue-worker': 'worker', 'tui-dashboard': 'dash'}
FLINT = ROOT / '.flint' / 'bin' / 'flint'
GO = ROOT / '.tools' / 'go' / 'bin' / 'go'

PREAMBLE = {
    'flint': """You are building this program in D with Flint, in the current directory, which is a fresh
`flint new` project. Read AGENTS.md first. Use the `flint` MCP server's tools to look up the exact API
(search_api, get_symbol, get_example, explain_error), to generate components, and to build, test and check
(build, test, check). Do not ask questions; work until the program meets the statement, then stop.
The executable must be named `{executable}` (set `[build] executable` in flint.toml if needed).
""",
    'go': """You are building this program in Go, in the current directory, which has a go.mod. Use your usual tools.
Build it with `go build -o {executable} .`. Do not ask questions; work until the program meets the statement,
then stop.
""",
    'spring': """You are building this program in Java with Spring Boot, in the current directory. Use your usual
tools and a Maven wrapper (`./mvnw`). `./mvnw -q -DskipTests package` must produce exactly one runnable jar in
target/. Do not ask questions; work until the program meets the statement, then stop.
""",
}


def task_names():
    return sorted(p.name for p in TASKS.iterdir() if (p / 'TASK.md').is_file())


def load_acceptance(task):
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location(f'vibe_{task.replace("-", "_")}', TASKS / task / 'acceptance.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prompt(task, language):
    return PREAMBLE[language].format(executable=EXECUTABLES[task]) + '\n' + (TASKS / task / 'TASK.md').read_text()


def run_quiet(command, cwd, env=None, timeout=900):
    return subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def prepare(task, language, directory):
    directory = Path(directory).resolve()
    if directory.exists() and any(directory.iterdir()):
        raise SystemExit(f'{directory} is not empty')
    directory.parent.mkdir(parents=True, exist_ok=True)
    if directory.exists():
        directory.rmdir()
    name = EXECUTABLES[task]
    if language != 'flint':
        directory.mkdir()
    if language == 'flint':
        kind = 'web' if task == 'rest-notes' else 'cli'
        result = run_quiet([str(FLINT), 'new', '--path', str(directory), '--starter', kind, name], directory.parent)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    elif language == 'go':
        result = run_quiet([str(GO), 'mod', 'init', 'example.com/' + name], directory)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    (directory / 'PROMPT.md').write_text(prompt(task, language))
    return directory


def build(task, language, directory):
    """Build the solution; returns (Program or None, log)."""
    from vibelib import Program
    directory = Path(directory).resolve()
    if language == 'flint':
        result = run_quiet([str(FLINT), 'build', '-C', str(directory), '--json'], directory)
        try:
            document = json.loads(result.stdout)
        except ValueError:
            return None, result.stdout + result.stderr
        artifact = document.get('artifact', {}).get('path') if isinstance(document.get('artifact'), dict) else None
        if result.returncode or not artifact:
            return None, result.stdout + result.stderr
        path = Path(artifact) if Path(artifact).is_absolute() else directory / artifact
        if not path.is_file():
            path = ROOT / artifact
        return Program([str(path)]), ''
    if language == 'go':
        output = directory / '.vibe' / EXECUTABLES[task]
        result = run_quiet([str(GO), 'build', '-o', str(output), '.'], directory)
        return (Program([str(output)]) if result.returncode == 0 else None), result.stdout + result.stderr
    wrapper = directory / 'mvnw'
    result = run_quiet([str(wrapper) if wrapper.exists() else 'mvn', '-q', '-DskipTests', 'package'], directory)
    jars = [p for p in (directory / 'target').glob('*.jar') if not p.name.endswith('-plain.jar')]
    if result.returncode or len(jars) != 1:
        return None, result.stdout + result.stderr
    return Program(['java', '-jar', str(jars[0])]), ''


def accept(task, language, directory):
    """Build and run the acceptance test; returns a result dictionary."""
    sys.path.insert(0, str(BENCH))
    started = time.monotonic()
    program, log = build(task, language, directory)
    built = time.monotonic()
    if program is None:
        return {'task': task, 'language': language, 'built': False, 'build_log': log[-4000:], 'checks': [],
                'passed': 0, 'total': 0, 'success': False, 'build_seconds': round(built - started, 2)}
    results = load_acceptance(task).checks(program)
    passed = sum(c.passed for c in results)
    return {'task': task, 'language': language, 'built': True, 'passed': passed, 'total': len(results),
            'success': passed == len(results) and len(results) > 0,
            'checks': [{'name': c.name, 'passed': c.passed, 'detail': c.detail} for c in results],
            'build_seconds': round(built - started, 2), 'accept_seconds': round(time.monotonic() - built, 2)}


COMMENT = {'d': re.compile(r'^\s*(//|/\*|\*|\+/|/\+)'), 'go': re.compile(r'^\s*(//|/\*|\*)'),
           'java': re.compile(r'^\s*(//|/\*|\*)')}
ATTRIBUTE = {'d': re.compile(r'@[A-Z]\w*'), 'java': re.compile(r'@[A-Z]\w*'), 'go': re.compile(r'`[^`]*:"[^`]*`')}
SOURCES = {'flint': ('d', ('src', 'test')), 'go': ('go', ('.',)), 'spring': ('java', ('src',))}


def review_size(language, directory):
    suffix, roots = SOURCES[language]
    lines = attributes = files = 0
    for root in roots:
        base = Path(directory) / root
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.' + suffix)):
            if any(part.startswith('.') or part in ('target', 'vendor') for part in path.relative_to(directory).parts):
                continue
            files += 1
            for line in path.read_text(errors='replace').splitlines():
                if line.strip() and not COMMENT[suffix].match(line):
                    lines += 1
                    attributes += len(ATTRIBUTE[suffix].findall(line))
    return {'files': files, 'lines': lines, 'attributes': attributes}


SHIM = """#!/bin/sh
printf '%s\\n' "$(date +%s%N) $(basename "$0") $*" >> {log}
exec {real} "$@"
"""


def shims(directory, log):
    """Logging wrappers for the build tools the Go and Spring Boot agents call."""
    bin_dir = Path(directory) / 'shims'
    bin_dir.mkdir()
    for name, real in (('go', str(GO)), ('mvn', shutil.which('mvn')), ('gradle', shutil.which('gradle'))):
        if real:
            path = bin_dir / name
            path.write_text(SHIM.format(log=shlex.quote(str(log)), real=shlex.quote(real)))
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return bin_dir


def iterations(language, mcp_log, shim_log):
    """Builds and test runs the agent started, and how many failed (failures are known for MCP calls only)."""
    if language == 'flint':
        calls = []
        if mcp_log.is_file():
            calls = [json.loads(line) for line in mcp_log.read_text().splitlines() if line.strip()]
        loops = [c for c in calls if c.get('tool') in ('build', 'test', 'check')]
        return {'builds': len(loops), 'failed': sum(c.get('exit_code', 0) != 0 for c in loops),
                'knowledge_calls': sum(c.get('tool') in ('search_api', 'get_symbol', 'get_example', 'explain_error')
                                       for c in calls)}
    lines = shim_log.read_text().splitlines() if shim_log.is_file() else []
    loops = [line for line in lines if re.search(r' (go (build|test|run|vet)|mvn\S* .*(package|test|verify|compile)|'
                                                r'gradle .*(build|test|bootJar))', line)]
    return {'builds': len(loops), 'failed': None}


def agent_command(agent, language, directory, prompt_file, model, mcp_log, template):
    """The agent's command line. Flint runs get only the flint MCP server and file tools; the others get a shell."""
    text = Path(prompt_file).read_text()
    if agent == 'claude':
        command = ['claude', '-p', text, '--output-format', 'json', '--permission-mode', 'acceptEdits']
        if model:
            command += ['--model', model]
        if language == 'flint':
            config = Path(directory).parent / 'mcp.json'
            config.write_text(json.dumps({'mcpServers': {'flint': {'command': str(FLINT),
                                                                   'args': ['mcp', '--log', str(mcp_log)]}}}))
            command += ['--mcp-config', str(config), '--strict-mcp-config',
                        '--allowedTools', 'mcp__flint,Read,Write,Edit,Glob,Grep', '--disallowedTools', 'Bash']
        else:
            command += ['--allowedTools', 'Bash,Read,Write,Edit,Glob,Grep']
        return command
    if agent == 'codex':
        command = ['codex', 'exec', '--full-auto', '--skip-git-repo-check']
        if model:
            command += ['--model', model]
        if language == 'flint':
            command += ['-c', 'mcp_servers.flint.command=' + json.dumps(str(FLINT)),
                        '-c', 'mcp_servers.flint.args=' + json.dumps(['mcp', '--log', str(mcp_log)])]
        return command + [text]
    if not template:
        raise SystemExit('--agent command needs --agent-command')
    return shlex.split(template.format(prompt=shlex.quote(str(prompt_file)), dir=shlex.quote(str(directory)),
                                       mcp_log=shlex.quote(str(mcp_log)), flint=shlex.quote(str(FLINT))))


def run(task, language, agent, runs, model, out, template, timeout):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    for index in range(runs):
        scratch = Path(tempfile.mkdtemp(prefix=f'vibe-{task}-{language}-'))
        directory = prepare(task, language, scratch / 'work')
        mcp_log = scratch / 'mcp.jsonl'
        shim_log = scratch / 'shims.log'
        env = {k: v for k, v in os.environ.items() if not k.startswith('FLINT_')}
        env['PATH'] = str(shims(scratch, shim_log)) + os.pathsep + env.get('PATH', '')
        command = agent_command(agent, language, directory, directory / 'PROMPT.md', model, mcp_log, template)
        started = time.monotonic()
        try:
            finished = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True, timeout=timeout)
            exit_code, transcript = finished.returncode, finished.stdout + finished.stderr
        except subprocess.TimeoutExpired as expired:
            exit_code, transcript = None, (expired.stdout or b'').decode(errors='replace') if isinstance(
                expired.stdout, bytes) else (expired.stdout or '')
        wall = time.monotonic() - started
        (scratch / 'transcript.txt').write_text(transcript)
        record = accept(task, language, directory)
        record.update({'run': index + 1, 'agent': agent, 'model': model, 'agent_exit': exit_code,
                       'wall_seconds': round(wall, 1), 'iterations': iterations(language, mcp_log, shim_log),
                       'review': review_size(language, directory), 'workspace': str(scratch)})
        records.append(record)
        print(f"{task} {language} run {index + 1}: {'pass' if record['success'] else 'FAIL'} "
              f"{record['passed']}/{record['total']} checks, {record['iterations']['builds']} builds, "
              f"{record['wall_seconds']} s", file=sys.stderr)
    path = out / f'{task}-{language}-{agent}-{time.strftime("%Y%m%dT%H%M%S")}.json'
    path.write_text(json.dumps({'schema': 'flint.vibe/1', 'records': records}, indent=1) + '\n')
    print(path)
    return records


def summary(records):
    rows = {}
    for record in records:
        rows.setdefault((record['task'], record['language']), []).append(record)
    lines = ['| Task | Language | Runs | Success | Checks | Builds (failed) | Wall s | Lines | Attributes |',
             '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for (task, language), group in sorted(rows.items()):
        def median(values):
            values = sorted(v for v in values if v is not None)
            return values[len(values) // 2] if values else None
        builds = median(r.get('iterations', {}).get('builds') for r in group)
        failed = median(r.get('iterations', {}).get('failed') for r in group)
        lines.append(f"| {task} | {language} | {len(group)} | {sum(r['success'] for r in group)}/{len(group)} | "
                     f"{median(r['passed'] / r['total'] if r['total'] else 0 for r in group):.0%} | "
                     f"{builds if builds is not None else '–'} ({failed if failed is not None else '–'}) | "
                     f"{median(r.get('wall_seconds') for r in group) or '–'} | "
                     f"{median(r.get('review', {}).get('lines') for r in group) or '–'} | "
                     f"{median(r.get('review', {}).get('attributes') for r in group) or '–'} |")
    return '\n'.join(lines)


def print_result(record):
    for check in record['checks']:
        print(('  ok    ' if check['passed'] else '  FAIL  ') + check['name']
              + ('' if check['passed'] else '\n          ' + check['detail'].replace('\n', '\n          ')[:600]))
    if not record['built']:
        print('  build failed:\n' + record['build_log'])
    print(f"{record['task']} ({record['language']}): {record['passed']}/{record['total']} checks"
          + (' — success' if record['success'] else ''))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('list')
    for name in ('prepare', 'accept'):
        sub = commands.add_parser(name)
        sub.add_argument('task', choices=task_names())
        sub.add_argument('--language', choices=LANGUAGES, default='flint')
        sub.add_argument('--dir', required=True)
        sub.add_argument('--json')
    sub = commands.add_parser('reference')
    sub.add_argument('tasks', nargs='*')
    sub.add_argument('--language', choices=LANGUAGES, default='flint')
    sub = commands.add_parser('oracle', help='score the Python oracle that proves a task\'s acceptance test sound')
    sub.add_argument('tasks', nargs='*')
    sub = commands.add_parser('run')
    sub.add_argument('task', choices=task_names())
    sub.add_argument('--language', choices=LANGUAGES, default='flint')
    sub.add_argument('--agent', choices=('claude', 'codex', 'command'), required=True)
    sub.add_argument('--agent-command', help='for --agent command: a template with {prompt}, {dir}, {mcp_log}, {flint}')
    sub.add_argument('--runs', type=int, default=1)
    sub.add_argument('--model')
    sub.add_argument('--timeout', type=int, default=3600)
    sub.add_argument('--out', default=str(BENCH / 'results'))
    sub = commands.add_parser('report')
    sub.add_argument('results', nargs='+')
    arguments = parser.parse_args()

    if arguments.command == 'list':
        for task in task_names():
            print(task)
    elif arguments.command == 'prepare':
        print(prepare(arguments.task, arguments.language, arguments.dir))
    elif arguments.command == 'accept':
        record = accept(arguments.task, arguments.language, arguments.dir)
        record['review'] = review_size(arguments.language, arguments.dir)
        print_result(record)
        if arguments.json:
            Path(arguments.json).write_text(json.dumps(record, indent=1) + '\n')
        return 0 if record['success'] else 1
    elif arguments.command == 'reference':
        failed = 0
        for task in arguments.tasks or task_names():
            directory = BENCH / 'reference' / arguments.language / task
            if not directory.is_dir():
                print(f'{task} ({arguments.language}): no reference solution')
                failed += 1
                continue
            record = accept(task, arguments.language, directory)
            record['review'] = review_size(arguments.language, directory)
            print_result(record)
            print(f"  review size: {record['review']}")
            failed += not record['success']
        return 1 if failed else 0
    elif arguments.command == 'oracle':
        sys.path.insert(0, str(BENCH))
        from vibelib import Program
        failed = 0
        for task in arguments.tasks or task_names():
            oracle = BENCH / 'oracles' / (task.replace('-', '_') + '.py')
            if not oracle.is_file():
                print(f'{task}: no oracle')
                continue
            results = load_acceptance(task).checks(Program([sys.executable, '-I', str(oracle)]))
            record = {'task': task, 'language': 'oracle', 'built': True, 'passed': sum(c.passed for c in results),
                      'total': len(results), 'checks': [vars(c) for c in results]}
            record['success'] = record['passed'] == record['total'] > 0
            print_result(record)
            failed += not record['success']
        return 1 if failed else 0
    elif arguments.command == 'run':
        records = run(arguments.task, arguments.language, arguments.agent, arguments.runs, arguments.model,
                      arguments.out, arguments.agent_command, arguments.timeout)
        print(summary(records))
    elif arguments.command == 'report':
        records = []
        for path in arguments.results:
            records += json.loads(Path(path).read_text())['records']
        print(summary(records))
    return 0


if __name__ == '__main__':
    sys.exit(main())
