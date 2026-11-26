/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Checked entity write bindings and single-table insertion at the JDBC boundary.
module flint.engine.jpa.parameter_binding;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, planLoadedSnapshot, readMapped;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, validateEntity, validateMapping;
import flint.engine.jpa.result_binding : TypedColumnCodec, TypedColumnWriter;
import flint.jakarta.persistence : GenerationType;
import flint.java.sql : Connection, PreparedStatement, ResultSet, Types;

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

/// Provider-compiled SQL and verified bindings for a single-table INSERT.
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
    return buildInsertPlan(mapping, sql, bindings, typed, false);
}

/// Checks an INSERT whose sole BIGINT key is produced by the database's IDENTITY column.
InsertPlanResult planIdentityInsert(immutable(EntityMapping)* mapping, string sql,
        immutable(ParameterBinding)[] bindings, TypedColumnCodec typed = TypedColumnCodec()) nothrow @nogc
{
    return buildInsertPlan(mapping, sql, bindings, typed, true);
}

private InsertPlanResult buildInsertPlan(immutable(EntityMapping)* mapping, string sql,
        immutable(ParameterBinding)[] bindings, TypedColumnCodec typed, bool generated) nothrow @nogc
{
    const parameters = planParameters(mapping, bindings, typed);
    if (!parameters.ok)
        return InsertPlanResult(InsertPlan.init, parameters.error);
    if (sql.length == 0)
        return InsertPlanResult(InsertPlan.init, Error(Status.invalidArgument, "missing static insert SQL"));
    const layout = validateInsertLayout(*mapping, bindings, generated);
    if (layout.code != Status.ok)
        return InsertPlanResult(InsertPlan.init, layout);
    const snapshot = planLoadedSnapshot(mapping);
    if (!snapshot.ok)
        return InsertPlanResult(InsertPlan.init, snapshot.error);
    return InsertPlanResult(InsertPlan(sql, parameters.value, snapshot.value));
}

private Error validateInsertLayout(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] parameterBindings, bool generated) nothrow @nogc
{
    const keyError = validateInsertKey(mapping, generated);
    if (keyError.code != Status.ok)
        return keyError;
    if (mapping.versionOrdinal != uint.max)
    {
        const revision = &mapping.attributes[mapping.versionOrdinal];
        if (!revision.insertable || revision.kind != AttributeKind.integer || revision.sqlType != Types.BIGINT)
            return Error(Status.unsupported, "versioned inserts require an initial BIGINT version", revision.ordinal);
    }
    const skipped = generated ? mapping.idOrdinals[0] : uint.max;
    return validateInsertBindings(mapping, parameterBindings, skipped);
}

private Error validateInsertKey(scope const ref EntityMapping mapping, bool generated) pure nothrow @nogc
{
    if (mapping.idOrdinals.length != 1 || mapping.generatesId != generated)
        return Error(Status.unsupported, "insert plan does not match the identifier strategy");
    const key = &mapping.attributes[mapping.idOrdinals[0]];
    if (generated)
    {
        if (mapping.generationStrategy != GenerationType.IDENTITY
                || key.kind != AttributeKind.integer || key.sqlType != Types.BIGINT)
            return Error(Status.unsupported, "generated inserts require a BIGINT IDENTITY key", key.ordinal);
    }
    else if (!key.insertable || key.kind != AttributeKind.integer)
        return Error(Status.unsupported, "static inserts require an insertable integer key", key.ordinal);
    return Error.init;
}

