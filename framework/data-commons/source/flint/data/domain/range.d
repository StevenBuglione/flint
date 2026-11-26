// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/Range.java
// Copyright 2015-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.range;

import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, valueOf;
import flint.java.util : Comparator, Objects, Optional, compareNatural;
import flint.java.util.function_ : Function;

@safe:

// Java erases the element type when comparing one range to another.
private abstract class RangeValue
{
    protected abstract Object lowerEndpoint();
    protected abstract Object upperEndpoint();
}

private abstract class BoundValue
{
    abstract bool isBounded();
    abstract bool isInclusive();
    protected abstract Object referenceValue();
}

/// An interval with independently inclusive, exclusive or absent bounds.
final class Range(T) : RangeValue
{
    private alias Compare = int delegate(T, T) @safe;

    private Bound lower;
    private Bound upper;

    private this(Bound lower, Bound upper)
    {
        if (lower is null)
            throw new IllegalArgumentException("Lower bound must not be null");
        if (upper is null)
            throw new IllegalArgumentException("Upper bound must not be null");
        this.lower = lower;
        this.upper = upper;
    }

    /// An interval with neither bound.
    static Range unbounded()
    {
        auto bound = Bound.unbounded();
        return new Range(bound, bound);
    }

    /// An interval that includes both endpoints.
    static Range closed(T from, T to)
    {
        return new Range(Bound.inclusive(from), Bound.inclusive(to));
    }

    /// An interval that excludes both endpoints.
    static Range open(T from, T to)
    {
        return new Range(Bound.exclusive(from), Bound.exclusive(to));
    }

    /// An interval that excludes its lower endpoint and includes its upper endpoint.
    static Range leftOpen(T from, T to)
    {
        return new Range(Bound.exclusive(from), Bound.inclusive(to));
    }

    /// An interval that includes its lower endpoint and excludes its upper endpoint.
    static Range rightOpen(T from, T to)
    {
        return new Range(Bound.inclusive(from), Bound.exclusive(to));
    }

    /// An interval with only an upper bound.
    static Range leftUnbounded(Bound to)
    {
        return new Range(Bound.unbounded(), to);
    }

    /// An interval with only a lower bound.
    static Range rightUnbounded(Bound from)
    {
        return new Range(from, Bound.unbounded());
    }

    /// Start a range builder with its lower bound.
    static RangeBuilder from(Bound lower)
    {
        if (lower is null)
            throw new IllegalArgumentException("Lower bound must not be null");
        return new RangeBuilder(lower);
    }

    /// An interval with the given bounds.
    static Range of(Bound lower, Bound upper)
    {
        return new Range(lower, upper);
    }

    /// An interval consisting of one value.
    static Range just(T value)
    {
        auto bound = Bound.inclusive(value);
        return new Range(bound, bound);
    }

    /// Whether the interval contains `value` in the element type's natural order.
    bool contains(T value)
    {
        return contains(value, (T first, T second) => compareValues(first, second));
    }

    private static int compareValues(T first, T second)
    {
        static if (is(T == float) || is(T == double))
        {
            import std.math.traits : signbit;

            // Java Float and Double place NaN last and negative zero before positive zero.
            if (first != first)
                return second != second ? 0 : 1;
            if (second != second)
                return -1;
            if (first == 0 && second == 0)
                return signbit(second) - signbit(first);
        }
        return compareNatural(first, second);
    }

    /// Whether the interval contains `value` in the given order.
    bool contains(T value, Comparator!T comparator)
    {
        return contains(value, comparator is null ? null : comparator.asDelegate());
    }

    /// Whether the interval contains `value` in the order defined by a delegate (R9).
    bool contains(T value, scope Compare compare)
    {
        if (Objects.isNull(value))
            throw new IllegalArgumentException("Reference value must not be null");
        const above = lower.includes(value, compare, true);
        const below = upper.includes(value, compare, false);
        return above && below;
    }

    /// Apply a function to present bounds, preserving open and closed endpoints.
    Range!R map(R)(Function!(T, R) mapper)
    {
        if (mapper is null)
            throw new IllegalArgumentException("Mapping function must not be null");
        return map(mapper.asDelegate());
    }

    /// Apply a delegate to present bounds. A null result removes that bound.
    Range!R map(R)(scope R delegate(T) @safe mapper)
    {
        if (mapper is null)
            throw new IllegalArgumentException("Mapping function must not be null");
        return Range!R.of(lower.map(mapper), upper.map(mapper));
    }

    /// The lower bound, which can be unbounded.
    Bound getLowerBound()
    {
        return lower;
    }

