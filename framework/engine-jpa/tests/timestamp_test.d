/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.timestamp_test;

import flint.arena : Status;
import flint.engine.jpa.timestamp : TimestampParts, decodeTimestampMicros, encodeTimestampMicros;

@safe:

@("timestamp rounding preserves the signed epoch across midnight")
unittest
{
    const belowHalf = encodeTimestampMicros(-1, 86_399_999_999_499);
    const atHalf = encodeTimestampMicros(-1, 86_399_999_999_500);
    assert(belowHalf.ok && belowHalf.value == -1);
    assert(atHalf.ok && atHalf.value == 0);
    const negative = decodeTimestampMicros(-1);
    assert(negative.ok && negative.value == TimestampParts(-1, 86_399_999_999_000));
    const epoch = decodeTimestampMicros(0);
    assert(epoch.ok && epoch.value == TimestampParts(0, 0));
}

@("timestamp conversions enforce the finite JDBC round-trip range before arithmetic")
unittest
{
    const first = encodeTimestampMicros(-719_162, 0);
    const last = encodeTimestampMicros(2_932_896, 86_399_999_999_499);
    assert(first.ok && first.value == -62_135_596_800_000_000);
    assert(last.ok && last.value == 253_402_300_799_999_999);
    assert(decodeTimestampMicros(first.value).value == TimestampParts(-719_162, 0));
    assert(decodeTimestampMicros(last.value).value == TimestampParts(2_932_896, 86_399_999_999_000));
    assert(encodeTimestampMicros(2_932_896, 86_399_999_999_500).error.code == Status.invalidArgument);
    assert(encodeTimestampMicros(long.min, 0).error.code == Status.invalidArgument);
    assert(encodeTimestampMicros(long.max, 0).error.code == Status.invalidArgument);
    assert(encodeTimestampMicros(0, -1).error.code == Status.invalidArgument);
    assert(encodeTimestampMicros(0, 86_400_000_000_000).error.code == Status.invalidArgument);
    assert(decodeTimestampMicros(first.value - 1).error.code == Status.invalidArgument);
    assert(decodeTimestampMicros(last.value + 1).error.code == Status.invalidArgument);
    assert(decodeTimestampMicros(long.min).error.code == Status.invalidArgument);
    assert(decodeTimestampMicros(long.max).error.code == Status.invalidArgument);
}
