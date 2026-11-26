/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.managed_entities_test;

import flint.arena : Error, Status;
import flint.engine.jpa.identity : EntityIdentity, IdentitySlot, LazyHandle;
import flint.engine.jpa.loaded_state : ManagedSnapshotSlot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import std.traits : hasIndirections;

@safe:

@("the managed table preserves the instance for an existing identity")
unittest
{
    IdentitySlot[1] identities;
    Object[1] roots;
    Error error;
    scope managed = ManagedEntities(identities[], roots[], error);
    assert(error.code == Status.ok);

    enum key = EntityIdentity(0, 4);
    auto original = new Object;
    auto other = new Object;
    assert(managed.manage(key, null).code == Status.invalidArgument);
    assert(managed.find(key).error.code == Status.notFound);
    assert(managed.manage(key, original).code == Status.ok);
    assert(managed.manage(key, original).code == Status.ok);
    assert(managed.manage(key, other).code == Status.conflict);
    assert(managed.find(key).value is original);
    assert(managed.dirty(key, null).error.code == Status.unsupported);
    assert(managed.manage(EntityIdentity(1, 4), other).code == Status.resourceExhausted);

    const detached = managed.detach(key);
    assert(detached.ok && detached.value is original);
    assert(roots[0] is null);
    assert(managed.find(key).error.code == Status.notFound);
    assert(managed.manage(key, other).code == Status.ok);
    assert(managed.find(key).value is other);
}

@("clearing a table and unwinding its scope both release the GC roots")
unittest
{
    IdentitySlot[2] identities;
    Object[2] roots;
    Error error;
    enum first = EntityIdentity(0, 1);
    enum second = EntityIdentity(0, 2);
    auto one = new Object;
    auto two = new Object;

    try
    {
        scope managed = ManagedEntities(identities[], roots[], error);
        assert(error.code == Status.ok);
        assert(managed.manage(first, one).code == Status.ok);
        assert(managed.manage(second, two).code == Status.ok);
        managed.clear();
        assert(roots[0] is null && roots[1] is null);
        assert(managed.find(first).error.code == Status.notFound);
        assert(managed.manage(second, two).code == Status.ok);
        throw new Exception("unwind the context");
    }
    catch (Exception expected)
    {
        assert(expected.msg == "unwind the context");
    }

    assert(roots[0] is null && roots[1] is null);
    scope reused = ManagedEntities(identities[], roots[], error);
    assert(reused.find(second).error.code == Status.notFound);
    assert(reused.manage(first, one).code == Status.ok);
}

@("an invalid storage pairing leaves the supplied GC roots untouched")
unittest
{
    IdentitySlot[2] identities;
    auto unrelated = new Object;
    Object[1] roots = [unrelated];
    Error error;
    {
        scope managed = ManagedEntities(identities[], roots[], error);
        assert(error.code == Status.invalidArgument);
        assert(managed.find(EntityIdentity(0, 1)).error.code == Status.notFound);
        managed.clear();
    }
    assert(roots[0] is unrelated);
    ManagedSnapshotSlot[2] snapshots;
    {
        scope managed = ManagedEntities(identities[0 .. 1], roots[], error, snapshots[]);
        assert(error.code == Status.invalidArgument);
        assert(managed.find(EntityIdentity(0, 1)).error.code == Status.notFound);
    }
    assert(roots[0] is unrelated);
}

@("the managed table cannot outlive the borrowed root buffer")
unittest
{
    static assert(!__traits(compiles, (IdentitySlot[] identities) @safe {
            Object[1] roots;
            Error error;
            return ManagedEntities(identities, roots[], error);
        }));
}

@("lazy handles identify a live attachment in their originating context")
unittest
{
    static assert(!hasIndirections!LazyHandle);
    static assert(LazyHandle.sizeof == 16);
    IdentitySlot[1] firstIndex;
    Object[1] firstRoots;
    IdentitySlot[1] secondIndex;
    Object[1] secondRoots;
    Error error;
    scope first = ManagedEntities(firstIndex[], firstRoots[], error);
    assert(error.code == Status.ok);
    scope second = ManagedEntities(secondIndex[], secondRoots[], error);
    assert(error.code == Status.ok);

    enum key = EntityIdentity(0, -7);
    auto owner = new Object;
    assert(first.lazyHandle(key).error.code == Status.notFound);
    assert(first.resolveLazyOwner(LazyHandle.init).error.code == Status.notFound);
    assert(first.manage(key, owner).code == Status.ok);
    assert(second.manage(key, owner).code == Status.ok);
    const original = first.lazyHandle(key);
    const foreign = second.lazyHandle(key);
    assert(original.ok && foreign.ok);
    assert(first.resolveLazyOwner(original.value).value is owner);
    assert(first.resolveLazyOwner(foreign.value).error.code == Status.notFound);
    assert(second.resolveLazyOwner(original.value).error.code == Status.notFound);

    assert(first.detach(key).ok);
    assert(first.resolveLazyOwner(original.value).error.code == Status.notFound);
    assert(first.manage(key, owner).code == Status.ok);
    const reused = first.lazyHandle(key);
    assert(reused.ok && first.resolveLazyOwner(reused.value).value is owner);
    assert(first.resolveLazyOwner(original.value).error.code == Status.notFound);
    first.clear();
    assert(first.manage(key, owner).code == Status.ok);
    const reloaded = first.lazyHandle(key);
    assert(reloaded.ok && first.resolveLazyOwner(reloaded.value).value is owner);
    assert(first.resolveLazyOwner(reused.value).error.code == Status.notFound);
}

@("reconstructing a context on the same storage does not revive its handles")
unittest
{
    IdentitySlot[1] identities;
    Object[1] roots;
    Error error;
    enum key = EntityIdentity(0, 1);
    auto entity = new Object;
    LazyHandle retired;
    {
        scope context = ManagedEntities(identities[], roots[], error);
        assert(error.code == Status.ok);
        assert(context.manage(key, entity).code == Status.ok);
        const issued = context.lazyHandle(key);
        assert(issued.ok);
        retired = issued.value;
    }
    scope replacement = ManagedEntities(identities[], roots[], error);
    assert(error.code == Status.ok);
    assert(replacement.manage(key, entity).code == Status.ok);
    const issued = replacement.lazyHandle(key);
    assert(issued.ok && replacement.resolveLazyOwner(issued.value).value is entity);
    assert(replacement.resolveLazyOwner(retired).error.code == Status.notFound);
}
