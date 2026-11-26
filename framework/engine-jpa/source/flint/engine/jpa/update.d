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
import flint.engine.jpa.managed_entities : DirtyTarget, ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping;
import flint.engine.jpa.parameter_binding : ParameterBinding, ParameterBindingPlan, bindMappedValues, planParameters;
import flint.engine.jpa.result_binding : TypedColumnCodec;
import flint.java.sql : Connection, Types;

@safe:

/// JDBC slots reserved for the incremented version in SET and the loaded version in WHERE.
struct VersionBindings
{
    /// One-based parameter for the incremented version.
    int next;
    /// One-based parameter for the loaded version.
    int expected;
}

/// Startup-validated bindings and provider-compiled SQL for one entity table.
struct UpdatePlan
{
    private immutable(EntityMapping)* mapping;
    private string sql;
    private ParameterBindingPlan parameters;
    private int keySlot;
    private VersionBindings versions;

    private this(immutable(EntityMapping)* mapping, string sql, ParameterBindingPlan plan,
            int keySlot, VersionBindings versions) nothrow @nogc
    {
        this.mapping = mapping;
        this.sql = sql;
        this.parameters = plan;
        this.keySlot = keySlot;
        this.versions = versions;
    }
}

private alias PlanResult = Result!UpdatePlan;
private alias UpdateResult = Result!bool;
private alias VersionResult = Result!VersionedUpdate;

/// Outcome of a versioned statement. An updated row's next version is available for later publication.
struct VersionedUpdate
{
    /// Whether the statement affected one row.
    bool updated;
    /// Version to publish for an updated row.
    long nextVersion;
}

/// Checks full coverage of updatable non-key fields and a distinct slot for the integer key.
/// The provider supplies the corresponding compiled single-table UPDATE SQL.
PlanResult planUpdate(immutable(EntityMapping)* mapping, string sql,
        immutable(ParameterBinding)[] changes, int keySlot, TypedColumnCodec typed = TypedColumnCodec()) nothrow @nogc
{
    return planUpdate(mapping, sql, changes, keySlot, VersionBindings.init, typed);
}

/// Checks the static update bindings for a table with a BIGINT optimistic version.
PlanResult planUpdate(immutable(EntityMapping)* mapping, string sql, immutable(ParameterBinding)[] changes,
        int keySlot, VersionBindings versions, TypedColumnCodec typed = TypedColumnCodec()) nothrow @nogc
{
    const parameters = planParameters(mapping, changes, typed);
    if (!parameters.ok)
        return PlanResult(UpdatePlan.init, parameters.error);
    if (sql.length == 0)
        return PlanResult(UpdatePlan.init, Error(Status.invalidArgument, "missing static update SQL"));
    if (mapping.idOrdinals.length != 1 || mapping.attributes[mapping.idOrdinals[0]].kind != AttributeKind.integer)
        return PlanResult(UpdatePlan.init, Error(Status.unsupported, "static updates require a simple integer key"));
    const layout = validateUpdateLayout(*mapping, changes, keySlot, versions);
    if (layout.code != Status.ok)
        return PlanResult(UpdatePlan.init, layout);
    return PlanResult(UpdatePlan(mapping, sql, parameters.value, keySlot, versions));
}

private Error validateUpdateLayout(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] changes, int keySlot, VersionBindings versions) nothrow @nogc
{
    const id = mapping.idOrdinals[0];
    const versioned = mapping.versionOrdinal != uint.max;
    size_t writable;
    foreach (ref attribute; mapping.attributes)
        writable += attribute.updatable && attribute.ordinal != id && attribute.ordinal != mapping.versionOrdinal;
    const slots = writable + (versioned ? 3 : 1);
    if (writable == 0 || changes.length != writable || keySlot < 1 || cast(size_t) keySlot > slots)
        return Error(Status.invalidArgument, "incomplete static update layout");
    const versionError = validateVersionBindings(mapping, keySlot, versions, slots);
    if (versionError.code != Status.ok)
        return versionError;
    return validateWritableBindings(mapping, changes, keySlot, versions, slots);
}

