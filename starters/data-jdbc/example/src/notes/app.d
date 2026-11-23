/// notes: a CRUD REST API over SQLite, wired by flint:starter-web and flint:starter-data.
module notes.app;

import flint.arena : Error, Result, Status, Text;
import flint.boot : FlintApplication, FlintMain;
import flint.boot_autoconfigure_data : DataSource, JdbcRepository;
import flint.engine.di : Repository;
import flint.engine.data : Id, Table;
import flint.validate : NotBlank, Valid;
import flint.engine.web : Delete, Get, PathVariable, Post, RequestBody, RequestContext, RestController;

@safe:

/// A note: the `notes` table and the JSON body.
@Table("notes")
struct Note
{
    /// Primary key, generated on insert.
    @Id
    ulong id;
    /// Required title.
    @NotBlank
    Text title;
    /// Text of the note.
    Text body;
}

/// The notes repository.
@Repository
final class Notes : JdbcRepository!(Note, ulong)
{
    /// Check the table against the migrated schema.
    this(DataSource source)
    {
        super(source);
    }
}

/// `/api/notes`.
@RestController("/api/notes")
struct NoteController
{
    private Notes notes;

    /// Receive the repository.
    this(Notes notes)
    {
        this.notes = notes;
    }

    /// Create a note.
    @Post("")
    Result!Note create(@RequestBody @Valid Note note, ref scope RequestContext context)
    {
        note.id = 0;
        return notes.save(note, context.arena, context.cancellation);
    }

    /// Fetch a note.
    @Get("/:id")
    Result!Note get(@PathVariable("id") ulong id, ref scope RequestContext context)
    {
        return notes.findById(id, context.arena, context.cancellation);
    }

    /// Delete a note.
    @Delete("/:id")
    Error remove(@PathVariable("id") ulong id, ref scope RequestContext context)
    {
        if (!notes.existsById(id, context.cancellation).value)
            return Error(Status.notFound, "no such note");
        return notes.deleteById(id, context.cancellation);
    }
}

/// The application.
@FlintApplication
final class NotesApplication
{
    /// Start the application.
    static int main(string[] args)
    {
        return FlintApplication.run!NotesApplication(args);
    }
}

mixin FlintMain!NotesApplication;
