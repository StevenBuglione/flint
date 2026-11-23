# flint:starter-data

This starter opens a SQL pool from `[database]` and applies the project's migrations at start-up. Repositories are beans (ADR-028 section 7).

```bash
flint add web data
flint generate migration create_notes
```

## Use

```d
import flint.starter_data : DataAutoConfiguration, Id, Repository, Table, Text;
import flint.starter_web : Get, NotBlank, PathVariable, Post, RequestBody, RequestContext, RestController, Result,
    Valid, runApplication;

@Table("notes")
struct Note
{
    @Id ulong id;
    @NotBlank Text title;
    Text body;
}

alias Notes = Repository!(Note, ulong);

@RestController("/api/notes")
struct NoteController
{
    private Notes notes;
    this(Notes notes) { this.notes = notes; }

    @Post("")
    Result!Note create(@RequestBody @Valid Note note, ref scope RequestContext context)
    {
        return notes.save(note, context.arena, context.cancellation);
    }
}

int main(string[] args)
{
    return runApplication!(DataAutoConfiguration, Notes, NoteController)(args);
}
```

- **`DataSource`** opens the pool from `[database]` and applies every `resources/migrations/V<version>__<description>.sql` in version order. Like `config/`, the migrations are read at start-up, and `flint package` ships `resources/`. flint:migrate records their hashes, so an edited applied migration stops start-up. The pool closes at shutdown.
- **`Repository!(E, ID)`** is a flint:data `CrudRepository` bean: `findById`, `save`, `deleteById` and `existsById`. `sql()` gives the underlying repository, for `queryOne` and projections. At construction it checks the table and columns against the migrated schema.
- **Text columns** are `Text` handles in the request arena. A repository call takes `context.arena`, and the handler returns the entity within the same request. Where business logic needs a `string`, use `toString(arena, text)` and `toText(arena, value)`.
- **Without a `[database]` section** the starter registers nothing.

## Configuration: `[database]`

| Key | Default | Meaning |
| --- | --- | --- |
| `driver` | `"sqlite"` | `sqlite` or `postgres` |
| `url` | none | A SQLite path or URI (`file:data.db`), or libpq connection settings |
| `max_connections` | `4` | Connections leased at once, at most 16 |
| `migrate` | `true` | Apply the migrations at start-up |
| `migrations` | `"resources/migrations"` | Where they are |

## Example

`example/` is a notes API with create, get and delete:

```bash
cd starters/data/example
flint run
curl -X POST -H 'Content-Type: application/json' -d '{"title":"First","body":"hi"}' localhost:8080/api/notes
curl localhost:8080/api/notes/1
```
