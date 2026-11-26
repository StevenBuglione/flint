/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// JDBC row materialization for immutable, provider-owned entity mappings.
module flint.engine.jpa.result_binding;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, planLoadedSnapshot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, validateEntity, validateMapping;
import flint.java.sql : PreparedStatement, ResultSet;

@safe:

/// Maps a JDBC projection position (one-based) to a persistent attribute ordinal (zero-based).
struct ResultBinding
{
    /// Zero-based index in EntityMapping.attributes.
    uint ordinal;
    /// One-based position in the JDBC result.
    int column;
}

/// Reads an application-linked typed JDBC column at the API boundary.
alias TypedColumnReader = AttributeValue function(ResultSet, int, AttributeKind) @safe;

/// Writes an application-linked typed JDBC parameter at the API boundary.
alias TypedColumnWriter = void function(PreparedStatement, int, scope const ref AttributeValue) @safe;

/// JDBC conversions shared by the generated plans in one application unit.
struct TypedColumnCodec
{
    /// Reads the supported typed kinds from a JDBC result.
    TypedColumnReader read;
    /// Binds the supported typed kinds to a JDBC statement.
    TypedColumnWriter write;
    /// The kinds handled by the codec, one bit per AttributeKind, shared by its reader and writer.
    uint kinds = 1u << AttributeKind.date;
}

static assert(cast(uint) AttributeKind.max < uint.sizeof * 8);

/// A checked row layout. The mapping and bindings must have provider lifetime.
struct RowMaterializationPlan
{
    private immutable(EntityMapping)* mapping;
    private immutable(ResultBinding)[] bindings;
    private TypedColumnReader readTyped;
}

/// A concrete row layout with a pre-resolved, signed integer primary-key projection.
struct ManagedRowMaterializationPlan
{
    private RowMaterializationPlan row;
    private LoadedSnapshotPlan snapshot;
    private uint root;
    private ResultBinding identity;

    private this(RowMaterializationPlan row, LoadedSnapshotPlan loaded, uint root, ResultBinding identity) nothrow @nogc
    {
        this.row = row;
        this.snapshot = loaded;
        this.root = root;
        this.identity = identity;
    }
}

private alias PlanResult = Result!RowMaterializationPlan;
private alias ManagedPlanResult = Result!ManagedRowMaterializationPlan;
private alias RowResult = Result!Object;

/// Checks a complete entity projection before registering it for use.
PlanResult planResult(immutable(EntityMapping)* mapping, immutable(ResultBinding)[] bindings,
        TypedColumnCodec typed = TypedColumnCodec.init) nothrow @nogc
{
    if (mapping is null)
        return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument, "missing entity mapping"));
    const error = validateMapping(*mapping);
    if (error.code != Status.ok)
        return PlanResult(RowMaterializationPlan.init, error);
    if (bindings.length != mapping.attributes.length)
        return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument, "incomplete entity projection"));

    foreach (index, ref binding; bindings)
    {
        if (binding.ordinal >= mapping.attributes.length || binding.column < 1)
            return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument,
                    "invalid result binding", index));
        const kind = mapping.attributes[binding.ordinal].kind;
        if ((kind == AttributeKind.date || kind == AttributeKind.timestamp) && (typed.read is null
                || (typed.kinds & (1u << kind)) == 0))
            return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument,
                    "missing typed JDBC reader", binding.ordinal));
        foreach (ref previous; bindings[0 .. index])
            if (previous.ordinal == binding.ordinal)
                return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument,
                        "duplicate result attribute ordinal", index));
    }
    return PlanResult(RowMaterializationPlan(mapping, bindings, typed.read));
}

/// Resolves the identity column at startup. The provider assigns a root mapping ordinal per inheritance root.
ManagedPlanResult planManagedResult(immutable(EntityMapping)* mapping,
        immutable(ResultBinding)[] bindings, uint root, TypedColumnCodec typed = TypedColumnCodec.init) nothrow @nogc
{
    const plan = planResult(mapping, bindings, typed);
    if (!plan.ok)
        return ManagedPlanResult(ManagedRowMaterializationPlan.init, plan.error);
    if (mapping.idOrdinals.length != 1 || mapping.attributes[mapping.idOrdinals[0]].kind != AttributeKind.integer)
        return ManagedPlanResult(ManagedRowMaterializationPlan.init, Error(Status.unsupported,
                "managed rows require a simple integer identity"));
    const id = mapping.idOrdinals[0];
    foreach (ref binding; bindings)
    {
        if (binding.ordinal != id)
            continue;
        const snapshot = planLoadedSnapshot(mapping);
        if (!snapshot.ok)
            return ManagedPlanResult(ManagedRowMaterializationPlan.init, snapshot.error);
        return ManagedPlanResult(ManagedRowMaterializationPlan(plan.value, snapshot.value, root, binding));
    }
    return ManagedPlanResult(ManagedRowMaterializationPlan.init, Error(Status.invalidArgument,
            "missing identity projection", id));
}