private Error validateWritableBindings(scope const ref EntityMapping mapping,
        scope const(ParameterBinding)[] changes, int keySlot, VersionBindings versions, size_t slots) nothrow @nogc
{
    const id = mapping.idOrdinals[0];
    foreach (index, ref change; changes)
    {
        if (change.ordinal == id || change.ordinal == mapping.versionOrdinal
                || !mapping.attributes[change.ordinal].updatable || cast(size_t) change.parameter > slots)
            return Error(Status.invalidArgument, "invalid static update binding", index);
        const parameter = change.parameter;
        if (parameter == keySlot || parameter == versions.next || parameter == versions.expected)
            return Error(Status.invalidArgument, "static update binding overlaps key or version", index);
        foreach (ref previous; changes[0 .. index])
            if (previous.ordinal == change.ordinal)
                return Error(Status.invalidArgument, "duplicate static update attribute", index);
    }
    return Error.init;
}

private Error validateVersionBindings(scope const ref EntityMapping mapping, int keySlot,
        VersionBindings versions, size_t slots) nothrow @nogc
{
    if (mapping.versionOrdinal == uint.max)
    {
        if (versions.next != 0 || versions.expected != 0)
            return Error(Status.invalidArgument, "unversioned mapping has version bindings");
        return Error.init;
    }
    const ordinal = mapping.versionOrdinal;
    const attribute = &mapping.attributes[ordinal];
    if ((versions.next == 0 && versions.expected == 0) || attribute.kind != AttributeKind.integer
            || attribute.sqlType != Types.BIGINT)
        return Error(Status.unsupported, "versioned updates require BIGINT version bindings", ordinal);
    if (versions.next < 1 || versions.expected < 1 || cast(size_t) versions.next > slots
            || cast(size_t) versions.expected > slots || versions.next == versions.expected
            || versions.next == keySlot || versions.expected == keySlot)
        return Error(Status.invalidArgument, "invalid or overlapping version bindings", ordinal);
    return Error.init;
}

/// Returns true after one updated row and false for a clean entity. The caller owns the transaction and
/// must roll back on failure. This operation leaves the loaded baseline in place for transaction handling.
UpdateResult executeManagedUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key, scope uint[] dirtyOrdinals)
{
    if (plan.versions.next != 0)
        return UpdateResult(false, Error(Status.invalidArgument, "use the versioned update executor"));
    const written = executeStaticUpdate(plan, connection, entities, key, dirtyOrdinals);
    return UpdateResult(written.value.updated, written.error);
}

/// Executes a version predicate with the loaded version. The caller owns version and baseline publication.
VersionResult executeVersionedUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key, scope uint[] dirtyOrdinals)
{
    if (plan.versions.next == 0)
        return VersionResult(VersionedUpdate.init, Error(Status.invalidArgument, "missing versioned update plan"));
    return executeStaticUpdate(plan, connection, entities, key, dirtyOrdinals);
}

/// Executes a dirty update and replaces its loaded baseline after one affected row.
/// Supply exclusive GC-scanned scratch with one slot per mapped attribute. Staged values retain their original
/// GC-owned strings for JDBC and the scratch is cleared on return.
/// The caller rolls back failures and detaches affected entries after transaction rollback.
VersionResult flushManagedUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities, EntityIdentity key, scope uint[] dirtyOrdinals, AttributeValue[] values)
{
    return executeStaticUpdate(plan, connection, entities, key, dirtyOrdinals, values, true);
}

