/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Connects the scalar identity index to a persistence context's GC-scanned entity roots.
module flint.engine.jpa.managed_entities;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity, IdentityIndex, IdentitySlot;

@safe:

private alias EntityResult = Result!Object;

/// One context's managed entities. The caller reserves both backing slices exclusively and supplies GC-scanned roots.
struct ManagedEntities
{
    private IdentityIndex index;
    private Object[] roots;

    @disable this(this);
    @disable void opAssign(ManagedEntities replacement);

    /// Starts with empty tables. On a capacity mismatch both supplied slices retain their contents.
    this(return scope IdentitySlot[] identities, return scope Object[] roots, out Error error) nothrow @nogc
    {
        if (identities.length != roots.length)
        {
            error = Error(Status.invalidArgument, "JPA identity and object tables differ in capacity");
            return;
        }
        index = IdentityIndex(identities);
        this.roots = roots;
        this.roots[] = null;
    }

    ~this() scope nothrow @nogc
    {
        clear();
    }

    /// Roots an entity for its canonical key. A conflicting instance leaves the existing root in place.
    Error manage(EntityIdentity key, Object entity) scope nothrow @nogc
    {
        if (entity is null)
            return Error(Status.invalidArgument, "cannot manage a null JPA entity");
        const claim = index.claim(key);
        if (!claim.ok)
            return claim.error;
        if (claim.value.inserted)
            roots[claim.value.slot] = entity;
        else if (roots[claim.value.slot]!is entity)
            return Error(Status.conflict, "another JPA entity has this identity");
        return Error.init;
    }

    /// Finds the managed instance for a canonical key.
    EntityResult find(EntityIdentity key) scope nothrow @nogc
    {
        const found = index.find(key);
        if (!found.ok)
            return EntityResult(null, found.error);
        return EntityResult(roots[found.value]);
    }

    /// Releases the entity's root and returns the detached instance.
    EntityResult detach(EntityIdentity key) scope nothrow @nogc
    {
        const found = index.detach(key);
        if (!found.ok)
            return EntityResult(null, found.error);
        auto entity = roots[found.value];
        roots[found.value] = null;
        return EntityResult(entity);
    }

    /// Releases all managed entity roots and resets the identity slots.
    void clear() scope nothrow @nogc
    {
        roots[] = null;
        index.clear();
    }
}
