/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.engine.jpa.snapshot_test;

import flint.arena : RequestArena, Status;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue;
import flint.engine.jpa.snapshot : AttributeSnapshot, captureAttribute, matchesAttribute;
import std.traits : hasIndirections;

@safe:

@("a byte snapshot copies mutable input and rejects retired or foreign arenas")
unittest
{
    static assert(!hasIndirections!AttributeSnapshot);
    ubyte[32] backing;
    ubyte[32] foreignBacking;
    ubyte[3] bytes = [1, 2, 3];
    scope arena = RequestArena(backing[]);
    scope foreign = RequestArena(foreignBacking[]);
    scope value = AttributeValue(kind: AttributeKind.binary, bytes: bytes[]);
    const snapshot = captureAttribute(arena, value);
    assert(snapshot.ok);
    assert(matchesAttribute(arena, snapshot.value, value).value);
    bytes[1] = 7;
    const edited = matchesAttribute(arena, snapshot.value, value);
    assert(edited.ok && !edited.value);
    assert(matchesAttribute(foreign, snapshot.value, value).error.code == Status.invalidArgument);
    assert(arena.reset() == Status.ok);
    assert(matchesAttribute(arena, snapshot.value, value).error.code == Status.invalidArgument);
    const AttributeValue nullValue;
    assert(matchesAttribute(arena, snapshot.value, nullValue).error.code == Status.invalidArgument);
}

@("ordinary attribute equality distinguishes NULL, empty values and signed zeros")
unittest
{
    ubyte[32] backing;
    scope arena = RequestArena(backing[]);
    const empty = AttributeValue(kind: AttributeKind.text, text: "x"[0 .. 0]);
    const snapshot = captureAttribute(arena, empty);
    assert(snapshot.ok);
    const emptyMatch = matchesAttribute(arena, snapshot.value, empty);
    assert(emptyMatch.ok && emptyMatch.value);
    const AttributeValue nullValue;
    const nullMatch = matchesAttribute(arena, snapshot.value, nullValue);
    assert(nullMatch.ok && !nullMatch.value);

    const positive = AttributeValue(kind: AttributeKind.floatingPoint, floatingPoint: 0.0);
    const negative = AttributeValue(kind: AttributeKind.floatingPoint, floatingPoint: -0.0);
    const zero = captureAttribute(arena, positive);
    assert(zero.ok && matchesAttribute(arena, zero.value, positive).value);
    const differentZero = matchesAttribute(arena, zero.value, negative);
    assert(differentZero.ok && !differentZero.value);

    const nan = AttributeValue(kind: AttributeKind.floatingPoint, floatingPoint: double.nan);
    const otherNan = AttributeValue(kind: AttributeKind.floatingPoint, floatingPoint: -double.nan);
    const savedNan = captureAttribute(arena, nan);
    assert(savedNan.ok && matchesAttribute(arena, savedNan.value, otherNan).value);
}

@("failed snapshot capture keeps the previous arena contents available")
unittest
{
    align(8) ubyte[8] backing;
    scope arena = RequestArena(backing[]);
    const valid = AttributeValue(kind: AttributeKind.text, text: "old");
    const snapshot = captureAttribute(arena, valid);
    assert(snapshot.ok);
    const used = arena.stats().used;
    const oversized = AttributeValue(kind: AttributeKind.text, text: "data too large");
    assert(captureAttribute(arena, oversized).error.code == Status.outOfMemory);
    assert(arena.stats().used == used);
    assert(matchesAttribute(arena, snapshot.value, valid).value);

    const missingBytes = AttributeValue(kind: AttributeKind.binary);
    assert(captureAttribute(arena, missingBytes).error.code == Status.invalidArgument);
    const unsupported = AttributeValue(kind: AttributeKind.decimal, integer: 100, scale: 2);
    assert(captureAttribute(arena, unsupported).error.code == Status.unsupported);
}
