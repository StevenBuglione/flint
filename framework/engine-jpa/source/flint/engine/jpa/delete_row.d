/*
 * Ported from hibernate-orm 7.1.0: hibernate-core/src/main/java/org/hibernate/persister/entity/mutation/AbstractDeleteCoordinator.java
 * and hibernate-core/src/main/java/org/hibernate/engine/jdbc/mutation/internal/ModelMutationHelper.java.
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 * Modified by the Flint authors: precompiled single-table SQL and explicit persistence-context retirement.
 */

/// Checked single-table deletes for managed entities with integer keys.
module flint.engine.jpa.delete_row;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.managed_entities : ManagedEntities, ManagedTarget;
import flint.engine.jpa.mapping : AttributeKind, EntityMapping, checkIdentifier, validateEntity, validateMapping;
import flint.java.sql : Connection, Types;

@safe:

/// Provider SQL with verified key and optional BIGINT version predicate slots.
struct DeletePlan
{
    private immutable(EntityMapping)* mapping;
    private string sql;
    private int keySlot;
    private int versionSlot;

    private this(immutable(EntityMapping)* mapping, string sql, int keySlot, int versionSlot) nothrow @nogc
    {
        this.mapping = mapping;
        this.sql = sql;
        this.keySlot = keySlot;
        this.versionSlot = versionSlot;
    }

    /// Whether planning verified the immutable SQL layout.
    package bool isPlanned() const scope pure nothrow @nogc
    {
        return mapping !is null;
    }
}

private alias PlanResult = Result!DeletePlan;

/// Verifies the binding layout of a provider-compiled single-table DELETE.
PlanResult planDelete(immutable(EntityMapping)* mapping, string sql, int keySlot, int versionSlot = 0) nothrow @nogc
{
    if (mapping is null || sql.length == 0)
        return PlanResult(DeletePlan.init, Error(Status.invalidArgument, "missing delete mapping or SQL"));
    const checked = validateMapping(*mapping);
    if (checked.code != Status.ok)
        return PlanResult(DeletePlan.init, checked);
    if (mapping.idOrdinals.length != 1 || mapping.attributes[mapping.idOrdinals[0]].kind != AttributeKind.integer)
        return PlanResult(DeletePlan.init, Error(Status.unsupported, "static deletes require a simple integer key"));
    const layout = validateSlots(*mapping, keySlot, versionSlot);
    if (layout.code != Status.ok)
        return PlanResult(DeletePlan.init, layout);
    return PlanResult(DeletePlan(mapping, sql, keySlot, versionSlot));
}

private Error validateSlots(scope const ref EntityMapping mapping, int keySlot, int versionSlot) pure nothrow @nogc
{
    const ordinal = mapping.versionOrdinal;
    if (ordinal == uint.max)
    {
        if (keySlot != 1 || versionSlot != 0)
            return Error(Status.invalidArgument, "unversioned delete requires only the key parameter");
        return Error.init;
    }

    const attribute = &mapping.attributes[ordinal];
    if (attribute.kind != AttributeKind.integer || attribute.sqlType != Types.BIGINT)
        return Error(Status.unsupported, "versioned deletes require a BIGINT version", ordinal);
    if (keySlot < 1 || keySlot > 2 || versionSlot < 1 || versionSlot > 2 || keySlot == versionSlot)
        return Error(Status.invalidArgument, "invalid or overlapping delete predicate slots", ordinal);
    return Error.init;
}

/// Deletes one managed row and retires its identity only after the statement closes.
/// The caller owns the JDBC transaction and rolls back on error.
Error executeManagedDelete(const ref DeletePlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key)
{
    if (plan.mapping is null || connection is null)
        return Error(Status.invalidArgument, "missing delete plan or connection");

    ManagedTarget target;
    const resolved = entities.resolveTarget(key, plan.mapping, target);
    if (resolved.code != Status.ok)
        return resolved;
    const type = validateEntity(*plan.mapping, target.entity);
    if (type.code != Status.ok)
        return type;
    const identifier = checkIdentifier(*plan.mapping, target.entity, key.identifier);
    if (identifier.code != Status.ok)
        return identifier;
    if (connection.getAutoCommit())
        return Error(Status.invalidArgument, "managed delete requires a JDBC transaction");

    const executed = deleteTarget(plan, connection, entities, target, key.identifier);
    if (executed.code != Status.ok)
        return executed;
    auto slot = entities.snapshotFor(target);
    if (slot is null || !slot.usesMapping(plan.mapping))
        return Error(Status.conflict, "managed entity retired during delete");
    return entities.detach(key).error;
}

private Error deleteTarget(const ref DeletePlan plan, Connection connection,
        scope ref ManagedEntities entities, scope ref ManagedTarget target, long identifier)
{
    auto slot = entities.snapshotFor(target);
    if (slot is null || !slot.usesMapping(plan.mapping))
        return Error(Status.conflict, "managed entity retired before delete");
    if (plan.versionSlot != 0)
    {
        const loaded = slot.loadedVersion(target.loadedVersion);
        if (loaded.code != Status.ok)
            return loaded;
    }

    auto statement = connection.prepareStatement(plan.sql);
    scope (exit)
        statement.close();
    statement.setLong(plan.keySlot, identifier);
    if (plan.versionSlot != 0)
        statement.setLong(plan.versionSlot, target.loadedVersion);
    const affected = statement.executeUpdate();
    if (affected == 0)
        return Error(Status.conflict, "managed delete predicate matched no row");
    if (affected != 1)
        return Error(Status.ioError, "managed delete affected an unexpected number of rows");
    return Error.init;
}
