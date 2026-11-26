/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Provider startup registration for generated entity mappings.
module flint.engine.jpa.registry;

import flint.arena : Error, Result, Status;
import flint.engine.jpa.mapping : EntityMapping, validateMapping;

@safe:

/// A checked immutable mapping table for one persistence unit.
struct MappingRegistry
{
    private immutable(EntityMapping)[] mappings;

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
}

/// Validates provider-lifetime mappings before publishing the table. An error's offset is the mapping index.
Result!MappingRegistry registerMappings(immutable(EntityMapping)[] mappings) nothrow @nogc
{
    alias Registration = Result!MappingRegistry;
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