private Error validateInsertBindings(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] parameterBindings, uint skipped) nothrow @nogc
{
    size_t count;
    foreach (ref attribute; mapping.attributes)
        count += attribute.insertable && attribute.ordinal != skipped;
    if (parameterBindings.length != count)
        return Error(Status.invalidArgument, "incomplete static insert layout");

    foreach (index, ref binding; parameterBindings)
    {
        if (binding.ordinal == skipped || !mapping.attributes[binding.ordinal].insertable
                || cast(size_t) binding.parameter > count)
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
    if (mapping is null || connection is null || mapping.generatesId)
        return Error(Status.invalidArgument, "missing assigned insert plan or connection");
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
    return checkInitialVersion(mapping.versionOrdinal, captured);
}

private Error checkInitialVersion(uint revision, scope const(AttributeValue)[] capturedAttributes) pure nothrow @nogc
{
    if (revision != uint.max && capturedAttributes[revision].kind != AttributeKind.integer)
        return Error(Status.invalidArgument, "inserted entity version is not an integer", revision);
    return Error.init;
}

private Error insertRow(const ref InsertPlan plan, Connection connection, const(AttributeValue)[] captured)
{
    auto statement = connection.prepareStatement(plan.sql);
    scope (exit)
        statement.close();
    return executeInsertStatement(plan.parameters, statement, captured);
}

private Error executeInsertStatement(scope const ref ParameterBindingPlan parameters,
        PreparedStatement statement, const(AttributeValue)[] captured)
{
    const bound = bindMappedValues(parameters, statement, null, captured);
    if (bound.code != Status.ok)
        return bound;
    if (statement.executeUpdate() != 1)
        return Error(Status.ioError, "managed insert affected an unexpected number of rows");
    return Error.init;
}

private alias GeneratedKeyResult = Result!long;

/// Reads one non-NULL integer from a generated-keys cursor positioned before its first row.
/// The caller owns the cursor and closes it after this operation.
GeneratedKeyResult readGeneratedIntegerKey(ResultSet keys)
{
    if (keys is null || !keys.next())
        return GeneratedKeyResult(0, Error(Status.ioError, "generated key result has no row"));
    auto metadata = keys.getMetaData();
    if (metadata is null || metadata.getColumnCount() != 1)
        return GeneratedKeyResult(0, Error(Status.invalidArgument, "expected one generated key column"));
    const kind = metadata.getColumnType(1);
    if (kind != Types.BIGINT && kind != Types.INTEGER && kind != Types.SMALLINT && kind != Types.TINYINT)
        return GeneratedKeyResult(0, Error(Status.invalidArgument, "generated key is not an integer"));
    const identifier = keys.getLong(1);
    if (keys.wasNull() || keys.next())
        return GeneratedKeyResult(0, Error(Status.ioError, "expected one non-NULL generated key"));
    return GeneratedKeyResult(identifier);
}

/// Inserts using the provider's stable, one-column key-name array and reserves identity capacity before SQL.
/// Complete rollback and detach affected state through the caller's transaction.
GeneratedKeyResult executeIdentityInsert(const ref InsertPlan plan, Connection connection,
        scope ref ManagedEntities entities, uint root, Object entity, AttributeValue[] values, string[] columns)
{
    const mapping = plan.parameters.mapping;
    const checked = validateIdentityArguments(mapping, connection, values.length, columns);
    if (checked.code != Status.ok)
        return GeneratedKeyResult(0, checked);

    auto captured = values[0 .. mapping.attributes.length];
    scope (exit)
        captured[] = AttributeValue.init;
    const reserved = entities.reserveIdentityInsert(entity);
    if (!reserved.ok)
        return GeneratedKeyResult(0, reserved.error);
    scope (exit)
        entities.cancelInsert(reserved.value);

    const initial = collectIdentityInput(*mapping, entity, captured);
    if (initial.code != Status.ok)
        return GeneratedKeyResult(0, initial);
    const written = insertGeneratedRow(plan, connection, captured, columns);
    if (!written.ok)
        return written;

    const ordinal = mapping.idOrdinals[0];
    captured[ordinal] = AttributeValue(AttributeKind.integer, written.value);
    const key = EntityIdentity(root, written.value);
    const staged = entities.stageIdentityInsert(reserved.value, key, plan.snapshot, captured);
    if (staged.code != Status.ok)
        return GeneratedKeyResult(0, staged);
    mapping.attributes[ordinal].write(entity, captured[ordinal]);
    const published = entities.publishInsert(reserved.value, entity);
    return GeneratedKeyResult(written.value, published);
}

private Error validateIdentityArguments(scope immutable(EntityMapping)* mapping,
        Connection connection, size_t valueCount, scope const(string)[] columns)
{
    if (mapping is null || connection is null || !mapping.generatesId)
        return Error(Status.invalidArgument, "missing IDENTITY insert plan or connection");
    if (valueCount < mapping.attributes.length)
        return Error(Status.resourceExhausted, "insufficient insert value slots");
    if (columns.length != 1 || columns[0] != mapping.attributes[mapping.idOrdinals[0]].column)
        return Error(Status.invalidArgument, "missing or mismatched generated key column name");
    if (connection.getAutoCommit())
        return Error(Status.invalidArgument, "managed insert requires a JDBC transaction");
    return Error.init;
}

private Error collectIdentityInput(scope const ref EntityMapping mapping, Object entity,
        scope AttributeValue[] capturedAttributes) nothrow @nogc
{
    const checked = validateEntity(mapping, entity);
    if (checked.code != Status.ok)
        return checked;
    const id = mapping.idOrdinals[0];
    foreach (ref attribute; mapping.attributes)
    {
        if (attribute.ordinal == id)
            continue;
        const value = readMapped(attribute, entity);
        if (!value.ok)
            return value.error;
        capturedAttributes[attribute.ordinal] = value.value;
    }
    return checkInitialVersion(mapping.versionOrdinal, capturedAttributes);
}

private GeneratedKeyResult insertGeneratedRow(const ref InsertPlan plan, Connection connection,
        const(AttributeValue)[] captured, string[] columns)
{
    auto statement = connection.prepareStatement(plan.sql, columns);
    scope (exit)
        statement.close();
    const written = executeInsertStatement(plan.parameters, statement, captured);
    if (written.code != Status.ok)
        return GeneratedKeyResult(0, written);

    auto keys = statement.getGeneratedKeys();
    scope (exit)
        if (keys !is null)
            keys.close();
    return readGeneratedIntegerKey(keys);
}

/// Checks scratch and plan shape before the batch starts any writes.
package Error checkInsertScratch(scope const ref InsertPlan plan, size_t valueSlots, size_t keySlots) pure nothrow @nogc
{
    const mapping = plan.parameters.mapping;
    if (mapping is null)
        return Error(Status.invalidArgument, "unplanned insert action");
    if (valueSlots < mapping.attributes.length)
        return Error(Status.resourceExhausted, "insufficient insert value slots");
    if (mapping.generatesId && keySlots != 1)
        return Error(Status.invalidArgument, "IDENTITY actions require one key-name slot");
    return Error.init;
}

/// Dispatches a checked action, reusing the value and key-name buffers until JDBC finishes.
package Error executeScheduledInsert(const ref InsertPlan plan, Connection connection,
        scope ref ManagedEntities managed, EntityIdentity key, Object entity, AttributeValue[] values, string[] columns)
{
    const mapping = plan.parameters.mapping;
    if (!mapping.generatesId)
        return executeManagedInsert(plan, connection, managed, key, entity, values);
    columns[0] = mapping.attributes[mapping.idOrdinals[0]].column;
    scope (exit)
        columns[0] = null;
    return executeIdentityInsert(plan, connection, managed, key.root, entity, values, columns).error;
}
