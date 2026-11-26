/*
 * Ported from hibernate-orm 7.1.0: hibernate-core/src/main/java/org/hibernate/persister/entity/mutation/UpdateCoordinatorStandard.java,
 * hibernate-core/src/main/java/org/hibernate/event/internal/DefaultFlushEntityEventListener.java
 * hibernate-core/src/main/java/org/hibernate/engine/jdbc/mutation/internal/ModelMutationHelper.java,
 * and hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java.
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 * Modified by the Flint authors: precompiled static SQL and resource-local JDBC with engine status results.
 */

/// Checked static updates for managed entities with a simple integer key.
module flint.engine.jpa.update;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.delete_row : DeletePlan, executeManagedDelete;
import flint.engine.jpa.identity : EntityIdentity;
import flint.engine.jpa.loaded_state : ManagedSnapshotSlot;
import flint.engine.jpa.managed_entities : ManagedTarget, ManagedEntities;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue, EntityMapping, checkIdentifier;
import flint.engine.jpa.parameter_binding : InsertPlan, ParameterBinding, ParameterBindingPlan,
    bindMappedValues, executeScheduledInsert, planParameters, checkInsertScratch;
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
    private size_t dirtySlots;

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
    auto plan = UpdatePlan(mapping, sql, parameters.value, keySlot, versions);
    plan.dirtySlots = changes.length + mapping.attributes[mapping.idOrdinals[0]].updatable;
    return PlanResult(plan);
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

/// A scalar work item naming one checked plan and one managed entity.
struct UpdateAction
{
    /// Ordinal in the plan table for this action's phase.
    uint planOrdinal;
    /// Canonical identity in the current persistence context.
    EntityIdentity key;
}

/// Progress through an ordered group of updates.
struct UpdateBatchProgress
{
    /// Number of statements that updated exactly one row and published their baseline.
    size_t updated;
    /// Position of the first failed action, or size_t.max on success or a batch-wide error.
    size_t failedAction = size_t.max;
}

private alias BatchResult = Result!UpdateBatchProgress;

/// Checks all plan references and scratch requirements before flushing in the supplied order.
/// One caller-owned connection and one set of scratch buffers serve every action.
/// On a reported error, progress counts earlier published writes and identifies the stopped action.
/// The caller owns rollback and must retire affected state, including earlier successes.
BatchResult flushManagedUpdates(Connection connection, scope ref ManagedEntities entities,
        const(UpdatePlan)[] plans, scope const(UpdateAction)[] actions, scope uint[] ordinals, AttributeValue[] values)
{
    if (actions.length != 0 && connection is null)
        return BatchResult(UpdateBatchProgress.init, Error(Status.invalidArgument, "missing update connection"));

    const checked = validateUpdateBatch(plans, actions, ordinals.length, values.length);
    if (!checked.ok)
        return checked;
    return executeUpdateBatch(connection, entities, plans, actions, ordinals, values);
}

private BatchResult validateUpdateBatch(scope const(UpdatePlan)[] plans,
        scope const(UpdateAction)[] actions, size_t ordinalCount, size_t valueCount) pure nothrow @nogc
{
    foreach (index, ref action; actions)
    {
        if (action.planOrdinal >= plans.length || plans[action.planOrdinal].mapping is null)
            return BatchResult(UpdateBatchProgress(0, index), Error(Status.invalidArgument,
                    "invalid update plan ordinal"));
        const plan = &plans[action.planOrdinal];
        if (ordinalCount < plan.dirtySlots || valueCount < plan.mapping.attributes.length)
            return BatchResult(UpdateBatchProgress(0, index), Error(Status.resourceExhausted,
                    "insufficient batch scratch"));
    }

    return BatchResult(UpdateBatchProgress.init);
}

private BatchResult executeUpdateBatch(Connection connection, scope ref ManagedEntities entities,
        const(UpdatePlan)[] plans, scope const(UpdateAction)[] actions, scope uint[] ordinals, AttributeValue[] values)
{
    UpdateBatchProgress progress;
    foreach (index, ref action; actions)
    {
        const result = flushManagedUpdate(plans[action.planOrdinal], connection, entities,
                action.key, ordinals, values);
        if (!result.ok)
        {
            progress.failedAction = index;
            return BatchResult(progress, result.error);
        }
        progress.updated += result.value.updated;
    }
    return BatchResult(progress);
}

