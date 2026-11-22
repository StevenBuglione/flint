module entity_negative;

import flint.data : Column, Id, SqlRepository, Table, Version;
import flint.sql : Pool;

@safe:

version (FlintDataMissingId)
{
    @Table("records")
    private struct Record
    {
        long quantity;
    }
}
else version (FlintDataMissingTable)
{
    private struct Record
    {
        @Id long id;
    }
}
else version (FlintDataDuplicateId)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        @Id long duplicate;
    }
}
else version (FlintDataDuplicateColumn)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        @Column("label") long first;
        @Column("LABEL") long duplicate;
    }
}
else version (FlintDataPointer)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        int* pointer;
    }
}
else version (FlintDataClass)
{
    private class Unsupported
    {
    }

    @Table("records")
    private struct Record
    {
        @Id long id;
        Unsupported object;
    }
}
else version (FlintDataDelegate)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        void delegate() callback;
    }
}
else version (FlintDataInvalidTable)
{
    @Table("invalid-table")
    private struct Record
    {
        @Id long id;
    }
}
else version (FlintDataInvalidColumn)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        @Column("invalid-column") long value;
    }
}
else version (FlintDataDuplicateVersion)
{
    @Table("records")
    private struct Record
    {
        @Id long id;
        @Version long first;
        @Version long duplicate;
    }
}
else version (FlintDataWrongKey)
{
    @Table("records")
    private struct Record
    {
        @Id ulong id;
    }
}

/// Instantiate the repository to expose the deliberate schema diagnostic.
void rejectEntity(ref Pool pool)
{
    new SqlRepository!(Record, long)(pool);
}
