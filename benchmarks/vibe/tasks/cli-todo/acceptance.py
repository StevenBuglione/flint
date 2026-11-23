"""Acceptance test for the to-do CLI (TASK.md)."""
import json
import subprocess
import tempfile
from pathlib import Path

from vibelib import Recorder


def checks(program):
    r = Recorder()
    with tempfile.TemporaryDirectory(prefix='vibe-cli-') as home:
        def todo(*arguments, config=None):
            extra = {'HOME': home}
            if config:
                extra['TODO_CONFIG'] = config
            result = subprocess.run(program.command(*arguments), cwd=home, capture_output=True, text=True,
                                    timeout=30, env=program.environment(**extra))
            return result.returncode, result.stdout, result.stderr

        try:
            run_checks(r, todo, Path(home))
        except Exception as error:  # noqa: BLE001 - a crash fails the remaining checks, not the harness
            r.crashed('run', error)
    return r.results


def run_checks(r, todo, home):
    code, out, _ = todo('--version')
    r.check('--version prints `todo 1.0.0`', code == 0 and out.strip() == 'todo 1.0.0', (code, out))
    code, out, _ = todo('--help')
    r.check('--help names the commands', code == 0 and all(w in out for w in ('add', 'list', 'done', 'remove')),
            (code, out))
    code, out, _ = todo('add', '--help')
    r.check('add --help names --priority', code == 0 and '--priority' in out, (code, out))
    code, out, _ = todo('list')
    r.check('list with no items prints nothing', code == 0 and out == '', (code, out))

    code, out, _ = todo('add', 'buy', 'milk')
    r.check('add prints `added 1`', code == 0 and out.strip() == 'added 1', (code, out))
    default_data = home / '.local/share/todo/todos.json'
    r.check('the default data file is created', default_data.is_file())
    code, out, _ = todo('add', 'write report', '--priority', 'high')
    r.check('add --priority', code == 0 and out.strip() == 'added 2', (code, out))
    code, out, _ = todo('add', '-p', 'low', 'water', 'plants')
    r.check('add -p before the text', code == 0 and out.strip() == 'added 3', (code, out))
    code, out, _ = todo('list')
    r.equal('list prints open items by id', (code, out.splitlines()),
            (0, ['1 [ ] normal buy milk', '2 [ ] high write report', '3 [ ] low water plants']))
    code, out, _ = todo('done', '2')
    r.check('done prints `done 2`', code == 0 and out.strip() == 'done 2', (code, out))
    code, out, _ = todo('list')
    r.equal('list hides done items', out.splitlines(), ['1 [ ] normal buy milk', '3 [ ] low water plants'])
    code, out, _ = todo('list', '--all')
    r.equal('list --all shows done items', out.splitlines(),
            ['1 [ ] normal buy milk', '2 [x] high write report', '3 [ ] low water plants'])
    code, out, _ = todo('remove', '1')
    r.check('remove prints `removed 1`', code == 0 and out.strip() == 'removed 1', (code, out))
    code, out, _ = todo('add', 'call mom')
    r.check('ids are never reused', out.strip() == 'added 4', out)
    code, out, _ = todo('list', '--all', '--json')
    try:
        items = json.loads(out)
    except ValueError:
        items = None
    r.equal('list --json', items, [
        {'id': 2, 'text': 'write report', 'priority': 'high', 'done': True},
        {'id': 3, 'text': 'water plants', 'priority': 'low', 'done': False},
        {'id': 4, 'text': 'call mom', 'priority': 'normal', 'done': False}])

    code, _, err = todo('done', '99')
    r.check('unknown id: exit 1 with a message', code == 1 and err.strip(), (code, err))
    code, _, err = todo('remove', '99')
    r.equal('remove unknown id: exit 1', code, 1)
    for name, arguments in [('unknown command', ['frobnicate']), ('unknown option', ['list', '--bogus']),
                            ('missing text', ['add']), ('missing id', ['done']), ('non-numeric id', ['done', 'abc']),
                            ('extra argument', ['done', '3', '4']), ('invalid priority', ['add', 'x', '-p', 'urgent'])]:
        code, _, err = todo(*arguments)
        r.check(f'usage error, {name}: exit 2 with a message', code == 2 and err.strip(), (code, err))

    data = home / 'elsewhere' / 'list.json'
    config = home / 'custom.toml'
    # as_posix(): a Windows path's backslashes would be escapes in a TOML basic string.
    config.write_text(f'[todo]\ndata_file = "{data.as_posix()}"\ndefault_priority = "high"\n')
    code, out, _ = todo('add', 'configured', config=str(config))
    r.check('TODO_CONFIG: data_file is used and created', code == 0 and out.strip() == 'added 1' and data.is_file(),
            (code, out))
    code, out, _ = todo('list', config=str(config))
    r.equal('TODO_CONFIG: default_priority applies', out.splitlines(), ['1 [ ] high configured'])
    default_config = home / '.config/todo/config.toml'
    default_config.parent.mkdir(parents=True)
    default_config.write_text('[todo]\ndefault_priority = "low"\n')
    code, out, _ = todo('add', 'from default config')
    _, listed, _ = todo('list')
    r.check('$HOME/.config/todo/config.toml is read', listed.splitlines()[-1:] == ['5 [ ] low from default config'],
            listed)
    bad = home / 'bad.toml'
    bad.write_text('[todo]\ncolour = "red"\n')
    code, _, err = todo('list', config=str(bad))
    r.check('unknown configuration key: exit 3 naming it', code == 3 and 'colour' in err, (code, err))
    bad.write_text('[todo]\ndefault_priority = "urgent"\n')
    code, _, err = todo('list', config=str(bad))
    r.check('invalid configuration value: exit 3 naming the key', code == 3 and 'default_priority' in err, (code, err))