/// A delete action uses the same scalar layout as an update action.
alias DeleteAction = UpdateAction;

/// A pending insert refers to a rooted entity without storing a GC reference in the action.
struct InsertAction
{
    /// Ordinal in the insert plan table.
    uint planOrdinal;
    /// Position of the entity in InsertInputs.roots.
    size_t entitySlot;
    /// Canonical root and, for an assigned ID, the identifier.
    EntityIdentity key;
}

/// Caller-reserved inputs for pending inserts.
struct InsertInputs
{
    /// GC-scanned roots containing the entities that may be inserted.
    Object[] roots;
    /// Exclusive scratch containing one key column name at a time for IDENTITY inserts.
    string[] keyColumn;
}

/// Provider-compiled plan tables for the mutation phases.
struct MutationPlans
{
    /// Update plans indexed by update actions.
    const(UpdatePlan)[] updates;
    /// Delete plans indexed by delete actions.
    const(DeletePlan)[] deletes;
    /// Insert plans indexed by pending insert actions.
    const(InsertPlan)[] inserts;
}

/// The caller's ordered action list for each phase.
struct MutationActions
{
    /// Actions to run in the update phase.
    const(UpdateAction)[] updates;
    /// Actions to run after the update phase.
    const(DeleteAction)[] deletes;
    /// Actions to run before the update phase.
    const(InsertAction)[] inserts;
}

/// Phase of the first action error.
enum MutationPhase : ubyte
{
    /// No individual action failed.
    none,
    /// An update plan or action failed.
    updates,
    /// A delete plan or action failed.
    deletes,
    /// An insert plan or action failed.
    inserts,
}

/// Counts completed writes and identifies the first reported action error.
struct MutationBatchProgress
{
    /// Updates that affected one row and published a baseline.
    size_t updated;
    /// Deletes that affected one row and retired an identity.
    size_t deleted;
    /// Phase that reported the error, or none for success or a batch-wide error.
    MutationPhase failedPhase;
    /// Zero-based index in that phase, or size_t.max when inapplicable.
    size_t failedAction = size_t.max;
    /// Inserts that affected one row and published an identity.
    size_t inserted;
}

private alias MutationBatchResult = Result!MutationBatchProgress;

/// Validates every phase before SQL, then inserts, updates and deletes on the caller's connection.
/// On a reported error, progress identifies the stopped action and retains earlier write counts.
/// The caller owns rollback and retires state that was touched before an error.
MutationBatchResult flushManagedMutations(Connection connection, scope ref ManagedEntities entities,
        const ref MutationPlans plans,
        scope const ref MutationActions actions, scope uint[] ordinals, AttributeValue[] values,
        InsertInputs inputs = InsertInputs.init)
{
    const hasActions = actions.inserts.length != 0 || actions.updates.length != 0 || actions.deletes.length != 0;
    if (hasActions && connection is null)
        return MutationBatchResult(MutationBatchProgress.init, Error(Status.invalidArgument,
                "missing mutation connection"));
    const layout = validateMutationBatch(plans, actions, ordinals.length, values.length, inputs);
    if (!layout.ok)
        return layout;

    MutationBatchProgress progress;
    foreach (index, ref action; actions.inserts)
    {
        const inserted = executeScheduledInsert(plans.inserts[action.planOrdinal], connection,
                entities, action.key, inputs.roots[action.entitySlot], values, inputs.keyColumn);
        if (inserted.code != Status.ok)
        {
            progress.failedPhase = MutationPhase.inserts;
            progress.failedAction = index;
            return MutationBatchResult(progress, inserted);
        }
        ++progress.inserted;
    }

    const updates = executeUpdateBatch(connection, entities, plans.updates, actions.updates, ordinals, values);
    if (!updates.ok)
        return failedUpdatePhase(updates, progress.inserted);
    progress.updated = updates.value.updated;

    foreach (index, ref action; actions.deletes)
    {
        const removed = executeManagedDelete(plans.deletes[action.planOrdinal], connection, entities, action.key);
        if (removed.code != Status.ok)
        {
            progress.failedPhase = MutationPhase.deletes;
            progress.failedAction = index;
            return MutationBatchResult(progress, removed);
        }
        ++progress.deleted;
    }
    return MutationBatchResult(progress);
}

