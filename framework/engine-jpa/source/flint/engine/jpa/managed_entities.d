/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Connects the scalar identity index to a persistence context's GC-scanned entity roots.
module flint.engine.jpa.managed_entities;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity, IdentityIndex, IdentitySlot, LazyHandle;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, ManagedSnapshotSlot;
import flint.engine.jpa.mapping : AttributeValue, EntityMapping;

@safe:

private alias EntityResult = Result!Object;
private alias TicketResult = Result!ulong;
private alias LazyLoadResult = Result!LazyLoadStart;

/// A resolved managed entity, its context slot and an optional loaded version.
package struct ManagedTarget
{
    Object entity;
    long loadedVersion;
    size_t slot = size_t.max;
}

/// One context's managed entities. The caller reserves both backing slices exclusively and supplies GC-scanned roots.
struct ManagedEntities
{
    private IdentityIndex index;
    private Object[] roots;
    private ManagedSnapshotSlot[] snapshots;
    private size_t insertionSlot = size_t.max;
    private ulong insertionTicket;
    private bool awaitingKey;
    private bool capturingAttachment;

    @disable this(this);
    @disable void opAssign(ManagedEntities replacement);

    /// Starts with empty tables, with one snapshot slot per root when snapshots are enabled.
    /// A capacity mismatch leaves the supplied storage untouched.
    this(return scope IdentitySlot[] identities, return scope Object[] roots, out Error error,
            return scope ManagedSnapshotSlot[] snapshots = null) nothrow @nogc
    {
        if (identities.length != roots.length)
        {
            error = Error(Status.invalidArgument, "JPA identity and object tables differ in capacity");
            return;
        }
        if (snapshots.length != 0 && snapshots.length != roots.length)
        {
            error = Error(Status.invalidArgument, "JPA snapshot and object tables differ in capacity");
            return;
        }
        index = IdentityIndex(identities);
        this.roots = roots;
        this.roots[] = null;
        this.snapshots = snapshots;
        foreach (ref snapshot; this.snapshots)
            snapshot.clear();
    }

    ~this() scope nothrow @nogc
    {
        clear();
    }

    /// Roots an entity for its canonical key after capturing its baseline when storage is configured.
    /// An existing identity keeps its original entity and baseline.
    Error manage(EntityIdentity key, Object entity, LoadedSnapshotPlan plan = LoadedSnapshotPlan()) scope nothrow @nogc
    {
        size_t publishedSlot;
        return manage(key, entity, plan, publishedSlot);
    }

    /// Reports the slot only when this call publishes a new attachment.
    package Error manage(EntityIdentity key, Object entity, LoadedSnapshotPlan snapshotPlan,
            out size_t publishedAttachmentSlot) scope nothrow @nogc
    {
        publishedAttachmentSlot = size_t.max;
        if (entity is null)
            return Error(Status.invalidArgument, "cannot manage a null JPA entity");
        if (capturingAttachment)
            return Error(Status.conflict, "a JPA attachment baseline is being captured");
        if (awaitingKey)
            return Error(Status.conflict, "context capacity is reserved for an IDENTITY insert");
        const claim = snapshots.length == 0 ? index.claim(key) : index.reserve(key);
        if (!claim.ok)
            return claim.error;
        const slot = claim.value.slot;
        if (!claim.value.inserted)
            return roots[slot] is entity ? Error.init : Error(Status.conflict, "another JPA entity has this identity");
        if (snapshots.length != 0)
        {
            const error = captureAttachment(slot, snapshotPlan, entity, null);
            if (!index.finishReservation(slot, error.code == Status.ok))
            {
                snapshots[slot].clear();
                return Error(Status.conflict, "JPA attachment retired during capture");
            }
            if (error.code != Status.ok)
                return error;
        }
        roots[slot] = entity;
        publishedAttachmentSlot = slot;
        return Error.init;
    }

