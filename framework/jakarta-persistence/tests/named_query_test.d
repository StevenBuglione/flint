/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.named_query_test;

import flint.jakarta.persistence : LockModeType, NamedQueries, NamedQuery, QueryHint;
import flint.java.classref : classOf;

@safe:

private struct OwnerRow
{
    long id;
}

@("named query metadata keeps default and explicit locking distinct")
unittest
{
    @NamedQuery("Owner.all", "select o from Owner o")
    @NamedQuery("Owner.locked", "select o from Owner o where o.id = :id", classOf!OwnerRow,
            LockModeType.PESSIMISTIC_WRITE, [QueryHint("100", "jakarta.persistence.lock.timeout")])
    static class Owner
    {
    }

    enum defaultQuery = __traits(getAttributes, Owner)[0];
    enum lockedQuery = __traits(getAttributes, Owner)[1];
    assert(defaultQuery.lockMode == LockModeType.NONE);
    assert(defaultQuery.resultClass.name == "" && defaultQuery.hints.length == 0);
    assert(lockedQuery.name == "Owner.locked" && lockedQuery.query == "select o from Owner o where o.id = :id");
    assert(lockedQuery.resultClass == classOf!OwnerRow);
    assert(lockedQuery.lockMode == LockModeType.PESSIMISTIC_WRITE);
    assert(lockedQuery.hints[0].name == "jakarta.persistence.lock.timeout");
    assert(lockedQuery.hints[0].value == "100");
}

@("named query containers preserve all declared query names")
unittest
{
    @NamedQueries([
        NamedQuery("Owner.all", "select o from Owner o"),
        NamedQuery("Owner.ids", "select o.id from Owner o")
    ])
    static class Owner
    {
    }

    enum declared = __traits(getAttributes, Owner)[0].value;
    assert(declared.length == 2 && declared[0].name == "Owner.all" && declared[1].name == "Owner.ids");
}
