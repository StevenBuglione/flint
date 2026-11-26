/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.persistence_unit_test;

import flint.jakarta.persistence : PersistenceUnit, PersistenceUnits;

@safe:

@("persistence unit dependencies retain distinct reference and unit names")
unittest
{
    @PersistenceUnit()
    static class Service
    {
    }

    @PersistenceUnits([
        PersistenceUnit("persistence/main", "clinic"),
        PersistenceUnit("persistence/reporting", "reporting")
    ])
    static class MultiUnitService
    {
    }

    enum defaults = __traits(getAttributes, Service)[0];
    assert(defaults.name == "" && defaults.unitName == "");

    enum declarations = __traits(getAttributes, MultiUnitService)[0].value;
    assert(declarations.length == 2);
    assert(declarations[0].name == "persistence/main" && declarations[0].unitName == "clinic");
    assert(declarations[1].name == "persistence/reporting" && declarations[1].unitName == "reporting");
}