    // Mapped readers can re-enter this context. Keep the slot exclusive until the reader has returned.
    private Error captureAttachment(size_t slot, LoadedSnapshotPlan snapshotPlan, Object entity,
            scope AttributeValue[] values) scope nothrow @nogc
    {
        capturingAttachment = true;
        scope (exit)
            capturingAttachment = false;
        return snapshots[slot].capture(snapshotPlan, entity, values);
    }

    /// Reserves an invisible identity and records the initial values for one in-flight insert.
    package TicketResult stageInsert(EntityIdentity key, LoadedSnapshotPlan plan, Object entity,
            scope AttributeValue[] values) scope nothrow @nogc
    {
        const available = checkInsertAvailability(entity);
        if (available.code != Status.ok)
            return TicketResult(0, available);
        const reserved = index.reserve(key);
        if (!reserved.ok)
            return TicketResult(0, reserved.error);
        if (!reserved.value.inserted)
            return TicketResult(0, Error(Status.conflict, "JPA insert identity is already managed"));

        insertionSlot = reserved.value.slot;
        const ticket = ++insertionTicket;
        const error = captureAttachment(reserved.value.slot, plan, entity, values);
        if (!ownsInsert(ticket))
        {
            snapshots[reserved.value.slot].clear();
            return TicketResult(0, Error(Status.conflict, "JPA insert reservation retired during capture"));
        }
        if (error.code != Status.ok)
        {
            cancelInsert(ticket);
            return TicketResult(0, error);
        }
        return TicketResult(ticket);
    }

    /// Reserves one bounded vacancy before JDBC returns the canonical key.
    package TicketResult reserveIdentityInsert(Object entity) scope nothrow @nogc
    {
        const available = checkInsertAvailability(entity);
        if (available.code != Status.ok)
            return TicketResult(0, available);
        if (!index.hasVacancy())
            return TicketResult(0, Error(Status.resourceExhausted, "JPA identity index is full"));
        awaitingKey = true;
        return TicketResult(++insertionTicket);
    }

    /// Assigns the reserved capacity to the generated key and records its initial state.
    package Error stageIdentityInsert(ulong ticket, EntityIdentity key, LoadedSnapshotPlan plan,
            scope const(AttributeValue)[] captured) scope nothrow @nogc
    {
        if (!ownsInsert(ticket) || !awaitingKey)
            return Error(Status.conflict, "JPA IDENTITY reservation retired");
        const reserved = index.reserve(key);
        if (!reserved.ok)
            return reserved.error;
        if (!reserved.value.inserted)
            return Error(Status.conflict, "generated JPA identity is already managed");

        awaitingKey = false;
        insertionSlot = reserved.value.slot;
        return snapshots[insertionSlot].captureValues(plan, captured);
    }

    private Error checkInsertAvailability(scope Object entity) const scope nothrow @nogc
    {
        if (snapshots.length == 0)
            return Error(Status.unsupported, "JPA insert requires snapshot storage");
        if (capturingAttachment)
            return Error(Status.conflict, "a JPA attachment baseline is being captured");
        if (awaitingKey || insertionSlot != size_t.max)
            return Error(Status.conflict, "a JPA insert is already pending in this context");
        if (insertionTicket == ulong.max)
            return Error(Status.resourceExhausted, "JPA insert tickets exhausted");
        if (entity !is null)
            foreach (root; roots)
                if (root is entity)
                    return Error(Status.conflict, "JPA insert entity is already managed");
        return Error.init;
    }

    /// Publishes the reserved entry once SQL and statement close succeed.
    package Error publishInsert(ulong ticket, Object entity) scope nothrow @nogc
    {
        if (!ownsInsert(ticket) || awaitingKey)
            return Error(Status.conflict, "JPA insert reservation retired");
        roots[insertionSlot] = entity;
        index.finishReservation(insertionSlot, true);
        insertionSlot = size_t.max;
        return Error.init;
    }

