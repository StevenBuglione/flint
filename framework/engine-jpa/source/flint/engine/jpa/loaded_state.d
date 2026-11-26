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

private struct SnapshotBank
{
    RequestArena arena;
    AttributeSnapshot[] fields;

    this(return scope AttributeSnapshot[] fields, return scope ubyte[] bytes) nothrow @nogc
    {
        arena = RequestArena(bytes);
        this.fields = fields;
    }
}

/// Bounded snapshot storage for one identity slot. A second bank enables atomic baseline replacement.
struct ManagedSnapshotSlot
{
    private SnapshotBank primary;
    private SnapshotBank alternate;
    private LoadedSnapshotPlan plan;
    private uint active;
    private bool pending;

    @disable this(this);
    @disable void opAssign(ManagedSnapshotSlot replacement);

    /// Borrows two disjoint sets of field and byte storage until this slot is retired.
    this(return scope AttributeSnapshot[] fields, return scope ubyte[] bytes,
            return scope AttributeSnapshot[] stagedFields = null, return scope ubyte[] stagedBytes = null) nothrow @nogc
    {
        primary = SnapshotBank(fields, bytes);
        if (stagedFields.length != 0)
            alternate = SnapshotBank(stagedFields, stagedBytes);
    }

    private ref SnapshotBank bank(uint index) scope return nothrow @nogc
    {
        if (index == 0)
            return primary;
        return alternate;
    }

    /// Initializes an empty slot before its entity root is published.
    package Error capture(LoadedSnapshotPlan initial, Object entity, scope AttributeValue[] values) scope nothrow @nogc
    {
        const error = writeSnapshots(initial, entity, bank(active).arena, bank(active).fields, values);
        if (error.code != Status.ok)
        {
            clear();
            return error;
        }
        plan = initial;
        return Error.init;
    }

    /// Creates the initial baseline from previously checked write values.
    package Error captureValues(LoadedSnapshotPlan initial, scope const(AttributeValue)[] values) scope nothrow @nogc
    {
        assert(initial.mapping !is null && values.length == initial.mapping.attributes.length);
        const error = storeCapturedSnapshots(bank(active).arena, bank(active).fields, values);
        if (error.code != Status.ok)
        {
            clear();
            return error;
        }
        plan = initial;
        return Error.init;
    }

    /// Tests descriptor identity before another plan uses this snapshot's entity.
    package bool usesMapping(scope immutable(EntityMapping)* mapping) const scope nothrow @nogc
    {
        return plan.mapping is mapping;
    }

    /// Reads the loaded scalar version for an optimistic predicate.
    package Error loadedVersion(out long value) scope nothrow @nogc
    {
        if (plan.mapping is null || plan.mapping.versionOrdinal == uint.max)
            return Error(Status.invalidArgument, "missing loaded version");
        const ordinal = plan.mapping.versionOrdinal;
        if (!bank(active).fields[ordinal].readInteger(value))
            return Error(Status.invalidArgument, "loaded version is not an integer", ordinal);
        return Error.init;
    }

    /// Checks the live baseline against its managed entity.
    package Result!size_t dirty(Object entity, scope uint[] ordinals) scope nothrow @nogc
    {
        return compareSnapshots(plan, entity, bank(active).fields, bank(active).arena, ordinals);
    }

    /// Captures a replacement for the type-checked target while its active bank remains readable.
    package Error stageChecked(Object entity, scope AttributeValue[] values, long nextRevision) scope nothrow @nogc
    {
        if (pending)
            return Error(Status.conflict, "a JPA snapshot refresh is already staged");
        assert(plan.mapping !is null && values.length == plan.mapping.attributes.length);
        const staging = active ^ 1;
        const error = storeSnapshots(*plan.mapping, entity, bank(staging).arena, bank(staging)
                .fields, values, nextRevision, true);
        if (error.code != Status.ok)
        {
            bank(staging).arena.reset();
            return error;
        }
        pending = true;
        return Error.init;
    }

    /// A detached or cleared slot has no pending baseline.
    package bool hasStaged() const scope nothrow @nogc
    {
        return pending;
    }

    /// Activates the replacement and returns the previous bank to the slot.
    package void publish() scope nothrow @nogc
    {
        assert(pending);
        bank(active).arena.reset();
        active ^= 1;
        pending = false;
    }

