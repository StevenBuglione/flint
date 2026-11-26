/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Provider startup registration for generated entity mappings.
module flint.engine.jpa.registry;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.mapping : EntityMapping, validateMapping;

@safe:

private struct MappingTypeSlot
{
    // The address is an opaque class identity and is never dereferenced.
    const(void)* identity;
    size_t ordinal;
}

/// A checked immutable mapping table for one persistence unit.
struct MappingRegistry
{
    private immutable(EntityMapping)[] mappings;
    private const(MappingTypeSlot)[] typeSlots;

    private this(immutable(EntityMapping)[] mappings) nothrow @nogc
    {
        this.mappings = mappings;
    }

    /// Resolves a case-sensitive Jakarta entity name during plan registration.
    immutable(EntityMapping)* findEntity(scope const(char)[] name) const nothrow @nogc
    {
        foreach (ref mapping; mappings)
            if (mapping.entityName == name)
                return &mapping;
        return null;
    }

    /// Resolves a fully qualified D class name during plan registration.
    immutable(EntityMapping)* findType(scope const(char)[] name) const nothrow @nogc
    {
        foreach (ref mapping; mappings)
            if (mapping.typeName == name)
                return &mapping;
        return null;
    }

    /// Resolves the exact runtime class in a registry built with a class table.
    immutable(EntityMapping)* findExactObject(scope const Object entity) const nothrow @nogc
    {
        if (entity is null || typeSlots.length == 0)
            return null;
        const identity = cast(const(void)*) typeid(entity);
        const slot = &typeSlots[slotOf(typeSlots, identity)];
        return slot.identity is null ? null : &mappings[slot.ordinal];
    }
}

private alias Registration = Result!MappingRegistry;

/// Validates provider-lifetime mappings before publishing the table. An error's offset is the mapping index.
Result!MappingRegistry registerMappings(immutable(EntityMapping)[] mappings) nothrow @nogc
{
    foreach (index, ref mapping; mappings)
    {
        const error = validateMapping(mapping);
        if (error.code != Status.ok)
            return Registration(MappingRegistry.init, Error(error.code, error.message, index));
        foreach (ref previous; mappings[0 .. index])
        {
            if (mapping.entityName == previous.entityName)
                return Registration(MappingRegistry.init, Error(Status.invalidArgument,
                        "duplicate JPA entity name", index));
            if (mapping.typeName == previous.typeName)
                return Registration(MappingRegistry.init, Error(Status.invalidArgument,
                        "duplicate JPA D type name", index));
        }
    }
    return Registration(MappingRegistry(mappings));
}

/// Builds a read-only exact-class index at startup. The ordered class table can be static read-only data.
Registration registerMappings(immutable(EntityMapping)[] mappings, scope const(TypeInfo_Class)[] classes)
{
    if (classes.length != mappings.length)
        return Registration(MappingRegistry.init, Error(Status.invalidArgument, "incomplete JPA class table"));
    auto registered = registerMappings(mappings);
    if (!registered.ok || mappings.length == 0)
        return registered;
    if (mappings.length > size_t.max / (4 * MappingTypeSlot.sizeof))
        return Registration(MappingRegistry.init, Error(Status.outOfMemory, "JPA class index is too large"));

    // Power of two, at most half full, with a free slot terminating every probe.
    size_t capacity = 2;
    while (capacity / 2 < mappings.length)
        capacity *= 2;
    auto slots = new MappingTypeSlot[capacity];
    foreach (ordinal, type; classes)
    {
        if (type is null || !mappings[ordinal].isExactType(type))
            return Registration(MappingRegistry.init, Error(Status.invalidArgument,
                    "JPA class does not match its mapping", ordinal));
        const identity = cast(const(void)*) type;
        const slot = slotOf(slots, identity);
        if (slots[slot].identity !is null)
            return Registration(MappingRegistry.init, Error(Status.invalidArgument,
                    "duplicate JPA class identity", ordinal));
        slots[slot] = MappingTypeSlot(identity, ordinal);
    }
    registered.value.typeSlots = slots;
    return registered;
}

private size_t slotOf(scope const(MappingTypeSlot)[] slots, scope const(void)* identity) pure nothrow @nogc
{
    const capacity = slots.length; // Callers have a nonempty power-of-two table.
    const mask = capacity - 1;
    size_t slot = hashOf(identity) & mask;
    while (slots[slot].identity !is null && slots[slot].identity !is identity)
        slot = (slot + 1) & mask;
    return slot;
}
