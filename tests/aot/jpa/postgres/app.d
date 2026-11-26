module app;

import flint.arena : Status;
import flint.engine.jpa : AttributeKind, EntityMapping, ResultBinding, materializeRow, planResult,
    validateEntity, validateMapping;
import flint.engine.jdbc : FlintDataSource, enablePostgres;
import flint.java.sql : Types;
import flint.java.time : LocalDate;
import flint_aot.jpa_probe.entity : jpaMappings, jpaTypedCodec;
import jpa_probe.entity : Owner;
import std.process : environment;

@safe:

private immutable ResultBinding[] projection = [
    ResultBinding(1, 1), ResultBinding(2, 2), ResultBinding(0, 3)
];

private void checkMetadata(scope const ref EntityMapping mapping)
{
    assert(validateMapping(mapping).code == Status.ok);
    assert(mapping.entityName == "Owner" && mapping.typeName == "jpa_probe.entity.Owner");
    assert(mapping.table == "jpa_seam_probe" && mapping.idOrdinals == [0]);
    assert(mapping.versionOrdinal == uint.max && !mapping.generatesId);
    assert(mapping.attributes.length == 3 && mapping.postLoad.length == 3);
}

private void checkAttributes(scope const ref EntityMapping mapping)
{
    with (mapping.attributes[0])
    {
        assert(ordinal == 0 && name == "id" && column == "id");
        assert(kind == AttributeKind.integer && sqlType == Types.BIGINT);
        assert(!columnNullable && !acceptsNull && insertable && !updatable);
    }
    with (mapping.attributes[1])
    {
        assert(ordinal == 1 && name == "name" && column == "name");
        assert(kind == AttributeKind.text && sqlType == Types.VARCHAR && columnLength == 255);
        assert(!columnNullable && acceptsNull && insertable && updatable);
    }
    with (mapping.attributes[2])
    {
        assert(ordinal == 2 && name == "birthDate" && column == "birth_date");
        assert(kind == AttributeKind.date && sqlType == Types.DATE);
    }
}

void main()
{
    const mappings = jpaMappings();
    assert(mappings.length == 1);
    const mapping = &mappings[0];
    checkMetadata(*mapping);
    checkAttributes(*mapping);
    const codec = jpaTypedCodec();
    const planned = planResult(mapping, projection, codec);
    assert(planned.ok);
    const date = LocalDate.of(1968, 2, 29);
    auto owner = cast(Owner) mapping.construct();
    assert(validateEntity(*mapping, owner).code == Status.ok);
    assert(validateEntity(*mapping, new Object).code == Status.invalidArgument);
    owner.birthDate = date;
    const encoded = mapping.attributes[2].read(owner);
    assert(encoded.ok && encoded.value.integer == date.toEpochDay());

    enablePostgres();
    auto dataSource = new FlintDataSource(environment.get("POSTGRES_URL"));
    dataSource.setUsername(environment.get("POSTGRES_USER"));
    dataSource.setPassword(environment.get("POSTGRES_PASS"));
    scope (exit)
        dataSource.close();
    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    auto create = connection.prepareStatement(
            "create table jpa_seam_probe (id bigint primary key, name text not null, birth_date date not null)");
    scope (exit)
        create.close();
    create.executeUpdate();
    auto insert = connection.prepareStatement("insert into jpa_seam_probe (id, name, birth_date) values (1, 'One', ?)");
    scope (exit)
        insert.close();
    codec.write(insert, 1, encoded.value);
    assert(insert.executeUpdate() == 1);
    auto query = connection.prepareStatement("select name, birth_date, id from jpa_seam_probe where id = 1");
    scope (exit)
        query.close();
    auto rows = query.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());
    const row = materializeRow(planned.value, rows);
    assert(row.ok);
    const loaded = cast(const Owner) row.value;
    assert(loaded.id == 1 && loaded.name == "One" && loaded.birthDate == date && loaded.loadedPhase() == 3);
}
