/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.identity_test;

import flint.arena : Status;
import flint.engine.jpa.identity : EntityIdentity, IdentityIndex, IdentitySlot;
import std.traits : hasIndirections;

@safe:

@("entity identity is local to the index and includes the root mapping and signed id")
unittest
{
    IdentitySlot[4] firstSlots;
    IdentitySlot[4] secondSlots;
    scope first = IdentityIndex(firstSlots[]);
    scope second = IdentityIndex(secondSlots[]);
    enum zero = EntityIdentity(0, 0);
    enum negative = EntityIdentity(0, -1);
    enum otherRoot = EntityIdentity(1, -1);

    assert(first.find(zero).error.code == Status.notFound);
    const entry = first.claim(zero);
    assert(entry.ok && entry.value.inserted);
    assert(first.find(zero).ok && first.find(zero).value == entry.value.slot);
    const existing = first.claim(zero);
    assert(existing.ok && !existing.value.inserted && existing.value.slot == entry.value.slot);
    assert(second.find(zero).error.code == Status.notFound);
    assert(second.claim(zero).ok);

    const one = first.claim(negative);
    const two = first.claim(otherRoot);
    assert(one.ok && two.ok && one.value.slot != two.value.slot);
    first.clear();
    assert(first.find(zero).error.code == Status.notFound);
    assert(second.find(zero).ok);
}

@("detaching from a full index leaves other entries reachable and permits slot reuse")
unittest
{
    IdentitySlot[2] slots;
    scope index = IdentityIndex(slots[]);
    enum a = EntityIdentity(0, 1);
    enum b = EntityIdentity(0, 5);
    enum c = EntityIdentity(0, 3);

    const first = index.claim(a);
    const second = index.claim(b);
    assert(first.ok && second.ok);
    assert(index.claim(c).error.code == Status.resourceExhausted);
    assert(index.detach(a).value == first.value.slot);
    assert(index.find(a).error.code == Status.notFound);
    assert(index.find(b).value == second.value.slot);
    const replacement = index.claim(c);
    assert(replacement.ok && replacement.value.slot == first.value.slot);
    assert(index.detach(b).ok && index.detach(c).ok);
    assert(index.detach(c).error.code == Status.notFound);
    assert(index.claim(a).ok && index.claim(b).ok);
    assert(index.claim(c).error.code == Status.resourceExhausted);
}

@("the index borrows storage without GC references or a stack escape")
unittest
{
    static assert(!hasIndirections!IdentitySlot);
    static assert(!__traits(compiles, () @safe { IdentitySlot[1] local; return IdentityIndex(local[]); }));
    scope empty = IdentityIndex(null);
    assert(empty.claim(EntityIdentity(0, 0)).error.code == Status.resourceExhausted);
}

@("a completed nested PostLoad clears its marker before the retired outer callback unwinds")
unittest
{
    IdentitySlot[1] slots;
    scope index = IdentityIndex(slots[]);
    enum key = EntityIdentity(0, 1);
    const first = index.claim(key);
    assert(first.ok);
    const outer = first.value.slot;
    index.beginPostLoad(outer);

    assert(index.detach(key).ok);
    const second = index.claim(key);
    assert(second.ok);
    const inner = second.value.slot;
    index.beginPostLoad(inner);
    assert(inner == outer);
    assert(index.finishPostLoad(inner));
    assert(!index.finishPostLoad(outer));
    assert(index.find(key).ok);
}

@("PostLoad cleanup accepts retirement of the entire index")
unittest
{
    IdentitySlot[1] slots;
    scope index = IdentityIndex(slots[]);
    enum key = EntityIdentity(0, 1);
    const claim = index.claim(key);
    assert(claim.ok);
    const position = claim.value.slot;
    index.beginPostLoad(position);
    destroy(index);
    assert(!index.finishPostLoad(position));
}
