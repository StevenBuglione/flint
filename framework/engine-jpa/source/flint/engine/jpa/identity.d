/*
 * Ported from hibernate-orm 7.1.0: hibernate-core/src/main/java/org/hibernate/engine/spi/EntityKey.java
 * and hibernate-core/src/main/java/org/hibernate/engine/internal/StatefulPersistenceContext.java.
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 * Modified by the Flint authors: root mapping ordinals and scalar bigint identifiers in bounded context storage.
 */

/// Scalar identity bookkeeping for one provider persistence context.
module flint.engine.jpa.identity;

import core.atomic : MemoryOrder, atomicLoad, cas;
import flint.arena : Error, Result, Status;

@safe:

/// A root entity mapping and its canonical signed bigint identifier.
struct EntityIdentity
{
    /// Persistence-unit ordinal shared by the mappings in one inheritance root.
    uint root;
    /// The persistent identifier, including zero and negative values.
    long identifier;
}

private enum SlotState : ubyte
{
    empty,
    live,
    reserved,
    deleted,
}

/// Scalar backing storage. The corresponding entity reference belongs in separate GC-scanned storage.
struct IdentitySlot
{
    private EntityIdentity key;
    private SlotState state;
    private uint generation;
}

/// Opaque scalar reference to an entity attachment for a deferred association.
struct LazyHandle
{
    private ulong context;
    private uint slot;
    private uint generation;
}

private shared ulong issuedContexts;

private ulong issueContext() nothrow @nogc
{
    for (;;)
    {
        const issued = atomicLoad!(MemoryOrder.raw)(issuedContexts);
        if (issued == ulong.max)
            return 0;
        if (cas!(MemoryOrder.raw, MemoryOrder.raw)(&issuedContexts, issued, issued + 1))
            return issued + 1;
    }
}

/// The result of claiming an identity. An existing claim must keep its original entity reference.
struct IdentityClaim
{
    /// Position in the context's object table, valid until the identity is detached or cleared.
    size_t slot;
    /// Whether this call assigned a new slot.
    bool inserted;
}

private struct Probe
{
    size_t slot = size_t.max;
    bool found;
}

/// Single-context index borrowing exclusively reserved storage for scalar slot metadata.
struct IdentityIndex
{
    private IdentitySlot[] slots;
    private ulong lazyContext;
    private uint lazyGeneration;

    @disable this(this);
    @disable void opAssign(IdentityIndex replacement);

    /// Resets the backing slots for a new context. The caller provides one object-table slot per backing slot.
    this(return scope IdentitySlot[] storage) nothrow @nogc
    {
        slots = storage;
        clear();
    }

    /// Finds the context's slot for an existing identity.
    Result!size_t find(EntityIdentity key) const scope nothrow @nogc
    {
        const result = probe(key);
        if (!result.found || slots[result.slot].state != SlotState.live)
            return Result!size_t(size_t.max, Error(Status.notFound, "JPA identity is not managed"));
        return Result!size_t(result.slot);
    }

    /// Issues a handle once per live attachment, after its entity has been published.
    package Result!LazyHandle mintLazyHandle(size_t position) scope nothrow @nogc
    {
        if (position > uint.max)
            return Result!LazyHandle(LazyHandle.init, Error(Status.resourceExhausted,
                    "JPA lazy slot exceeds capacity"));
        auto slot = &slots[position];
        assert(slot.state == SlotState.live);
        if (slot.generation == 0)
        {
            if (lazyContext == 0)
                lazyContext = issueContext();
            if (lazyContext == 0 || lazyGeneration == uint.max)
                return Result!LazyHandle(LazyHandle.init, Error(Status.resourceExhausted,
                        "JPA lazy attachment identifiers exhausted"));
            slot.generation = ++lazyGeneration;
        }
        return Result!LazyHandle(LazyHandle(lazyContext, cast(uint) position, slot.generation));
    }

    /// Checks the originating context and current attachment without resolving or loading an association.
    package Result!size_t resolveLazySlot(LazyHandle handle) const scope nothrow @nogc
    {
        if (handle.context == lazyContext && handle.slot < slots.length && handle.generation != 0)
        {
            const slot = &slots[handle.slot];
            if (slot.state == SlotState.live && slot.generation == handle.generation)
                return Result!size_t(handle.slot);
        }
        return Result!size_t(size_t.max, Error(Status.notFound, "JPA lazy owner is no longer managed"));
    }

    /// Assigns a slot for a new identity or returns the existing claim without changing it.
    Result!IdentityClaim claim(EntityIdentity key) scope nothrow @nogc
    {
        return claimSlot(key, SlotState.live);
    }

    /// Checks capacity before reserving a slot whose database-generated key is still unknown.
    package bool hasVacancy() const scope nothrow @nogc
    {
        foreach (ref slot; slots)
            if (slot.state == SlotState.empty || slot.state == SlotState.deleted)
                return true;
        return false;
    }

    /// Reserves a slot that excludes the same key from other claims before it is visible to find.
    package Result!IdentityClaim reserve(EntityIdentity key) scope nothrow @nogc
    {
        return claimSlot(key, SlotState.reserved);
    }

    /// Resolves the current context's reservation when its statement has completed.
    package bool finishReservation(size_t slot, bool publish) scope nothrow @nogc
    {
        if (slots[slot].state != SlotState.reserved)
            return false;
        slots[slot].state = publish ? SlotState.live : SlotState.deleted;
        return true;
    }

    private Result!IdentityClaim claimSlot(EntityIdentity key, SlotState state) scope nothrow @nogc
    {
        const result = probe(key);
        if (result.slot == size_t.max)
            return Result!IdentityClaim(IdentityClaim.init, Error(Status.resourceExhausted,
                    "JPA identity index is full"));
        if (!result.found)
            slots[result.slot] = IdentitySlot(key, state);
        return Result!IdentityClaim(IdentityClaim(result.slot, !result.found));
    }

    /// Detaches one identity and returns the slot whose entity reference the caller must clear.
    Result!size_t detach(EntityIdentity key) scope nothrow @nogc
    {
        const result = find(key);
        if (result.ok)
            slots[result.value].state = SlotState.deleted;
        return result;
    }

    /// Resets the index. The caller also clears its object table before reusing the slots.
    void clear() scope nothrow @nogc
    {
        slots[] = IdentitySlot.init;
    }

    private Probe probe(EntityIdentity key) const scope nothrow @nogc
    {
        if (slots.length == 0)
            return Probe.init;
        size_t position = hashOf(key.identifier, key.root) % slots.length;
        size_t available = size_t.max;
        foreach (_; 0 .. slots.length)
        {
            const slot = &slots[position];
            if (slot.state == SlotState.live || slot.state == SlotState.reserved)
            {
                if (slot.key.root == key.root && slot.key.identifier == key.identifier)
                    return Probe(position, true);
            }
            else
            {
                if (available == size_t.max)
                    available = position;
                if (slot.state == SlotState.empty)
                    break;
            }
            ++position;
            if (position == slots.length)
                position = 0;
        }
        return Probe(available, false);
    }
}
