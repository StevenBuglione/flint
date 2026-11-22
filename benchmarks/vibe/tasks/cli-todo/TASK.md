# To-do CLI with configuration and subcommands

Build a command-line program named `todo` that keeps a to-do list in a JSON file.

## Configuration

- The configuration file is the path in `TODO_CONFIG`, or else `$HOME/.config/todo/config.toml`. A missing file means defaults.
- It may contain:
  ```toml
  [todo]
  data_file = "/path/to/todos.json"   # default: $HOME/.local/share/todo/todos.json
  default_priority = "normal"         # low, normal or high
  ```
- An unknown key or an invalid value in the file is an error: exit code 3, and a message on standard error naming the key.
- The data file and its directory are created on first write.

## Commands

| Command | Effect | Output |
| --- | --- | --- |
| `todo add <text...> [--priority low\|normal\|high]` | Adds an item; the words of the text are joined by single spaces | `added <id>` |
| `todo list [--all] [--json]` | Lists open items, or every item with `--all`, by id | see below |
| `todo done <id>` | Marks an item done | `done <id>` |
| `todo remove <id>` | Deletes an item | `removed <id>` |
| `todo --help`, `todo <command> --help` | Help on standard output, exit 0 | usage text naming the commands or the options |
| `todo --version` | | `todo 1.0.0` |

- Ids are positive integers, start at 1 and are never reused, even after a removal.
- `-p` is short for `--priority`. When it is not given, the item takes `default_priority`.
- `list` prints one line per item: `<id> [ ] <priority> <text>`, or `<id> [x] <priority> <text>` for a done item. With no items it prints nothing.
- `list --json` prints a JSON array of `{"id": 1, "text": "...", "priority": "normal", "done": false}` objects.

## Exit codes

- 0: success.
- 1: an id that does not exist, with a message on standard error.
- 2: usage error: an unknown command or option, a missing or extra argument, a non-numeric id or an invalid priority. A message goes to standard error.
- 3: configuration error.
