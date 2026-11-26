// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/Limit.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.limit;

import flint.engine.aot.objects : statelessInstance;
import flint.java.lang : IllegalStateException, JavaObject;

@safe:

/// Maximum number of results for an operation, or an unlimited result.
/// Spring's permitted implementations are `Limit.Limited` and `Limit.Unlimited` (R16).
interface Limit
{
    /// The shared limit with no maximum.
    static Limit unlimited() nothrow @nogc
    {
        return statelessInstance!Unlimited();
    }

    /// A limit with the given maximum. Interpretation of zero and negative values is up to the operation.
    static Limit of(int max)
    {
        return new Limited(max);
    }

    /// The maximum number of results. Throws IllegalStateException when unlimited.
    int max();

    /// Whether a maximum applies.
    bool isLimited();

    /// Whether the operation has no maximum.
    bool isUnlimited();

    /// Java's default method (R3).
    mixin template Defaults()
    {
        bool isUnlimited()
        {
            return !isLimited();
        }
    }

    /// A limit with a maximum.
    static final class Limited : Limit
    {
        private const int maximum;

        private this(int max)
        {
            maximum = max;
        }

        mixin Limit.Defaults;

        override int max()
        {
            return maximum;
        }

        override bool isLimited()
        {
            return true;
        }

        /// Java's value equality.
        bool equals(Object obj)
        {
            auto other = cast(Limited) obj;
            return other !is null && maximum == other.maximum;
        }

        /// Java's hash code.
        int hashCode()
        {
            return maximum;
        }

        mixin JavaObject;
    }

    /// The absence of a maximum.
    static final class Unlimited : Limit
    {
        package(flint) this()
        {
        }

        mixin Limit.Defaults;

        override int max()
        {
            throw new IllegalStateException(
                    "Unlimited does not define 'max'. Please check 'isLimited' before attempting to read 'max'");
        }

        override bool isLimited()
        {
            return false;
        }
    }
}
