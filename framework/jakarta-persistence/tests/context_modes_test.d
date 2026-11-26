/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.context_modes_test;

import flint.jakarta.persistence : ParameterMode, PersistenceContextType, SynchronizationType;
import std.traits : EnumMembers;

@safe:

@("Jakarta context and parameter modes preserve the upstream members and order")
unittest
{
    static assert([EnumMembers!ParameterMode] == [
        ParameterMode.IN, ParameterMode.INOUT, ParameterMode.OUT, ParameterMode.REF_CURSOR
    ]);
    static assert([EnumMembers!PersistenceContextType] == [
        PersistenceContextType.TRANSACTION, PersistenceContextType.EXTENDED
    ]);
    static assert([EnumMembers!SynchronizationType] == [
        SynchronizationType.SYNCHRONIZED, SynchronizationType.UNSYNCHRONIZED
    ]);
    static assert(PersistenceContextType.init == PersistenceContextType.TRANSACTION);
    static assert(SynchronizationType.init == SynchronizationType.SYNCHRONIZED);
}
