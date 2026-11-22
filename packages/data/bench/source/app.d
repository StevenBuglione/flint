module app;

import flint.arena : RequestArena, Status;
import flint.conc : Context;
import flint.data : CrudRepository, Id, SqlRepository, Table, Version;
import flint.sql : Pool;
import probe : benchmark, require, rows;

@safe:

@Table("probe_rows")
private struct Record
{
    @Id long id;
    long payload;
    @Version long revision;
}

private ulong run(ref Pool pool, ref Context context)
{
    CrudRepository!(Record, long) repository = new SqlRepository!(Record, long)(pool);
    scope RequestArena arena;
    ulong checksum;
    foreach (value; 1 .. rows + 1)
    {
        const input = Record(0, value);
        const inserted = repository.save(input, arena, context);
        require(inserted.ok() && inserted.value.id > 0);
        const read = repository.findById(inserted.value.id, arena, context);
        require(read.ok() && read.value.payload == value && read.value.revision == 0);
        auto update = Record(read.value.id, value + 1, read.value.revision);
        const updated = repository.save(update, arena, context);
        require(updated.ok() && updated.value.payload == value + 1 && updated.value.revision == 1);
        const present = repository.existsById(read.value.id, context);
        require(present.ok() && present.value);
        require(repository.deleteById(read.value.id, context).code == Status.ok);
        const absent = repository.existsById(read.value.id, context);
        require(absent.ok() && !absent.value);
        checksum += updated.value.payload + updated.value.revision;
    }
    return checksum;
}

void main(string[] args)
{
    benchmark(args, &run);
}