    /// Cancels only the insertion that acquired this ticket.
    package void cancelInsert(ulong ticket) scope nothrow @nogc
    {
        if (!ownsInsert(ticket))
            return;
        if (awaitingKey)
        {
            awaitingKey = false;
            return;
        }
        snapshots[insertionSlot].clear();
        index.finishReservation(insertionSlot, false);
        insertionSlot = size_t.max;
    }

    private bool ownsInsert(ulong ticket) const scope nothrow @nogc
    {
        return (awaitingKey || insertionSlot != size_t.max) && insertionTicket == ticket;
    }

    /// Finds the managed instance for a canonical key.
    EntityResult find(EntityIdentity key) scope nothrow @nogc
    {
        const found = index.find(key);
        if (!found.ok)
            return EntityResult(null, found.error);
        return EntityResult(roots[found.value]);
    }

    /// Returns a handle for an owner whose attachment has been published.
    Result!LazyHandle lazyHandle(EntityIdentity key) scope nothrow @nogc
    {
        const found = index.find(key);
        if (!found.ok)
            return Result!LazyHandle(LazyHandle.init, found.error);
        if (roots[found.value] is null)
            return Result!LazyHandle(LazyHandle.init, Error(Status.notFound, "JPA identity is not managed"));
        return index.mintLazyHandle(found.value);
    }

    /// Resolves the owner of an unloaded association before a loader acquires JDBC.
    EntityResult resolveLazyOwner(LazyHandle handle) scope nothrow @nogc
    {
        const found = index.resolveLazySlot(handle);
        if (!found.ok)
            return EntityResult(null, found.error);
        return EntityResult(roots[found.value]);
    }

    package void beginPostLoad(size_t slot) scope nothrow @nogc
    {
        index.beginPostLoad(slot);
    }

    package void finishPostLoad(size_t slot, EntityIdentity key, bool failed) scope nothrow @nogc
    {
        if (index.finishPostLoad(slot) && failed)
            detach(key);
    }

    /// Reports changed updatable ordinals for a managed identity with a captured baseline.
    Result!size_t dirty(EntityIdentity key, scope uint[] ordinals) scope nothrow @nogc
    {
        ManagedTarget target;
        return dirtyTarget(key, null, ordinals, target);
    }

    /// Resolves an identity and verifies descriptor ownership before a mutation.
    package Error resolveTarget(EntityIdentity key, scope immutable(EntityMapping)* expectedMapping,
            out ManagedTarget target) scope nothrow @nogc
    {
        const found = index.find(key);
        if (!found.ok)
            return found.error;
        if (snapshots.length == 0)
            return Error(Status.unsupported, "JPA context has no snapshot storage");
        if (expectedMapping !is null && !snapshots[found.value].usesMapping(expectedMapping))
            return Error(Status.invalidArgument, "mutation plan does not match the loaded mapping");
        target.slot = found.value;
        target.entity = roots[target.slot];
        return Error.init;
    }

    /// Checks the resolved target and collects dirty fields with one identity lookup.
    package Result!size_t dirtyTarget(EntityIdentity key, scope immutable(EntityMapping)* mapping,
            scope uint[] ordinals, out ManagedTarget target, bool versioned = false) scope nothrow @nogc
    {
        const resolved = resolveTarget(key, mapping, target);
        if (resolved.code != Status.ok)
            return Result!size_t(0, resolved);
        auto snapshot = &snapshots[target.slot];
        const dirty = snapshot.dirty(target.entity, ordinals);
        if (dirty.ok && dirty.value != 0 && versioned)
        {
            const versionError = snapshot.loadedVersion(target.loadedVersion);
            if (versionError.code != Status.ok)
                return Result!size_t(0, versionError);
        }
        return dirty;
    }

