/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.flush_mode_test;

import flint.jakarta.persistence : FlushModeType;

@safe:

@("Jakarta flush modes preserve declared order and are distinct")
unittest
{
    assert(cast(int) FlushModeType.COMMIT == 0);
    assert(cast(int) FlushModeType.AUTO == 1);
}
