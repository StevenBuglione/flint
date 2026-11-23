/// notes: a CRUD REST API over SQLite, wired by flint:starter-web and flint:starter-data.
module notes.app;

import flint.arena : Error, Result, Status, Text;
import flint.boot : runApplication;
import flint.boot_autoconfigure_data : DataSourceAutoConfiguration, Repository;
import flint.boot_autoconfigure_web : WebServerAutoConfiguration;
import flint.data : Id, Table;
import flint.validate : NotBlank, Valid;
import flint.web : Delete, Get, PathVariable, Post, RequestBody, RequestContext, RestController;

@safe:

/// A note: the `notes` table and the JSON body.
@Table("notes")
struct Note
{
    /// Primary key, generated on insert.
    @Id ulong id;
    /// Required title.
    @NotBlank Text title;
    /// Text of the note.
    Text body;
}

/// The notes repository.
alias Notes = Repository!(Note, ulong);

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

int main(string[] args)
{
    return runApplication!(WebServerAutoConfiguration, DataSourceAutoConfiguration, Notes, NoteController)(args);
}