    /// Borrows the checked target slot while its original entity is still managed.
    package ManagedSnapshotSlot* snapshotFor(scope const ref ManagedTarget target) return scope nothrow @nogc
    {
        if (target.slot >= snapshots.length || roots[target.slot]!is target.entity)
            return null;
        return &snapshots[target.slot];
    }

    package bool setDeletePending(scope const ref ManagedTarget target, bool pending) scope nothrow @nogc
    {
        return index.setDeletePending(target.slot, pending);
    }

    /// Checks that the target still owns the attachment marked for deletion.
    package ManagedSnapshotSlot* snapshotForDelete(scope const ref ManagedTarget target) return scope nothrow @nogc
    {
        return index.deletePending(target.slot) ? snapshotFor(target) : null;
    }

    /// Releases the entity's root and baseline, then returns the detached instance.
    EntityResult detach(EntityIdentity key) scope nothrow @nogc
    {
        const found = index.detach(key);
        if (!found.ok)
            return EntityResult(null, found.error);
        auto entity = roots[found.value];
        roots[found.value] = null;
        if (snapshots.length != 0)
            snapshots[found.value].clear();
        return EntityResult(entity);
    }

    /// Releases all managed entity roots and resets identity and baseline storage.
    void clear() scope nothrow @nogc
    {
        roots[] = null;
        index.clear();
        insertionSlot = size_t.max;
        awaitingKey = false;
        foreach (ref snapshot; snapshots)
            snapshot.clear();
    }
}

/// A validated owner and its active load attempt.
struct LazyLoadStart
{
    /// GC-owned owner for the fetch.
    Object entity;
    /// Attempt number for the originating state.
    uint attempt;
}

/// Single-fiber load state for one association. Its caller owns the typed payload and JDBC lease.
struct LazyLoadState
{
    private enum Phase : ubyte
    {
        unloaded,
        loading,
        loaded,
    }

    private LazyHandle owner;
    private uint serial;
    private Phase phase;

    @disable this(this);
    @disable void opAssign(LazyLoadState replacement);

    /// Read before consulting a context. An initialized null or empty payload is loaded too.
    @property bool loaded() const scope nothrow @nogc
    {
        return phase == Phase.loaded;
    }

    /// Resolves the owner before JDBC acquisition. An attempt number belongs to this state alone.
    /// Supply the handle captured on attachment, including for retries.
    LazyLoadResult begin(scope ref ManagedEntities managed, LazyHandle handle) scope nothrow @nogc
    {
        if (phase != Phase.unloaded)
            return LazyLoadResult(LazyLoadStart.init, Error(Status.conflict,
                    "JPA lazy association has already started loading"));
        if (serial == uint.max)
            return LazyLoadResult(LazyLoadStart.init, Error(Status.resourceExhausted,
                    "JPA lazy load attempts exhausted"));
        auto resolved = managed.resolveLazyOwner(handle);
        if (!resolved.ok)
            return LazyLoadResult(LazyLoadStart.init, resolved.error);
        owner = handle;
        phase = Phase.loading;
        return LazyLoadResult(LazyLoadStart(resolved.value, ++serial));
    }

    /// Completes a terminal successful fetch after rechecking its owner in the current context.
    /// Publish the staged payload immediately on success, before invoking callbacks.
    Error complete(scope ref ManagedEntities managed, uint attempt) scope nothrow @nogc
    {
        if (!owns(attempt))
            return Error(Status.conflict, "JPA lazy load attempt is no longer active");
        const resolved = managed.resolveLazyOwner(owner);
        phase = resolved.ok ? Phase.loaded : Phase.unloaded;
        return resolved.error;
    }

    /// Releases the matching failed attempt once its I/O is terminal.
    void fail(uint attempt) scope nothrow @nogc
    {
        if (owns(attempt))
            phase = Phase.unloaded;
    }

    private bool owns(uint attempt) const scope nothrow @nogc
    {
        return phase == Phase.loading && attempt == serial;
    }
}
