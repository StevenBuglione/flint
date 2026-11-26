/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.persistence_context_test;

import flint.jakarta.persistence : PersistenceContext, PersistenceContexts, PersistenceContextType,
    PersistenceProperty, SynchronizationType;

@safe:

@("persistence context defaults and per-context properties survive UDA grouping")
unittest
{
    @PersistenceContext()
    static class DefaultContext
    {
    }

    enum property = PersistenceProperty(name: "vendor.readOnly", value: "true");
    enum audit = PersistenceContext("persistence/audit", "audit", PersistenceContextType.EXTENDED,
                SynchronizationType.UNSYNCHRONIZED, [property]);

    @PersistenceContexts([PersistenceContext(name: "persistence/clinic", unitName: "clinic"), audit])
    static class MultiContext
    {
    }

    enum defaults = __traits(getAttributes, DefaultContext)[0];
    static assert(defaults.name == "" && defaults.unitName == "" && defaults.properties.length == 0);
    static assert(defaults.type == PersistenceContextType.TRANSACTION);
    static assert(defaults.synchronization == SynchronizationType.SYNCHRONIZED);

    enum declarations = __traits(getAttributes, MultiContext)[0].value;
    static assert(declarations.length == 2);
    static assert(declarations[0].name == "persistence/clinic" && declarations[0].unitName == "clinic");
    static assert(declarations[0].properties.length == 0);
    static assert(declarations[1].name == "persistence/audit" && declarations[1].unitName == "audit");
    static assert(declarations[1].type == PersistenceContextType.EXTENDED);
    static assert(declarations[1].synchronization == SynchronizationType.UNSYNCHRONIZED);
    static assert(declarations[1].properties.length == 1);
    static assert(declarations[1].properties[0].name == "vendor.readOnly");
    static assert(declarations[1].properties[0].value == "true");
}
