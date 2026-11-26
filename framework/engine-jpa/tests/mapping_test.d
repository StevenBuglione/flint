/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.mapping_test;

import flint.arena : Error, Result, Status;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    ResultBinding, planResult, validateEntity, validateMapping;
import flint.java.sql : Types;

@safe:

private class Record
{
    long id;
}

private final class OtherRecord : Record
{
}

private Object constructRecord()
{
    return new Record;
}

private bool isExactRecordType(scope const TypeInfo_Class candidate) nothrow @nogc
{
    return candidate is typeid(Record);
}

private Result!AttributeValue readId(Object entity) nothrow @nogc
{
    auto record = cast(Record) entity;
    if (record is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Record"));
    return Result!AttributeValue(AttributeValue(AttributeKind.integer, record.id));
}

private void writeId(Object entity, const ref AttributeValue value)
{
    (cast(Record) entity).id = value.integer;
}

private immutable EntityMapping recordMapping = EntityMapping("Record",
        "flint.engine.jpa.mapping_test.Record", "records",
        [
            AttributeMapping(0, "id", "id", AttributeKind.integer, &readId, &writeId, false,
                false, true, false, 0, Types.BIGINT)
], &constructRecord, [], &isExactRecordType, [0]);

@("an exact type guard rejects missing metadata, null entities and subclasses")
unittest
{
    assert(validateMapping(recordMapping).code == Status.ok);
    assert(validateEntity(recordMapping, new Record).code == Status.ok);
    assert(validateEntity(recordMapping, null).code == Status.invalidArgument);
    assert(validateEntity(recordMapping, new OtherRecord).code == Status.invalidArgument);
    const missing = EntityMapping.init;
    assert(validateEntity(missing, new Record).code == Status.invalidArgument);
}

@("row plans reject projections with an invalid persistent ordinal or SQL position")
unittest
{
    assert(planResult(&recordMapping, [ResultBinding(0, 3)]).ok);
    assert(planResult(null, [ResultBinding(0, 1)]).error.code == Status.invalidArgument);
    assert(planResult(&recordMapping, []).error.code == Status.invalidArgument);
    assert(planResult(&recordMapping, [ResultBinding(1, 1)]).error.code == Status.invalidArgument);
    assert(planResult(&recordMapping, [ResultBinding(0, 0)]).error.code == Status.invalidArgument);
}

@("attribute writers cannot take borrowed text that may outlive the caller")
unittest
{
    static assert(!__traits(compiles, (scope string borrowed, AttributeMapping mapping) @safe {
            scope AttributeValue value;
            value.text = borrowed;
            mapping.write(null, value);
        }));
}
