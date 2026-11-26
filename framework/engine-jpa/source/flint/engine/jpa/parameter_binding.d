/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Checked entity write bindings and assigned-ID insertion at the JDBC boundary.
module flint.engine.jpa.parameter_binding;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, planLoadedSnapshot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, validateEntity, validateMapping;
import flint.engine.jpa.result_binding : TypedColumnCodec, TypedColumnWriter;
import flint.java.sql : Connection, PreparedStatement, Types;

@safe:

/// Maps a one-based JDBC parameter to a zero-based persistent attribute.
struct ParameterBinding
{
    /// Index in EntityMapping.attributes.
    uint ordinal;
    /// Position in the prepared SQL statement.
    int parameter;
}

/// Checked bindings backed by immutable provider-lifetime metadata.
struct ParameterBindingPlan
{
    private immutable(EntityMapping)* mapping;
    private immutable(ParameterBinding)[] bindings;
    private TypedColumnWriter writeTyped;

    private this(immutable(EntityMapping)* mapping, immutable(ParameterBinding)[] bindings,
            TypedColumnWriter writeTyped) nothrow @nogc
    {
        this.mapping = mapping;
        this.bindings = bindings;
        this.writeTyped = writeTyped;
    }
}

private alias PlanResult = Result!ParameterBindingPlan;

/// Validates the bindings and required typed JDBC writers before statement use.
PlanResult planParameters(immutable(EntityMapping)* mapping, immutable(ParameterBinding)[] bindings,
        TypedColumnCodec typed = TypedColumnCodec.init) nothrow @nogc
{
    if (mapping is null)
        return PlanResult(ParameterBindingPlan.init, Error(Status.invalidArgument, "missing entity mapping"));
    const error = validateMapping(*mapping);
    if (error.code != Status.ok)
        return PlanResult(ParameterBindingPlan.init, error);

    foreach (index, ref binding; bindings)
    {
        if (binding.ordinal >= mapping.attributes.length || binding.parameter < 1)
            return PlanResult(ParameterBindingPlan.init, Error(Status.invalidArgument,
                    "invalid parameter binding", index));
        const kind = mapping.attributes[binding.ordinal].kind;
        if ((kind == AttributeKind.date || kind == AttributeKind.timestamp) && (typed.write is null
                || (typed.kinds & (1u << kind)) == 0))
            return PlanResult(ParameterBindingPlan.init, Error(Status.invalidArgument,
                    "missing typed JDBC writer", binding.ordinal));
        foreach (ref previous; bindings[0 .. index])
            if (previous.parameter == binding.parameter)
                return PlanResult(ParameterBindingPlan.init, Error(Status.invalidArgument,
                        "duplicate JDBC parameter position", index));
    }
    return PlanResult(ParameterBindingPlan(mapping, bindings, typed.write));
}

/// Binds an entity at the JDBC boundary. The caller executes after success and discards the statement on failure.
Error bindParameters(scope const ref ParameterBindingPlan plan, PreparedStatement statement, Object entity)
{
    if (plan.mapping is null || statement is null)
        return Error(Status.invalidArgument, "missing parameter plan or statement");
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return error;
    return bindMappedValues(plan, statement, entity);
}

/// Binds after the provider has type-checked the entity against this plan's exact mapping.
package Error bindMappedValues(scope const ref ParameterBindingPlan plan, PreparedStatement statement,
        Object entity, const(AttributeValue)[] captured = null)
{
    foreach (ref binding; plan.bindings)
    {
        const attribute = &plan.mapping.attributes[binding.ordinal];
        AttributeValue value;
        if (captured.length == 0)
        {
            const read = attribute.read(entity);
            if (!read.ok)
                return Error(read.error.code, read.error.message, binding.ordinal);
            value = read.value;
        }
        else
            value = captured[binding.ordinal];
        if (value.kind == AttributeKind.nullValue)
        {
            if (!attribute.columnNullable || !attribute.acceptsNull)
                return Error(Status.invalidArgument, "cannot bind SQL NULL from attribute", binding.ordinal);
            statement.setNull(binding.parameter, attribute.sqlType);
            continue;
        }
        if (value.kind != attribute.kind)
            return Error(Status.invalidArgument, "parameter reader returned an invalid value", binding.ordinal);

        const status = bindValue(statement, binding.parameter, value, plan.writeTyped);
        if (status != Status.ok)
            return Error(status, "parameter reader returned an invalid value", binding.ordinal);
    }
    return Error.init;
}

private Status bindValue(PreparedStatement statement, int parameter, const ref AttributeValue value,
        scope TypedColumnWriter writeTyped)
{
    switch (value.kind)
    {
    case AttributeKind.integer:
        statement.setLong(parameter, value.integer);
        break;
    case AttributeKind.floatingPoint:
        statement.setDouble(parameter, value.floatingPoint);
        break;
    case AttributeKind.boolean:
        statement.setBoolean(parameter, value.boolean);
        break;
    case AttributeKind.text:
        if (value.text is null)
            return Status.invalidArgument;
        statement.setString(parameter, value.text);
        break;
    case AttributeKind.binary:
        if (value.bytes is null)
            return Status.invalidArgument;
        // The JDBC adapter copies the bytes before retaining them in the statement.
        statement.setBytes(parameter, value.bytes);
        break;
    case AttributeKind.date:
    case AttributeKind.timestamp:
        writeTyped(statement, parameter, value);
        break;
    default:
        return Status.unsupported;
    }
    return Status.ok;
}

