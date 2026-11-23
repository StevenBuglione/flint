# flint:starter-data-jdbc

This starter is a dependency bundle and the `[database]` section, and holds no code (ADR-029 section 8). It brings flint:data, flint:sql, flint:migrate and `flint:boot-autoconfigure-data`, whose `DataSourceAutoConfiguration` does three things:
- opens a SQL pool from `[database]`;
- applies the project's migrations at start-up;
- makes repositories beans.

```bash
flint add web data-jdbc
flint generate migration create_notes
```

## Use

```d
import flint.arena : Result, Text;
import flint.boot : runApplication;
import flint.boot_autoconfigure_data : DataSourceAutoConfiguration, Repository;
import flint.boot_autoconfigure_web : WebServerAutoConfiguration;
import flint.data : Id, Table;
import flint.validate : NotBlank, Valid;
import flint.web : Post, RequestBody, RequestContext, RestController;

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
    return runApplication!(WebServerAutoConfiguration, DataSourceAutoConfiguration, Notes, NoteController)(args);
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
cd starters/data-jdbc/example
flint run
curl -X POST -H 'Content-Type: application/json' -d '{"title":"First","body":"hi"}' localhost:8080/api/notes
curl localhost:8080/api/notes/1
```