private MutationBatchResult validateMutationBatch(scope const ref MutationPlans plans,
        scope const ref MutationActions actions, size_t ordinalCount, size_t valueCount,
        scope const ref InsertInputs inputs) pure nothrow @nogc
{
    const inserts = validateInsertActions(plans.inserts, actions.inserts, valueCount, inputs);
    if (!inserts.ok)
        return inserts;
    const updates = validateUpdateBatch(plans.updates, actions.updates, ordinalCount, valueCount);
    if (!updates.ok)
        return failedUpdatePhase(updates);
    foreach (index, ref action; actions.deletes)
    {
        if (action.planOrdinal >= plans.deletes.length || !plans.deletes[action.planOrdinal].isPlanned())
            return MutationBatchResult(MutationBatchProgress(0, 0, MutationPhase.deletes, index),
                    Error(Status.invalidArgument, "invalid delete plan ordinal"));
    }
    return MutationBatchResult(MutationBatchProgress.init);
}

private MutationBatchResult validateInsertActions(scope const(InsertPlan)[] plans,
        scope const(InsertAction)[] actions, size_t valueCount, scope const ref InsertInputs inputs) pure nothrow @nogc
{
    foreach (index, ref action; actions)
    {
        const progress = MutationBatchProgress(0, 0, MutationPhase.inserts, index);
        if (action.planOrdinal >= plans.length)
            return MutationBatchResult(progress, Error(Status.invalidArgument, "invalid insert plan ordinal"));
        if (action.entitySlot >= inputs.roots.length || inputs.roots[action.entitySlot] is null)
            return MutationBatchResult(progress, Error(Status.invalidArgument, "invalid insert entity root"));
        const layout = checkInsertScratch(plans[action.planOrdinal], valueCount, inputs.keyColumn.length);
        if (layout.code != Status.ok)
            return MutationBatchResult(progress, layout);
    }
    return MutationBatchResult(MutationBatchProgress.init);
}

private MutationBatchResult failedUpdatePhase(const ref BatchResult updates, size_t inserted = 0) pure nothrow @nogc
{
    const progress = MutationBatchProgress(updates.value.updated, 0, MutationPhase.updates,
            updates.value.failedAction, inserted);
    return MutationBatchResult(progress, updates.error);
}

private VersionResult executeStaticUpdate(const ref UpdatePlan plan, Connection connection,
        scope ref ManagedEntities entities,
        EntityIdentity key, scope uint[] dirtyOrdinals, AttributeValue[] values = null, bool refresh = false)
{
    if (plan.mapping is null || connection is null)
        return VersionResult(VersionedUpdate.init, Error(Status.invalidArgument, "missing update plan or connection"));

    ManagedTarget target;
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
        scope ref ManagedEntities entities, ManagedTarget target, EntityIdentity key,
        long nextRevision, AttributeValue[] values)
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

    const result = executeStatement(plan, connection, target, key.identifier, nextRevision, captured, slot);
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

private VersionResult executeStatement(const ref UpdatePlan plan, Connection connection, ManagedTarget target,
        long id, long nextRevision, const(AttributeValue)[] captured = null,
        scope const ManagedSnapshotSlot* staged = null)
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
    if (staged !is null && !staged.hasStaged())
        return refreshConflict();
    const affected = statement.executeUpdate();
    if (affected == 0)
        return VersionResult(VersionedUpdate.init, Error(Status.conflict, "managed update predicate matched no row"));
    if (affected != 1)
        return VersionResult(VersionedUpdate.init, Error(Status.ioError,
                "managed update affected an unexpected number of rows"));
    return VersionResult(VersionedUpdate(true, nextRevision));
}
