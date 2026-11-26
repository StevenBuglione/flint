// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/{ScrollPosition,OffsetScrollPosition,KeysetScrollPosition}.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.scroll_position;

import flint.engine.aot.any : Any;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import flint.java.lang : IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException, JavaObject, Long;
import flint.java.util : Collections, Map, RawMap;
import flint.java.util.function_ : IntFunction;

@safe:

private template Keys()
{
    alias Keys = Map!(string, Any);
}

/// A position from which to start or resume scrolling through a query result.
interface ScrollPosition
{
    /// Whether the scroll starts from the beginning of the result.
    bool isInitial();

    /// The initial keyset position in the forward direction.
    static KeysetScrollPosition keyset()()
    {
        return new KeysetScrollPosition(Collections.emptyMap!(string, Any)(), Direction.FORWARD);
    }

    /// The initial offset position, before the first element.
    static OffsetScrollPosition offset()
    {
        return new OffsetScrollPosition(-1);
    }

    /// A position at the given non-negative offset.
    static OffsetScrollPosition offset(long offset)
    {
        if (offset < 0)
            throw new IllegalArgumentException("Offset must not be negative");
        return new OffsetScrollPosition(offset);
    }

    /// A keyset position scrolling forward.
    static KeysetScrollPosition forward()(Keys!() keys)
    {
        return of(keys, Direction.FORWARD);
    }

    /// A keyset position scrolling backward.
    static KeysetScrollPosition backward()(Keys!() keys)
    {
        return of(keys, Direction.BACKWARD);
    }

    /// A keyset position owning a read-only snapshot of the given keys.
    static KeysetScrollPosition of()(Keys!() keys, Direction direction)
    {
        if (keys is null)
            throw new IllegalArgumentException("Keys must not be null");
        if (direction != Direction.FORWARD && direction != Direction.BACKWARD)
            throw new IllegalArgumentException("Invalid scroll direction");
        return new KeysetScrollPosition(Collections.unmodifiableMap(keys), direction);
    }

    /// Keyset scrolling direction.
    enum Direction
    {
        FORWARD,
        BACKWARD,
    }
}

/// A scroll position at a result offset, or before its first element.
final class OffsetScrollPosition : ScrollPosition
{
    private const long offset;

    private this(long offset)
    {
        this.offset = offset;
    }

    /// A function mapping a zero-based index to a position starting at `startOffset`.
    static IntFunction!OffsetScrollPosition positionFunction(long startOffset)
    {
        if (startOffset < 0)
            throw new IllegalArgumentException("Start offset must not be negative");
        return new OffsetPositionFunction(startOffset);
    }

    /// A position function that begins after this position.
    IntFunction!OffsetScrollPosition positionFunction()
    {
        return positionFunction(offset + 1);
    }

    /// The current offset. Throws IllegalStateException at the initial position.
    long getOffset()
    {
        if (isInitial())
            throw new IllegalStateException("Initial state does not have an offset. Make sure to check #isInitial()");
        return offset;
    }

    /// Advance by a signed delta. The resulting offset is at least zero.
    OffsetScrollPosition advanceBy(long delta)
    {
        const value = isInitial() ? delta : offset + delta;
        return new OffsetScrollPosition(value < 0 ? 0 : value);
    }

    override bool isInitial()
    {
        return offset == -1;
    }

    /// Java's value equality.
    bool equals(Object other)
    {
        auto that = cast(OffsetScrollPosition) other;
        return that !is null && offset == that.offset;
    }

    /// Java's hash code.
    int hashCode()
    {
        return 31 + Long.hashCode(offset);
    }

    override string toString()
    {
        return "OffsetScrollPosition [" ~ Long.toString(offset) ~ "]";
    }

    mixin JavaObject;
}

private final class OffsetPositionFunction : IntFunction!OffsetScrollPosition
{
    private const long startOffset;

    this(long startOffset)
    {
        this.startOffset = startOffset;
    }

    override OffsetScrollPosition apply(int index)
    {
        if (index < 0)
            throw new IndexOutOfBoundsException(index);
        return ScrollPosition.offset(startOffset + index);
    }

    bool equals(Object other)
    {
        auto that = cast(OffsetPositionFunction) other;
        return that !is null && startOffset == that.startOffset;
    }

    int hashCode()
    {
        return Long.hashCode(startOffset);
    }

    mixin JavaObject;
}

/// A scroll position based on the keyset of the last result seen.
final class KeysetScrollPosition : ScrollPosition
{
    private alias Direction = ScrollPosition.Direction;
    private RawMap keys;
    private const Direction direction;

    private this(RawMap keys, Direction direction)
    {
        this.keys = keys;
        this.direction = direction;
    }

    /// The read-only keyset for this position.
    Keys!() getKeys()()
    {
        return cast(Keys!()) keys;
    }

    /// The direction of travel through the query result.
    Direction getDirection()
    {
        return direction;
    }

    /// Whether this position scrolls toward the end of the results.
    bool scrollsForward()
    {
        return direction == Direction.FORWARD;
    }

    /// Whether this position scrolls toward the start of the results.
    bool scrollsBackward()
    {
        return direction == Direction.BACKWARD;
    }

    /// The same keyset scrolling forward.
    KeysetScrollPosition forward()
    {
        return scrollsForward() ? this : new KeysetScrollPosition(keys, Direction.FORWARD);
    }

    /// The same keyset scrolling backward.
    KeysetScrollPosition backward()
    {
        return scrollsBackward() ? this : new KeysetScrollPosition(keys, Direction.BACKWARD);
    }

    /// The same keyset with its direction reversed.
    KeysetScrollPosition reverse()
    {
        return new KeysetScrollPosition(keys, scrollsForward() ? Direction.BACKWARD : Direction.FORWARD);
    }

    override bool isInitial()
    {
        return keys.size() == 0;
    }

    /// Java's value equality.
    bool equals(Object other)
    {
        auto that = cast(KeysetScrollPosition) other;
        return that !is null && direction == that.direction && objectEquals(cast(Object) keys, cast(Object) that.keys);
    }

    /// Java's hash code.
    int hashCode()
    {
        return 31 * (31 + cast(int) objectToHash(cast(Object) keys)) + cast(int) direction;
    }

    override string toString()
    {
        auto name = scrollsForward() ? "FORWARD" : "BACKWARD";
        return "KeysetScrollPosition [" ~ name ~ ", " ~ objectToString(cast(Object) keys) ~ "]";
    }

    mixin JavaObject;
}
