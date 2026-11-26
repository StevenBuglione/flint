/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// JDBC row materialization for immutable, provider-owned entity mappings.
module flint.engine.jpa.result_binding;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, validateEntity, validateMapping;
import flint.java.sql : ResultSet;

@safe:

/// Maps a JDBC projection position (one-based) to a persistent attribute ordinal (zero-based).
struct ResultBinding
{
    /// Zero-based index in EntityMapping.attributes.
    uint ordinal;
    /// One-based position in the JDBC result.
    int column;
}

/// A checked row layout. The mapping and bindings must have provider lifetime.
struct RowMaterializationPlan
{
    private immutable(EntityMapping)* mapping;
    private immutable(ResultBinding)[] bindings;
}

private alias PlanResult = Result!RowMaterializationPlan;
private alias RowResult = Result!Object;

/// Checks a complete entity projection before registering it for use.
PlanResult planResult(immutable(EntityMapping)* mapping, immutable(ResultBinding)[] bindings) nothrow @nogc
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
        foreach (ref previous; bindings[0 .. index])
            if (previous.ordinal == binding.ordinal)
                return PlanResult(RowMaterializationPlan.init, Error(Status.invalidArgument,
                        "duplicate result attribute ordinal", index));
    }
    return PlanResult(RowMaterializationPlan(mapping, bindings));
}

/// API boundary for JDBC getters and the entity constructor, writers and callbacks.
/// The caller owns the cursor and advances or closes it after this function returns.
RowResult materializeRow(scope const ref RowMaterializationPlan plan, ResultSet row)
{
    if (plan.mapping is null || row is null)
        return RowResult(null, Error(Status.invalidArgument, "missing materialization plan or row"));

    auto entity = plan.mapping.construct();
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return RowResult(null, error);

    foreach (ref binding; plan.bindings)
    {
        const attribute = &plan.mapping.attributes[binding.ordinal];
        AttributeValue value;
        value.kind = attribute.kind;
        final switch (value.kind)
        {
        case AttributeKind.integer:
            value.integer = row.getLong(binding.column);
            break;
        case AttributeKind.floatingPoint:
            value.floatingPoint = row.getDouble(binding.column);
            break;
        case AttributeKind.boolean:
            value.boolean = row.getBoolean(binding.column);
            break;
        case AttributeKind.text:
            value.text = row.getString(binding.column);
            break;
        case AttributeKind.binary:
            value.bytes = row.getBytes(binding.column);
            break;
        case AttributeKind.nullValue:
            return RowResult(null, Error(Status.invalidArgument,
                    "untyped result attribute", binding.ordinal));
        }
        if (row.wasNull())
        {
            if (!attribute.columnNullable || !attribute.acceptsNull)
                return RowResult(null, Error(Status.invalidArgument, "Cannot map SQL NULL to", binding.ordinal));
            value = AttributeValue.init;
        }
        // JDBC strings already survive cursor advancement. The writer must own any retained binary storage.
        attribute.write(entity, value);
    }
    foreach (callback; plan.mapping.postLoad)
        callback(entity);
    return RowResult(entity);
}
