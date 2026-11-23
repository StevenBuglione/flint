/// notes: a CRUD REST API over SQLite, wired by flint:starter-web and flint:starter-data.
module notes.app;

import flint.starter_data : DataAutoConfiguration, Id, Repository, Table, Text;
import flint.starter_web : Delete, Error, Get, NotBlank, PathVariable, Post, RequestBody,
    RequestContext, RestController, Result, Status, Valid, runApplication;

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
    return runApplication!(DataAutoConfiguration, Notes, NoteController)(args);
}
