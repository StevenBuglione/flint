/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Binding of compiled entity attributes to JDBC statement parameters.
module flint.engine.jpa.parameter_binding;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, validateEntity, validateMapping;
import flint.engine.jpa.result_binding : TypedColumnCodec, TypedColumnWriter;
import flint.java.sql : PreparedStatement;

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