private VersionResult executeStaticUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities,
        EntityIdentity key, scope uint[] dirtyOrdinals, AttributeValue[] values = null, bool refresh = false)
{
    if (plan.mapping is null || connection is null)
        return VersionResult(VersionedUpdate.init, Error(Status.invalidArgument, "missing update plan or connection"));

    DirtyTarget target;
    const dirty = entities.dirtyTarget(key, plan.mapping, dirtyOrdinals, target, plan.versions.next != 0);
    if (!dirty.ok)
        return VersionResult(VersionedUpdate.init, dirty.error);

    const identifier = checkIdentifier(*plan.mapping, target.entity, key.identifier);
    if (identifier.code != Status.ok)
        return VersionResult(VersionedUpdate.init, identifier);
    if (dirty.value == 0)
        return VersionResult(VersionedUpdate.init);
    if (connection.getAutoCommit())
        return VersionResult(VersionedUpdate.init, Error(Status.invalidArgument,
                "managed update requires a JDBC transaction"));
    const versioned = plan.versions.next != 0;
    if (versioned && target.loadedVersion == long.max)
        return VersionResult(VersionedUpdate.init, Error(Status.resourceExhausted,
                "managed entity version exhausted", plan.mapping.versionOrdinal));
    const nextRevision = versioned ? target.loadedVersion + 1 : 0;
    if (refresh)
        return executeWithRefresh(plan, connection, entities, target, key, nextRevision, values);
    return executeStatement(plan, connection, target, key.identifier, nextRevision);
}

private VersionResult executeWithRefresh(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities, DirtyTarget target, EntityIdentity key, long nextRevision,
        AttributeValue[] values)
{
    const count = plan.mapping.attributes.length;
    if (values.length < count)
        return VersionResult(VersionedUpdate.init, Error(Status.resourceExhausted, "insufficient update value slots"));
    auto slot = entities.snapshotFor(target);
    if (slot is null || !slot.usesMapping(plan.mapping))
        return refreshConflict();
    auto captured = values[0 .. count];
    scope (exit)
        captured[] = AttributeValue.init;
    const staged = slot.stageChecked(target.entity, captured, nextRevision);
    if (staged.code != Status.ok)
        return VersionResult(VersionedUpdate.init, staged);
    scope (exit)
        slot.discard();

    const result = executeStatement(plan, connection, target, key.identifier, nextRevision, captured);
    if (!result.ok)
        return result;
    if (entities.snapshotFor(target) is null || !slot.hasStaged())
        return refreshConflict();
    if (plan.versions.next != 0)
    {
        scope (failure)
            if (entities.snapshotFor(target) !is null && slot.hasStaged())
                entities.detach(key);
        const ordinal = plan.mapping.versionOrdinal;
        plan.mapping.attributes[ordinal].write(target.entity, captured[ordinal]);
        if (entities.snapshotFor(target) is null || !slot.hasStaged())
            return refreshConflict();
    }
    slot.publish();
    return result;
}

private VersionResult refreshConflict() pure nothrow @nogc
{
    return VersionResult(VersionedUpdate.init, Error(Status.conflict, "managed entity retired during update"));
}

private VersionResult executeStatement(const ref UpdatePlan plan, Connection connection,
        DirtyTarget target, long id, long nextRevision, const(AttributeValue)[] captured = null)
{
    auto statement = connection.prepareStatement(plan.sql);
    scope (exit)
        statement.close();
    const bound = bindMappedValues(plan.parameters, statement, target.entity, captured);
    if (bound.code != Status.ok)
        return VersionResult(VersionedUpdate.init, bound);

    statement.setLong(plan.keySlot, id);
    if (plan.versions.next != 0)
    {
        statement.setLong(plan.versions.next, nextRevision);
        statement.setLong(plan.versions.expected, target.loadedVersion);
    }
    const affected = statement.executeUpdate();
    if (affected == 0)
        return VersionResult(VersionedUpdate.init, Error(Status.conflict, "managed update predicate matched no row"));
    if (affected != 1)
        return VersionResult(VersionedUpdate.init, Error(Status.ioError,
                "managed update affected an unexpected number of rows"));
    return VersionResult(VersionedUpdate(true, nextRevision));
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
