/*
 * Ported from hibernate-orm 7.1.0: hibernate-core/src/main/java/org/hibernate/persister/entity/mutation/UpdateCoordinatorStandard.java,
 * hibernate-core/src/main/java/org/hibernate/event/internal/DefaultFlushEntityEventListener.java
 * and hibernate-core/src/main/java/org/hibernate/engine/jdbc/mutation/internal/ModelMutationHelper.java.
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 * Modified by the Flint authors: precompiled static SQL and resource-local JDBC with engine status results.
 */

/// Checked static updates for managed entities with a simple integer key.
module flint.engine.jpa.update;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, EntityMapping;
import flint.engine.jpa.parameter_binding : ParameterBinding, ParameterBindingPlan, bindMappedValues, planParameters;
import flint.engine.jpa.result_binding : TypedColumnCodec;
import flint.java.sql : Connection;

@safe:

/// Startup-validated bindings and provider-compiled SQL for one unversioned entity table.
struct UpdatePlan
{
    private immutable(EntityMapping)* mapping;
    private string sql;
    private ParameterBindingPlan parameters;
    private int keySlot;

    private this(immutable(EntityMapping)* mapping, string sql, ParameterBindingPlan plan, int keySlot) nothrow @nogc
    {
        this.mapping = mapping;
        this.sql = sql;
        this.parameters = plan;
        this.keySlot = keySlot;
    }
}

private alias PlanResult = Result!UpdatePlan;
private alias UpdateResult = Result!bool;

/// Checks full coverage of updatable non-key fields and a distinct slot for the integer key.
/// The provider supplies the corresponding compiled single-table UPDATE SQL.
PlanResult planUpdate(immutable(EntityMapping)* mapping, string sql,
        immutable(ParameterBinding)[] changes, int keySlot, TypedColumnCodec typed = TypedColumnCodec()) nothrow @nogc
{
    const parameters = planParameters(mapping, changes, typed);
    if (!parameters.ok)
        return PlanResult(UpdatePlan.init, parameters.error);
    if (sql.length == 0)
        return PlanResult(UpdatePlan.init, Error(Status.invalidArgument, "missing static update SQL"));
    if (mapping.versionOrdinal != uint.max || mapping.idOrdinals.length != 1
            || mapping.attributes[mapping.idOrdinals[0]].kind != AttributeKind.integer)
        return PlanResult(UpdatePlan.init, Error(Status.unsupported,
                "static updates require an unversioned entity with a simple integer key"));
    const layout = validateUpdateLayout(*mapping, changes, mapping.idOrdinals[0], keySlot);
    if (layout.code != Status.ok)
        return PlanResult(UpdatePlan.init, layout);
    return PlanResult(UpdatePlan(mapping, sql, parameters.value, keySlot));
}

private Error validateUpdateLayout(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] changes, uint id, int keySlot) nothrow @nogc
{
    size_t writable;
    foreach (ref attribute; mapping.attributes)
        writable += attribute.updatable && attribute.ordinal != id;
    if (writable == 0 || changes.length != writable || keySlot < 1 || cast(size_t) keySlot > writable + 1)
        return Error(Status.invalidArgument, "incomplete static update layout");

    foreach (index, ref change; changes)
    {
        if (change.ordinal == id || !mapping.attributes[change.ordinal].updatable
                || change.parameter == keySlot || cast(size_t) change.parameter > writable + 1)
            return Error(Status.invalidArgument, "invalid static update binding", index);
        foreach (ref previous; changes[0 .. index])
            if (previous.ordinal == change.ordinal)
                return Error(Status.invalidArgument, "duplicate static update attribute", index);
    }
    return Error.init;
}

/// Returns true after one updated row and false for a clean entity. The caller owns the transaction and
/// must roll back on failure. This operation leaves the loaded baseline in place for transaction handling.
UpdateResult executeManagedUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key, scope uint[] dirtyOrdinals)
{
    if (plan.mapping is null || connection is null)
        return UpdateResult(false, Error(Status.invalidArgument, "missing update plan or connection"));

    Object entity;
    const dirty = entities.dirtyTarget(key, plan.mapping, dirtyOrdinals, entity);
    if (!dirty.ok)
        return UpdateResult(false, dirty.error);

    const identifier = checkIdentifier(*plan.mapping, entity, key.identifier);
    if (identifier.code != Status.ok)
        return UpdateResult(false, identifier);
    if (dirty.value == 0)
        return UpdateResult(false);
    if (connection.getAutoCommit())
        return UpdateResult(false, Error(Status.invalidArgument, "managed update requires a JDBC transaction"));

    auto statement = connection.prepareStatement(plan.sql);
    scope (exit)
        statement.close();
    const bound = bindMappedValues(plan.parameters, statement, entity);
    if (bound.code != Status.ok)
        return UpdateResult(false, bound);

    statement.setLong(plan.keySlot, key.identifier);
    const affected = statement.executeUpdate();
    if (affected == 0)
        return UpdateResult(false, Error(Status.conflict, "managed update row is missing"));
    if (affected != 1)
        return UpdateResult(false, Error(Status.ioError, "managed update affected an unexpected number of rows"));
    return UpdateResult(true);
}

private Error checkIdentifier(scope const ref EntityMapping mapping, Object entity, long identifier) nothrow @nogc
{
    const id = mapping.idOrdinals[0];
    const current = mapping.attributes[id].read(entity);
    if (!current.ok)
        return Error(current.error.code, current.error.message, id);
    if (current.value.kind != AttributeKind.integer || current.value.integer != identifier)
        return Error(Status.invalidArgument, "managed entity identifier changed", id);
    return Error.init;
}
