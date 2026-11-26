/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Ordinal-aligned loaded state for the provider's dirty checking.
module flint.engine.jpa.loaded_state;

import flint.arena : Error, RequestArena, Result, Status;
import flint.engine.jpa.mapping : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    validateEntity, validateMapping;
import flint.engine.jpa.snapshot : AttributeSnapshot, captureAttribute, matchesAttribute;

@safe:

/// A validated mapping and the output capacity required for its dirty ordinals.
struct LoadedSnapshotPlan
{
    private immutable(EntityMapping)* mapping;
    private size_t updatable;

    private this(immutable(EntityMapping)* mapping, size_t updatable) nothrow @nogc
    {
        this.mapping = mapping;
        this.updatable = updatable;
    }
}

/// A context-owned view over a committed baseline's reserved snapshot slots.
struct LoadedSnapshot
{
    private LoadedSnapshotPlan plan;
    private const(AttributeSnapshot)[] snapshots;

    private this(LoadedSnapshotPlan plan, return scope const(AttributeSnapshot)[] snapshots) nothrow @nogc
    {
        this.plan = plan;
        this.snapshots = snapshots;
    }
}

/// Bounded baseline storage for one managed identity slot, with its own byte arena for reuse.
struct ManagedSnapshotSlot
{
    private RequestArena arena;
    private AttributeSnapshot[] fields;
    private LoadedSnapshotPlan plan;

    @disable this(this);
    @disable void opAssign(ManagedSnapshotSlot replacement);

    /// Borrows the exclusively reserved field and byte storage until this slot is retired.
    this(return scope AttributeSnapshot[] fields, return scope ubyte[] bytes) nothrow @nogc
    {
        arena = RequestArena(bytes);
        this.fields = fields;
    }

    /// Initializes an empty slot before its entity root is published.
    package Error capture(LoadedSnapshotPlan current, Object entity) scope nothrow @nogc
    {
        const error = writeSnapshots(current, entity, arena, fields);
        if (error.code != Status.ok)
        {
            clear();
            return error;
        }
        plan = current;
        return Error.init;
    }

    /// Checks the live baseline against its managed entity.
    package Result!size_t dirty(Object entity, scope uint[] ordinals) scope nothrow @nogc
    {
        return compareSnapshots(plan, entity, fields, arena, ordinals);
    }

    /// Retires the baseline and makes its byte storage available for the next identity.
    package void clear() scope nothrow @nogc
    {
        plan = LoadedSnapshotPlan.init;
        arena.reset();
    }
}

private alias PlanResult = Result!LoadedSnapshotPlan;
private alias LoadedResult = Result!LoadedSnapshot;
private alias DirtyResult = Result!size_t;
private alias ReadResult = Result!AttributeValue;

/// Checks the mapping at provider startup. It must outlive snapshots made from the plan.
PlanResult planLoadedSnapshot(immutable(EntityMapping)* mapping) nothrow @nogc
{
    if (mapping is null)
        return PlanResult(LoadedSnapshotPlan.init, Error(Status.invalidArgument, "missing loaded snapshot mapping"));
    const error = validateMapping(*mapping);
    if (error.code != Status.ok)
        return PlanResult(LoadedSnapshotPlan.init, error);
    size_t updatable;
    foreach (ref attribute; mapping.attributes)
        updatable += attribute.updatable;
    return PlanResult(LoadedSnapshotPlan(mapping, updatable));
}

/// Captures every attribute into reserved slots and returns a view after all reads and copies succeed.
/// A replacement uses separate staging slots and arena storage while its existing baseline remains live.
/// The caller can reclaim staging storage after failure and promotes the new view only after accepting it.
LoadedResult captureLoadedState(LoadedSnapshotPlan plan, Object entity, scope ref RequestArena arena,
        return scope AttributeSnapshot[] staging) nothrow @nogc
{
    const error = writeSnapshots(plan, entity, arena, staging);
    if (error.code != Status.ok)
        return LoadedResult(LoadedSnapshot.init, error);
    return LoadedResult(LoadedSnapshot(plan, staging[0 .. plan.mapping.attributes.length]));
}

private Error writeSnapshots(scope const LoadedSnapshotPlan plan, Object entity,
        scope ref RequestArena arena, scope AttributeSnapshot[] staging) nothrow @nogc
{
    if (plan.mapping is null)
        return Error(Status.invalidArgument, "missing loaded snapshot plan");
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return error;
    if (staging.length < plan.mapping.attributes.length)
        return Error(Status.resourceExhausted, "insufficient loaded snapshot slots");

    foreach (ref attribute; plan.mapping.attributes)
    {
        const current = readMapped(attribute, entity);
        if (!current.ok)
            return current.error;
        const snapshot = captureAttribute(arena, current.value);
        if (!snapshot.ok)
            return Error(snapshot.error.code, snapshot.error.message, attribute.ordinal);
        staging[attribute.ordinal] = snapshot.value;
    }
    return Error.init;
}

/// Writes changed updatable ordinals in mapping order. Reserve one slot per updatable attribute and use the
/// returned prefix after success. Byte comparisons use the baseline's original arena.
DirtyResult dirtyOrdinals(scope const ref LoadedSnapshot loaded, Object entity,
        scope ref RequestArena arena, scope uint[] ordinals) nothrow @nogc
{
    return compareSnapshots(loaded.plan, entity, loaded.snapshots, arena, ordinals);
}

private DirtyResult compareSnapshots(scope const LoadedSnapshotPlan plan, Object entity,
        scope const(AttributeSnapshot)[] fields, scope ref RequestArena arena, scope uint[] ordinals) nothrow @nogc
{
    if (plan.mapping is null)
        return DirtyResult(0, Error(Status.invalidArgument, "missing loaded baseline"));
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return DirtyResult(0, error);
    if (ordinals.length < plan.updatable)
        return DirtyResult(0, Error(Status.resourceExhausted, "insufficient dirty ordinal slots"));

    size_t count;
    foreach (ref attribute; plan.mapping.attributes)
    {
        if (!attribute.updatable)
            continue;
        const current = readMapped(attribute, entity);
        if (!current.ok)
            return DirtyResult(0, current.error);
        const matches = matchesAttribute(arena, fields[attribute.ordinal], current.value);
        if (!matches.ok)
            return DirtyResult(0, Error(matches.error.code, matches.error.message, attribute.ordinal));
        if (!matches.value)
            ordinals[count++] = attribute.ordinal;
    }
    return DirtyResult(count);
}

private ReadResult readMapped(scope const ref AttributeMapping attribute, Object entity) nothrow @nogc
{
    auto current = attribute.read(entity);
    if (!current.ok)
        return ReadResult(AttributeValue.init, Error(current.error.code, current.error.message, attribute.ordinal));
    const kind = current.value.kind;
    if (kind == attribute.kind || (kind == AttributeKind.nullValue && attribute.acceptsNull))
        return current;
    return ReadResult(AttributeValue.init, Error(Status.invalidArgument,
            "invalid mapped attribute kind", attribute.ordinal));
}
