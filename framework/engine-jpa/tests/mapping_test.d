/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.mapping_test;

import flint.arena : Error, Result, Status;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    ResultBinding, planResult, validateEntity, validateMapping;
import flint.engine.jpa.parameter_binding : ParameterBinding, ParameterBindingPlan, planParameters;
import flint.engine.jpa.registry : registerMappings;
import flint.engine.jpa.result_binding : planManagedResult;
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

private Object constructOtherRecord()
{
    return new OtherRecord;
}

private bool isExactOtherRecordType(scope const TypeInfo_Class candidate) nothrow @nogc
{
    return candidate is typeid(OtherRecord);
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

private immutable EntityMapping otherRecordMapping = EntityMapping("OtherRecord",
        "flint.engine.jpa.mapping_test.OtherRecord",
        "records", recordMapping.attributes, &constructOtherRecord, [], &isExactOtherRecordType, [0]);

@("the mapping index uses exact class identity and copies the side table")
unittest
{
    static immutable EntityMapping[] descriptors = [recordMapping, otherRecordMapping];
    TypeInfo_Class[] classes = [typeid(Record), typeid(OtherRecord)];
    const registered = registerMappings(descriptors, classes);
    assert(registered.ok);
    classes[0] = typeid(Object);
    assert(registered.value.findExactObject(new Record) is &descriptors[0]);
    assert(registered.value.findExactObject(new OtherRecord) is &descriptors[1]);
    assert(registered.value.findExactObject(new Object) is null);
    assert(registered.value.findExactObject(null) is null);

    EntityMapping separateMapping = recordMapping;
    separateMapping.table = "other_unit";
    const separate = registerMappings([separateMapping].idup, [typeid(Record)]);
    assert(separate.ok && separate.value.findExactObject(new Record).table == "other_unit");
    assert(separate.value.findExactObject(new OtherRecord) is null);
    assert(registered.value.findExactObject(new Record).table == "records");
}

@("a missing, misordered or duplicate class identity prevents registry publication")
unittest
{
    static immutable EntityMapping[] descriptors = [recordMapping, otherRecordMapping];
    const missing = registerMappings(descriptors, [typeid(Record)]);
    assert(missing.error.code == Status.invalidArgument);
    const wrongOrder = registerMappings(descriptors, [typeid(OtherRecord), typeid(Record)]);
    assert(wrongOrder.error.code == Status.invalidArgument && wrongOrder.error.offset == 0);
    const nullEntry = registerMappings(descriptors, [typeid(Record), null]);
    assert(nullEntry.error.code == Status.invalidArgument && nullEntry.error.offset == 1);

    EntityMapping aliasMapping = recordMapping;
    aliasMapping.entityName = "Alias";
    aliasMapping.typeName = "app.Alias";
    const duplicate = registerMappings([recordMapping, aliasMapping].idup, [
        typeid(Record), typeid(Record)
    ]);
    assert(duplicate.error.code == Status.invalidArgument && duplicate.error.offset == 1);
    assert(duplicate.error.message == "duplicate JPA class identity");
    assert(duplicate.value.findEntity("Record") is null);
    assert(duplicate.value.findExactObject(new Record) is null);
}

@("a persistence unit resolves its canonical mappings by entity name and D type name")
unittest
{
    static immutable EntityMapping[] descriptors = [recordMapping];
    const registered = registerMappings(descriptors);
    assert(registered.ok);
    assert(registered.value.findEntity("Record") is &descriptors[0]);
    assert(registered.value.findType("flint.engine.jpa.mapping_test.Record") is &descriptors[0]);
    assert(registered.value.findEntity("record") is null);
    assert(registered.value.findType("Record") is null);
    assert(registered.value.findExactObject(new Record) is null);

    EntityMapping otherUnit = recordMapping;
    otherUnit.table = "other_records";
    const separate = registerMappings([otherUnit].idup);
    assert(separate.ok && separate.value.findEntity("Record").table == "other_records");
    assert(registered.value.findEntity("Record").table == "records");
}

@("registration rejects invalid or ambiguous mappings before publishing any entries")
unittest
{
    EntityMapping duplicate = recordMapping;
    duplicate.typeName = "flint.engine.jpa.mapping_test.OtherRecord";
    const duplicateEntity = registerMappings([recordMapping, duplicate].idup);
    assert(duplicateEntity.error.code == Status.invalidArgument && duplicateEntity.error.offset == 1);
    assert(duplicateEntity.error.message == "duplicate JPA entity name");
    assert(duplicateEntity.value.findEntity("Record") is null);

    duplicate = recordMapping;
    duplicate.entityName = "OtherRecord";
    const duplicateType = registerMappings([recordMapping, duplicate].idup);
    assert(duplicateType.error.code == Status.invalidArgument && duplicateType.error.offset == 1);
    assert(duplicateType.error.message == "duplicate JPA D type name");

    duplicate.typeName = "flint.engine.jpa.mapping_test.OtherRecord";
    const sharedTable = registerMappings([recordMapping, duplicate].idup);
    assert(sharedTable.ok && sharedTable.value.findEntity("OtherRecord").table == "records");

    duplicate.table = "";
    const invalid = registerMappings([recordMapping, duplicate].idup);
    assert(invalid.error.code == Status.invalidArgument && invalid.error.offset == 1);
    assert(invalid.value.findEntity("Record") is null);

    const empty = registerMappings([]);
    assert(empty.ok && empty.value.findEntity("Record") is null);
}

@("a mapping registry cannot retain stack storage")
unittest
{
    static assert(!__traits(compiles, () @safe {
            immutable(EntityMapping)[1] localMappings = [recordMapping];
            return registerMappings(localMappings[]);
        }));
}

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

@("managed row plans require a complete projection and a simple integer identity")
unittest
{
    assert(planManagedResult(&recordMapping, [ResultBinding(0, 3)], 0).ok);
    assert(planManagedResult(&recordMapping, [], 0).error.code == Status.invalidArgument);
    static immutable EntityMapping textId = EntityMapping("Record", "app.Record", "records",
            [AttributeMapping(0, "id", "id", AttributeKind.text, &readId, &writeId)],
            &constructRecord, [], &isExactRecordType, [0]);
    assert(planManagedResult(&textId, [ResultBinding(0, 1)], 0).error.code == Status.unsupported);
    static immutable EntityMapping composite = EntityMapping("Record", "app.Record", "records",
            [
                AttributeMapping(0, "id", "id", AttributeKind.integer, &readId, &writeId),
                AttributeMapping(1, "tenant", "tenant", AttributeKind.integer, &readId, &writeId)
    ], &constructRecord, [], &isExactRecordType, [0, 1]);
    assert(planManagedResult(&composite, [ResultBinding(0, 1), ResultBinding(1, 2)], 0)
            .error.code == Status.unsupported);
}

@("parameter plans validate positions independently of attribute ordinals")
unittest
{
    assert(planParameters(&recordMapping, [ParameterBinding(0, 2), ParameterBinding(0, 1)]).ok);
    assert(planParameters(null, [ParameterBinding(0, 1)]).error.code == Status.invalidArgument);
    assert(planParameters(&recordMapping, [ParameterBinding(1, 1)]).error.code == Status.invalidArgument);
    assert(planParameters(&recordMapping, [ParameterBinding(0, 0)]).error.code == Status.invalidArgument);
    const duplicate = planParameters(&recordMapping, [
        ParameterBinding(0, 1), ParameterBinding(0, 1)
    ]);
    assert(duplicate.error.code == Status.invalidArgument && duplicate.error.offset == 1);
    static assert(!__traits(compiles, ParameterBindingPlan(&recordMapping, [], null)));
}

@("typed parameter plans require a writer for the specific declared kind")
unittest
{
    import flint.engine.jpa : TypedColumnCodec;
    import flint.java.sql : PreparedStatement;

    static immutable EntityMapping timestamps = EntityMapping("Record",
            "flint.engine.jpa.mapping_test.Record", "records",
            [AttributeMapping(0, "id", "id", AttributeKind.timestamp, &readId, &writeId)],
            &constructRecord, [], &isExactRecordType, [0]);
    static void write(PreparedStatement, int, scope const ref AttributeValue)
    {
    }

    const dateOnly = TypedColumnCodec(write: &write);
    const withoutWriter = TypedColumnCodec(kinds: 1u << AttributeKind.timestamp);
    const timestampWriter = TypedColumnCodec(write: &write, kinds: 1u << AttributeKind.timestamp);
    assert(planParameters(&timestamps, [ParameterBinding(0, 1)], dateOnly).error.code == Status.invalidArgument);
    assert(planParameters(&timestamps, [ParameterBinding(0, 1)], withoutWriter).error.code == Status.invalidArgument);
    assert(planParameters(&timestamps, [ParameterBinding(0, 1)], timestampWriter).ok);
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

@("unsupported JDBC kinds identify the mapped attribute before query execution")
unittest
{
    EntityMapping mapping = recordMapping;
    auto attributes = mapping.attributes.dup;
    attributes[0].kind = AttributeKind.timestampWithOffset;
    mapping.attributes = attributes.idup;
    const offset = validateMapping(mapping);
    assert(offset.code == Status.unsupported && offset.offset == 0);
    assert(offset.message == "JDBC driver support for TIMESTAMP WITH TIME ZONE is unavailable");

    attributes[0].kind = AttributeKind.decimal;
    mapping.attributes = attributes.idup;
    const decimal = validateMapping(mapping);
    assert(decimal.code == Status.unsupported && decimal.offset == 0);
    assert(decimal.message == "JDBC driver support for NUMERIC is unavailable");
}

@("a date projection requires a typed reader at registration")
unittest
{
    static immutable EntityMapping dates = EntityMapping("Record", "flint.engine.jpa.mapping_test.Record", "records",
            [AttributeMapping(0, "id", "id", AttributeKind.date, &readId, &writeId)],
            &constructRecord, [], &isExactRecordType, [0]);
    const missing = planResult(&dates, [ResultBinding(0, 1)]);
    assert(missing.error.code == Status.invalidArgument && missing.error.offset == 0);
    assert(missing.error.message == "missing typed JDBC reader");
}

@("a timestamp projection requires an explicitly declared typed reader")
unittest
{
    import flint.engine.jpa : TypedColumnCodec;
    import flint.java.sql : ResultSet;

    static immutable EntityMapping timestamps = EntityMapping("Record",
            "flint.engine.jpa.mapping_test.Record", "records",
            [
                AttributeMapping(0, "id", "id", AttributeKind.integer, &readId, &writeId),
                AttributeMapping(1, "recordedAt", "recorded_at", AttributeKind.timestamp, &readId, &writeId)
    ], &constructRecord, [], &isExactRecordType, [0]);
    static immutable ResultBinding[] projection = [ResultBinding(1, 1), ResultBinding(0, 2)];
    static AttributeValue read(ResultSet, int, AttributeKind kind)
    {
        return AttributeValue(kind);
    }

    const dateOnly = TypedColumnCodec(&read, null);
    const missing = planResult(&timestamps, projection, dateOnly);
    assert(missing.error.code == Status.invalidArgument && missing.error.offset == 1);
    assert(missing.error.message == "missing typed JDBC reader");

    const explicitReader = TypedColumnCodec(read: &read, kinds: 1u << AttributeKind.timestamp);
    assert(planResult(&timestamps, projection, explicitReader).ok);

    const missingReader = TypedColumnCodec(kinds: 1u << AttributeKind.timestamp);
    assert(planResult(&timestamps, projection, missingReader).error.code == Status.invalidArgument);
}
