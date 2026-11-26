module app;

import core.stdc.stdio : fputc, stdout;
import flint.jakarta.persistence : Column, Entity, Id, Table;

@safe:

private void emit(scope const(char)[] text) nothrow @nogc
{
    foreach (c; text)
        fputc(c, stdout);
    fputc('\n', stdout);
}

@Entity("Owner")
@Table("owners")
private class Owner
{
    @Id
    @Column("id")
    long id;
}

int main(string[] args)
{
    enum name = __traits(getAttributes, Owner)[0].name;
    enum table = __traits(getAttributes, Owner)[1].name;
    enum idColumn = __traits(getAttributes, Owner.id)[1].name;
    emit(args.length > 1 ? table : name ~ " " ~ table ~ " " ~ idColumn);
    return 0;
}
