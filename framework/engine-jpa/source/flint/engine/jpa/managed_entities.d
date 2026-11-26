/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Connects the scalar identity index to a persistence context's GC-scanned entity roots.
module flint.engine.jpa.managed_entities;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.identity : EntityIdentity, IdentityIndex, IdentitySlot;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, ManagedSnapshotSlot;
import flint.engine.jpa.mapping : EntityMapping;

@safe:

private alias EntityResult = Result!Object;

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
        if (entity is null)
            return Error(Status.invalidArgument, "cannot manage a null JPA entity");
        const claim = index.claim(key);
        if (!claim.ok)
            return claim.error;
        const slot = claim.value.slot;
        if (!claim.value.inserted)
            return roots[slot] is entity ? Error.init : Error(Status.conflict, "another JPA entity has this identity");
        if (snapshots.length != 0)
        {
            const error = snapshots[slot].capture(plan, entity);
            if (error.code != Status.ok)
            {
                index.detach(key);
                return error;
            }
        }
        roots[slot] = entity;
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
        foreach (ref snapshot; snapshots)
            snapshot.clear();
    }
}
