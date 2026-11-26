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
    if (plan.mapping is null)
        return LoadedResult(LoadedSnapshot.init, Error(Status.invalidArgument, "missing loaded snapshot plan"));
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return LoadedResult(LoadedSnapshot.init, error);
    const count = plan.mapping.attributes.length;
    if (staging.length < count)
        return LoadedResult(LoadedSnapshot.init, Error(Status.resourceExhausted,
                "insufficient loaded snapshot slots"));

    foreach (ref attribute; plan.mapping.attributes)
    {
        const current = readMapped(attribute, entity);
        if (!current.ok)
            return LoadedResult(LoadedSnapshot.init, current.error);
        const snapshot = captureAttribute(arena, current.value);
        if (!snapshot.ok)
            return LoadedResult(LoadedSnapshot.init, Error(snapshot.error.code,
                    snapshot.error.message, attribute.ordinal));
        staging[attribute.ordinal] = snapshot.value;
    }
    return LoadedResult(LoadedSnapshot(plan, staging[0 .. count]));
}

/// Writes changed updatable ordinals in mapping order. Reserve one slot per updatable attribute and use the
/// returned prefix after success. Byte comparisons use the baseline's original arena.
DirtyResult dirtyOrdinals(scope const ref LoadedSnapshot loaded, Object entity,
        scope ref RequestArena arena, scope uint[] ordinals) nothrow @nogc
{
    if (loaded.plan.mapping is null)
        return DirtyResult(0, Error(Status.invalidArgument, "missing loaded baseline"));
    const error = validateEntity(*loaded.plan.mapping, entity);
    if (error.code != Status.ok)
        return DirtyResult(0, error);
    if (ordinals.length < loaded.plan.updatable)
        return DirtyResult(0, Error(Status.resourceExhausted, "insufficient dirty ordinal slots"));

    size_t count;
    foreach (ref attribute; loaded.plan.mapping.attributes)
    {
        if (!attribute.updatable)
            continue;
        const current = readMapped(attribute, entity);
        if (!current.ok)
            return DirtyResult(0, current.error);
        const matches = matchesAttribute(arena, loaded.snapshots[attribute.ordinal], current.value);
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
