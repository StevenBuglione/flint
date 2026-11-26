/*
 * Ported from hibernate-orm 7.1.0: hibernate-core/src/main/java/org/hibernate/type/AbstractStandardBasicType.java
 * and the AbstractClassJavaType and PrimitiveByteArrayJavaType descriptors in org.hibernate.type.descriptor.java.
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 * Modified by the Flint authors: typed scalar comparison and context arena byte copies.
 */

/// Loaded value snapshots for dirty checking in a persistence context.
module flint.engine.jpa.snapshot;

import flint.arena : Buffer, Error, RequestArena, Result, Status;
import flint.engine.jpa.mapping : AttributeKind, AttributeValue;
import std.math.traits : isNaN;

@safe:

/// A captured attribute. Text and binary snapshots keep an opaque context arena handle.
struct AttributeSnapshot
{
    private AttributeKind kind;
    private long integer;
    private double floatingPoint;
    private Buffer bytes;

    private this(AttributeKind kind) pure nothrow @nogc
    {
        this.kind = kind;
    }
}

private alias SnapshotResult = Result!AttributeSnapshot;
private alias MatchResult = Result!bool;

/// Captures an attribute in the context's arena. On exhaustion existing snapshots remain available.
SnapshotResult captureAttribute(scope ref RequestArena arena, scope const ref AttributeValue value) nothrow @nogc
{
    auto snapshot = AttributeSnapshot(value.kind);
    switch (value.kind)
    {
    case AttributeKind.nullValue:
        break;
    case AttributeKind.integer:
    case AttributeKind.date:
    case AttributeKind.timestamp:
        snapshot.integer = value.integer;
        break;
    case AttributeKind.boolean:
        snapshot.integer = value.boolean;
        break;
    case AttributeKind.floatingPoint:
        snapshot.floatingPoint = value.floatingPoint;
        break;
    case AttributeKind.text:
    case AttributeKind.binary:
        const payload = bytesOf(value);
        if (payload is null)
            return SnapshotResult(AttributeSnapshot.init, Error(Status.invalidArgument, "missing JPA byte payload"));
        const copied = arena.copyIn(payload);
        if (!copied.ok)
            return SnapshotResult(AttributeSnapshot.init, copied.error);
        snapshot.bytes = copied.value;
        break;
    default:
        return SnapshotResult(AttributeSnapshot.init, Error(Status.unsupported, "unsupported JPA snapshot kind"));
    }
    return SnapshotResult(snapshot);
}

/// Checks the current attribute against its baseline. Byte snapshots require their original live arena.
MatchResult matchesAttribute(scope ref RequestArena arena, scope const ref AttributeSnapshot snapshot,
        scope const ref AttributeValue current) nothrow @nogc
{
    if (snapshot.kind == AttributeKind.text || snapshot.kind == AttributeKind.binary)
        return matchesBytes(arena, snapshot, current);
    if (snapshot.kind != current.kind)
        return MatchResult(false);
    switch (current.kind)
    {
    case AttributeKind.nullValue:
        return MatchResult(true);
    case AttributeKind.integer:
    case AttributeKind.date:
    case AttributeKind.timestamp:
        return MatchResult(snapshot.integer == current.integer);
    case AttributeKind.boolean:
        return MatchResult(snapshot.integer == current.boolean);
    case AttributeKind.floatingPoint:
        // Like Java Double.equals, signed zeros differ and all NaNs compare equal.
        return MatchResult((snapshot.floatingPoint is current.floatingPoint)
                || (isNaN(snapshot.floatingPoint) && isNaN(current.floatingPoint)));
    default:
        return MatchResult(false, Error(Status.unsupported, "unsupported JPA snapshot kind"));
    }
}

private MatchResult matchesBytes(scope ref RequestArena arena, scope const ref AttributeSnapshot snapshot,
        scope const ref AttributeValue current) nothrow @nogc
{
    const sameKind = snapshot.kind == current.kind;
    scope const(ubyte)[] payload;
    if (sameKind)
    {
        payload = bytesOf(current);
        if (payload is null)
            return MatchResult(false, Error(Status.invalidArgument, "missing JPA byte payload"));
    }
    bool same;
    const status = arena.read(snapshot.bytes, (scope const(ubyte)[] stored) nothrow @nogc {
        same = sameKind && stored == payload;
    });
    if (status != Status.ok)
        return MatchResult(false, Error(status, "invalid JPA byte snapshot"));
    return MatchResult(same);
}

private const(ubyte)[] bytesOf(return scope const ref AttributeValue value) pure nothrow @nogc
{
    return value.kind == AttributeKind.text ? cast(const(ubyte)[]) value.text : value.bytes;
}