/// Provider-compiled SQL and verified bindings for an assigned-key INSERT.
struct InsertPlan
{
    private string sql;
    private ParameterBindingPlan parameters;
    private LoadedSnapshotPlan snapshot;

    private this(string sql, ParameterBindingPlan plan, LoadedSnapshotPlan snapshot) nothrow @nogc
    {
        this.sql = sql;
        this.parameters = plan;
        this.snapshot = snapshot;
    }
}

private alias InsertPlanResult = Result!InsertPlan;

/// Checks contiguous parameter positions and exactly one binding per insertable attribute.
/// An optional BIGINT version is supplied by the entity.
InsertPlanResult planInsert(immutable(EntityMapping)* mapping, string sql,
        immutable(ParameterBinding)[] bindings, TypedColumnCodec typed = TypedColumnCodec()) nothrow @nogc
{
    const parameters = planParameters(mapping, bindings, typed);
    if (!parameters.ok)
        return InsertPlanResult(InsertPlan.init, parameters.error);
    if (sql.length == 0)
        return InsertPlanResult(InsertPlan.init, Error(Status.invalidArgument, "missing static insert SQL"));
    const layout = validateInsertLayout(*mapping, bindings);
    if (layout.code != Status.ok)
        return InsertPlanResult(InsertPlan.init, layout);
    const snapshot = planLoadedSnapshot(mapping);
    if (!snapshot.ok)
        return InsertPlanResult(InsertPlan.init, snapshot.error);
    return InsertPlanResult(InsertPlan(sql, parameters.value, snapshot.value));
}

private Error validateInsertLayout(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] parameterBindings) nothrow @nogc
{
    if (mapping.generatesId || mapping.idOrdinals.length != 1)
        return Error(Status.unsupported, "static inserts require an assigned integer key");
    const key = &mapping.attributes[mapping.idOrdinals[0]];
    if (!key.insertable || key.kind != AttributeKind.integer)
        return Error(Status.unsupported, "static inserts require an insertable integer key", key.ordinal);
    if (mapping.versionOrdinal != uint.max)
    {
        const revision = &mapping.attributes[mapping.versionOrdinal];
        if (!revision.insertable || revision.kind != AttributeKind.integer || revision.sqlType != Types.BIGINT)
            return Error(Status.unsupported, "versioned inserts require an initial BIGINT version", revision.ordinal);
    }
    return validateInsertBindings(mapping, parameterBindings);
}

private Error validateInsertBindings(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] parameterBindings) nothrow @nogc
{
    size_t count;
    foreach (ref attribute; mapping.attributes)
        count += attribute.insertable;
    if (parameterBindings.length != count)
        return Error(Status.invalidArgument, "incomplete static insert layout");

    foreach (index, ref binding; parameterBindings)
    {
        if (!mapping.attributes[binding.ordinal].insertable || cast(size_t) binding.parameter > count)
            return Error(Status.invalidArgument, "invalid static insert binding", index);
        foreach (ref previous; parameterBindings[0 .. index])
            if (previous.ordinal == binding.ordinal)
                return Error(Status.invalidArgument, "duplicate static insert attribute", index);
    }
    return Error.init;
}

/// Stages a baseline and publishes the identity after one inserted row and successful statement close.
/// The caller reserves value scratch and owns commit or rollback, including retirement after rollback.
Error executeManagedInsert(const ref InsertPlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key, Object entity, AttributeValue[] values)
{
    const mapping = plan.parameters.mapping;
    if (mapping is null || connection is null)
        return Error(Status.invalidArgument, "missing insert plan or connection");
    const count = mapping.attributes.length;
    if (values.length < count)
        return Error(Status.resourceExhausted, "insufficient insert value slots");
    if (connection.getAutoCommit())
        return Error(Status.invalidArgument, "managed insert requires a JDBC transaction");

    auto captured = values[0 .. count];
    scope (exit)
        captured[] = AttributeValue.init;
    const staged = entities.stageInsert(key, plan.snapshot, entity, captured);
    if (!staged.ok)
        return staged.error;
    scope (exit)
        entities.cancelInsert(staged.value);

    const initial = checkInsertedValues(*mapping, key.identifier, captured);
    if (initial.code != Status.ok)
        return initial;
    const executed = insertRow(plan, connection, captured);
    if (executed.code != Status.ok)
        return executed;
    return entities.publishInsert(staged.value, entity);
}

private Error checkInsertedValues(scope const ref EntityMapping mapping, long identifier,
        scope const(AttributeValue)[] captured) pure nothrow @nogc
{
    const ordinal = mapping.idOrdinals[0];
    if (captured[ordinal].kind != AttributeKind.integer || captured[ordinal].integer != identifier)
        return Error(Status.invalidArgument, "inserted entity identifier differs from its key", ordinal);
    const revision = mapping.versionOrdinal;
    if (revision != uint.max && captured[revision].kind != AttributeKind.integer)
        return Error(Status.invalidArgument, "inserted entity version is not an integer", revision);
    return Error.init;
}

private Error insertRow(const ref InsertPlan plan, Connection connection, const(AttributeValue)[] captured)
{
    auto statement = connection.prepareStatement(plan.sql);
    scope (exit)
        statement.close();
    const bound = bindMappedValues(plan.parameters, statement, null, captured);
    if (bound.code != Status.ok)
        return bound;
    if (statement.executeUpdate() != 1)
        return Error(Status.ioError, "managed insert affected an unexpected number of rows");
    return Error.init;
}