    /// The upper bound, which can be unbounded.
    Bound getUpperBound()
    {
        return upper;
    }

    /// Whether the other interval has equal bounds.
    bool equals(Object other)
    {
        auto that = cast(RangeValue) other;
        return that !is null && lower.equals(that.lowerEndpoint()) && upper.equals(that.upperEndpoint());
    }

    protected override Object lowerEndpoint()
    {
        return lower;
    }

    protected override Object upperEndpoint()
    {
        return upper;
    }

    /// Java's value hash.
    int hashCode()
    {
        return Objects.hash(lower, upper);
    }

    override string toString()
    {
        return lower.toPrefixString() ~ "-" ~ upper.toSuffixString();
    }

    mixin JavaObject;

    /// A present inclusive or exclusive boundary, or an unbounded end.
    static final class Bound : BoundValue
    {
        private Optional!T value;
        private const bool inclusive_;

        private this(Optional!T value, bool inclusive)
        {
            this.value = value;
            inclusive_ = inclusive;
        }

        /// An absent bound.
        static Bound unbounded()
        {
            return new Bound(Optional!T.empty(), true);
        }

        /// A bound that includes its endpoint.
        static Bound inclusive(T value)
        {
            return of(value, true);
        }

        /// A bound that excludes its endpoint.
        static Bound exclusive(T value)
        {
            return of(value, false);
        }

        private static Bound of(T value, bool inclusive)
        {
            if (Objects.isNull(value))
                throw new IllegalArgumentException("Value must not be null");
            return new Bound(Optional!T.of(value), inclusive);
        }

        /// Whether the boundary has an endpoint.
        override bool isBounded()
        {
            return value.isPresent();
        }

        /// Whether the boundary is inclusive.
        override bool isInclusive()
        {
            return inclusive_;
        }

        /// The optional endpoint.
        Optional!T getValue()
        {
            return value;
        }

        /// Map an endpoint. A null result or an absent endpoint gives an unbounded end.
        Range!R.Bound map(R)(Function!(T, R) mapper)
        {
            if (mapper is null)
                throw new IllegalArgumentException("Mapping function must not be null");
            return map(mapper.asDelegate());
        }

        /// Map an endpoint using a delegate (R9).
        Range!R.Bound map(R)(scope R delegate(T) @safe mapper)
        {
            if (mapper is null)
                throw new IllegalArgumentException("Mapping function must not be null");
            if (!isBounded())
                return Range!R.Bound.unbounded();
            R mapped = mapper(value.get());
            return Objects.isNull(mapped) ? Range!R.Bound.unbounded() : Range!R.Bound.of(mapped, inclusive_);
        }

        private bool includes(T candidate, scope Compare compare, bool lower)
        {
            if (!isBounded())
                return true;
            if (compare is null)
                throw new NullPointerException();
            const result = compare(value.get(), candidate);
            return (inclusive_ && result == 0) || (lower ? result < 0 : result > 0);
        }

        private string toPrefixString()
        {
            return !isBounded() ? "unbounded" : (inclusive_ ? "[" : "(") ~ valueOf(value.get());
        }

        private string toSuffixString()
        {
            return !isBounded() ? "unbounded" : valueOf(value.get()) ~ (inclusive_ ? "]" : ")");
        }

        /// Java's value equality.
        bool equals(Object other)
        {
            if (this is other)
                return true;
            auto that = cast(BoundValue) other;
            if (that is null)
                return false;
            if (!isBounded() || !that.isBounded())
                return isBounded() == that.isBounded();
            if (inclusive_ != that.isInclusive())
                return false;

            if (auto typed = cast(Bound) that)
            {
                static if (is(T == float) || is(T == double))
                    return compareValues(value.get(), typed.value.get()) == 0;
                else
                    return value == typed.value;
            }
            return referenceValue() !is null && Objects.equals(referenceValue(), that.referenceValue());
        }

        protected override Object referenceValue()
        {
            static if (is(T == class) || is(T == interface))
                return isBounded() ? cast(Object) value.get() : null;
            else
                return null;
        }

        /// Java's value hash.
        int hashCode()
        {
            return isBounded() ? 31 * Objects.hashCode(value.get()) + (inclusive_ ? 1 : 0) : 0;
        }

        override string toString()
        {
            return isBounded() ? valueOf(value.get()) : "unbounded";
        }

        mixin JavaObject;
    }

    /// A range builder that holds the lower bound.
    static class RangeBuilder
    {
        private Bound lower;

        private this(Bound lower)
        {
            this.lower = lower;
        }

        /// Finish the range with its upper bound.
        Range to(Bound upper)
        {
            return new Range(lower, upper);
        }
    }
}
