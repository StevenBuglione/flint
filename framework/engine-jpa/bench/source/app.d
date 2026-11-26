/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module app;

import core.stdc.stdio : fputc, stdout;
import flint.arena : Error, Result, Status;
import flint.engine.jdbc : FlintDataSource, enablePostgres;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    ResultBinding, materializeRow, planResult;
import flint.java.sql : Types;

@safe:

private final class Owner
{
    long id;
    string name;
}

private Object constructOwner()
{
    return new Owner;
}

private bool isExactOwner(scope const TypeInfo_Class candidate) nothrow @nogc
{
    return candidate is typeid(Owner);
}

private Result!AttributeValue readId(Object entity) nothrow @nogc
{
    auto owner = cast(Owner) entity;
    if (owner is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Owner"));
    return Result!AttributeValue(AttributeValue(AttributeKind.integer, owner.id));
}

private Result!AttributeValue readName(Object entity) nothrow @nogc
{
    auto owner = cast(Owner) entity;
    if (owner is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Owner"));
    AttributeValue value;
    value.kind = AttributeKind.text;
    value.text = owner.name;
    return Result!AttributeValue(value);
}

private void writeId(Object entity, const ref AttributeValue value)
{
    (cast(Owner) entity).id = value.integer;
}

private void writeName(Object entity, const ref AttributeValue value)
{
    (cast(Owner) entity).name = value.text;
}

private immutable EntityMapping ownerMapping = EntityMapping("Owner", "app.Owner", "owners",
        [
            AttributeMapping(0, "id", "id", AttributeKind.integer, &readId, &writeId, false,
                false, true, false, 0, Types.BIGINT),
            AttributeMapping(1, "name", "name", AttributeKind.text, &readName, &writeName,
                false, false, true, true, 0, Types.LONGVARCHAR)
], &constructOwner, [], &isExactOwner, [0]);

private immutable ResultBinding[] bindings = [ResultBinding(1, 1), ResultBinding(0, 2)];

int main(string[] args)
{
    if (args.length != 4)
        return 2;
    const planned = planResult(&ownerMapping, bindings);
    if (!planned.ok)
        return 1;

    enablePostgres();
    auto dataSource = new FlintDataSource(args[1]);
    dataSource.setUsername(args[2]);
    dataSource.setPassword(args[3]);
    scope (exit)
        dataSource.close();
    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    auto statement = connection.prepareStatement("select 'One'::text as name, 1::bigint as id");
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    if (!rows.next())
        return 1;
    const materialized = materializeRow(planned.value, rows);
    if (!materialized.ok)
        return 1;
    const owner = cast(const Owner) materialized.value;
    if (owner is null || owner.id != 1 || owner.name != "One")
        return 1;
    foreach (character; owner.name)
        fputc(character, stdout);
    fputc('\n', stdout);
    return 0;
}