/// API boundary for JDBC getters and the entity constructor, writers and callbacks.
/// The caller owns the cursor and advances or closes it after this function returns.
RowResult materializeRow(scope const ref RowMaterializationPlan plan, ResultSet row)
{
    if (plan.mapping is null || row is null)
        return RowResult(null, Error(Status.invalidArgument, "missing materialization plan or row"));
    return hydrateRow!false(plan, row);
}

/// Resolves a managed identity before hydration. The caller owns the cursor and supplies the current context.
/// A captured baseline retains the immutable mapping for the life of its managed slot.
RowResult materializeManagedRow(const ref ManagedRowMaterializationPlan plan, ResultSet row,
        scope ref ManagedEntities entities)
{
    if (plan.row.mapping is null || row is null)
        return RowResult(null, Error(Status.invalidArgument, "missing managed materialization plan or row"));
    const identifier = row.getLong(plan.identity.column);
    if (row.wasNull())
        return RowResult(null, Error(Status.invalidArgument, "Cannot map SQL NULL to", plan.identity.ordinal));
    const key = EntityIdentity(plan.root, identifier);
    auto existing = entities.find(key);
    if (existing.ok)
    {
        const error = validateEntity(*plan.row.mapping, existing.value);
        return error.code == Status.ok ? existing : RowResult(null, error);
    }

    auto loaded = hydrateRow!true(plan.row, row, plan.identity.ordinal, identifier);
    if (!loaded.ok)
        return loaded;
    const error = entities.manage(key, loaded.value, plan.snapshot);
    if (error.code != Status.ok)
        return RowResult(null, error);
    scope (failure)
    {
        // A callback can detach or replace the current instance before it throws.
        const current = entities.find(key);
        if (current.ok && current.value is loaded.value)
            entities.detach(key);
    }
    notifyPostLoad(*plan.row.mapping, loaded.value);
    return loaded;
}

private RowResult hydrateRow(bool managed)(scope const ref RowMaterializationPlan plan, ResultSet row,
        uint idOrdinal = uint.max, long identifier = 0)
{
    auto entity = plan.mapping.construct();
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return RowResult(null, error);

    foreach (ref binding; plan.bindings)
    {
        const attribute = &plan.mapping.attributes[binding.ordinal];
        static if (managed)
        {
            if (binding.ordinal == idOrdinal)
            {
                const value = AttributeValue(AttributeKind.integer, identifier);
                attribute.write(entity, value);
                continue;
            }
        }
        auto value = readColumn(row, binding.column, attribute.kind, plan.readTyped);
        if (row.wasNull())
        {
            if (!attribute.columnNullable || !attribute.acceptsNull)
                return RowResult(null, Error(Status.invalidArgument, "Cannot map SQL NULL to", binding.ordinal));
            value = AttributeValue.init;
        }
        else if (value.kind != attribute.kind)
            return RowResult(null, Error(Status.invalidArgument,
                    "typed JDBC reader returned the wrong kind", binding.ordinal));
        // JDBC strings already survive cursor advancement. The writer must own any retained binary storage.
        attribute.write(entity, value);
    }
    static if (!managed)
        notifyPostLoad(*plan.mapping, entity);
    return RowResult(entity);
}

private void notifyPostLoad(scope const ref EntityMapping mapping, Object entity)
{
    foreach (callback; mapping.postLoad)
        callback(entity);
}

private AttributeValue readColumn(ResultSet row, int column, AttributeKind kind, scope TypedColumnReader readTyped)
{
    AttributeValue value;
    value.kind = kind;
    final switch (value.kind)
    {
    case AttributeKind.integer:
        value.integer = row.getLong(column);
        break;
    case AttributeKind.floatingPoint:
        value.floatingPoint = row.getDouble(column);
        break;
    case AttributeKind.boolean:
        value.boolean = row.getBoolean(column);
        break;
    case AttributeKind.text:
        value.text = row.getString(column);
        break;
    case AttributeKind.binary:
        value.bytes = row.getBytes(column);
        break;
    case AttributeKind.date:
    case AttributeKind.timestamp:
        return readTyped(row, column, kind);
    case AttributeKind.time:
    case AttributeKind.timestampWithOffset:
    case AttributeKind.decimal:
    case AttributeKind.nullValue:
        return AttributeValue.init;
    }
    return value;
}