    /// Releases an unpublished replacement after failure.
    package void discard() scope nothrow @nogc
    {
        if (pending)
        {
            bank(active ^ 1).arena.reset();
            pending = false;
        }
    }

    /// Retires the baseline and makes its byte storage available for the next identity.
    package void clear() scope nothrow @nogc
    {
        plan = LoadedSnapshotPlan.init;
        primary.arena.reset();
        alternate.arena.reset();
        active = 0;
        pending = false;
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
        updatable += attribute.updatable && attribute.ordinal != mapping.versionOrdinal;
    return PlanResult(LoadedSnapshotPlan(mapping, updatable));
}

/// Captures every attribute into reserved slots and returns a view after all reads and copies succeed.
/// A replacement uses separate staging slots and arena storage while its existing baseline remains live.
/// The caller can reclaim staging storage after failure and promotes the new view only after accepting it.
LoadedResult captureLoadedState(LoadedSnapshotPlan plan, Object entity, scope ref RequestArena arena,
        return scope AttributeSnapshot[] staging) nothrow @nogc
{
    const error = writeSnapshots(plan, entity, arena, staging, null);
    if (error.code != Status.ok)
        return LoadedResult(LoadedSnapshot.init, error);
    return LoadedResult(LoadedSnapshot(plan, staging[0 .. plan.mapping.attributes.length]));
}

private Error writeSnapshots(scope const LoadedSnapshotPlan plan, Object entity,
        scope ref RequestArena arena, scope AttributeSnapshot[] staging, scope AttributeValue[] values) nothrow @nogc
{
    if (plan.mapping is null)
        return Error(Status.invalidArgument, "missing loaded snapshot plan");
    const error = validateEntity(*plan.mapping, entity);
    if (error.code != Status.ok)
        return error;
    return storeSnapshots(*plan.mapping, entity, arena, staging, values);
}

private Error storeSnapshots(scope const ref EntityMapping mapping, Object entity, scope ref RequestArena arena,
        scope AttributeSnapshot[] staging, scope AttributeValue[] values, long nextRevision = 0,
        bool replaceVersion = false) nothrow @nogc
{
    const count = mapping.attributes.length;
    if (staging.length < count || (values.length != 0 && values.length < count))
        return Error(Status.resourceExhausted, "insufficient loaded snapshot slots");

    foreach (ref attribute; mapping.attributes)
    {
        const replacementVersion = replaceVersion && attribute.ordinal == mapping.versionOrdinal;
        const current = replacementVersion ? ReadResult(AttributeValue(AttributeKind.integer, nextRevision))
            : readMapped(attribute, entity);
        if (!current.ok)
            return current.error;
        const error = storeField(arena, staging[attribute.ordinal], current.value, attribute.ordinal);
        if (error.code != Status.ok)
            return error;
        if (values.length != 0)
            values[attribute.ordinal] = current.value;
    }
    return Error.init;
}

private Error storeCapturedSnapshots(scope ref RequestArena arena, scope AttributeSnapshot[] storage,
        scope const(AttributeValue)[] values) nothrow @nogc
{
    if (storage.length < values.length)
        return Error(Status.resourceExhausted, "insufficient loaded snapshot slots");
    foreach (ordinal, ref value; values)
    {
        const error = storeField(arena, storage[ordinal], value, ordinal);
        if (error.code != Status.ok)
            return error;
    }
    return Error.init;
}

private Error storeField(scope ref RequestArena arena, ref AttributeSnapshot target,
        scope const ref AttributeValue value, size_t ordinal) nothrow @nogc
{
    const snapshot = captureAttribute(arena, value);
    if (!snapshot.ok)
        return Error(snapshot.error.code, snapshot.error.message, ordinal);
    target = snapshot.value;
    return Error.init;
}

/// Writes changed updatable ordinals in mapping order, excluding the provider-owned version. Reserve one slot
/// per updatable attribute and use the returned prefix after success. Byte comparisons use the original arena.
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
        if (!attribute.updatable || attribute.ordinal == plan.mapping.versionOrdinal)
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

package ReadResult readMapped(scope const ref AttributeMapping attribute, Object entity) nothrow @nogc
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
