/*
 * Copyright 2017 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/CountAtBucket.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/ValueAtPercentile.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/HistogramSnapshot.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/util/TimeUtils.java
// Modified by the Flint authors.
/// R1 implementation leaf. Applications use the canonical distribution module.
module flint.micrometer.core.instrument.distribution.snapshots;

import flint.java.lang : Double, JavaObject, Long;
import flint.java.util.concurrent : TimeUnit, toNanos;

@safe:

// Snapshot readers and the public TimeUtils method share this conversion without a package import cycle.
package(flint.micrometer.core.instrument) double nanosToUnit(double amount, TimeUnit destinationUnit) pure nothrow @nogc
{
    return destinationUnit == TimeUnit.NANOSECONDS ? amount : amount / destinationUnit.toNanos(1);
}

/// The number of events at or below a histogram bucket.
final class CountAtBucket
{
    private immutable double boundary;
    private immutable double events;

    /// Construct a bucket with an integral boundary.
    deprecated("Use the double boundary") this(long bucket, double count) nothrow @nogc
    {
        this(cast(double) bucket, count);
    }

    /// Construct a bucket with a fractional boundary and count.
    this(double bucket, double count) nothrow @nogc
    {
        boundary = bucket;
        events = count;
    }

    /// The original boundary.
    double bucket() const nothrow @nogc
    {
        return boundary;
    }

    /// Interpret the boundary as nanoseconds and convert it to unit.
    double bucket(TimeUnit unit) const nothrow @nogc
    {
        return nanosToUnit(boundary, unit);
    }

    /// The number of events at or below this bucket.
    double count() const nothrow @nogc
    {
        return events;
    }

    /// Java double equality distinguishes signed zeros and equates NaNs.
    bool equals(Object other) nothrow @nogc
    {
        auto that = cast(CountAtBucket) other;
        return that !is null && equalHistogramValues(boundary, events, that.boundary, that.events);
    }

    /// Hash the boundary and count using Java's double bits.
    int hashCode() const nothrow @nogc
    {
        return hashHistogramValues(boundary, events);
    }

    /// Format the count and its boundary.
    override string toString() const
    {
        return formatHistogramValue(events, boundary, ")");
    }

    mixin JavaObject;
}

/// The value observed at a precomputed percentile.
final class ValueAtPercentile
{
    private immutable double rank;
    private immutable double observation;

    /// Construct a percentile with its observed value.
    this(double percentile, double value) nothrow @nogc
    {
        rank = percentile;
        observation = value;
    }

    /// The requested percentile, as a fraction.
    double percentile() const nothrow @nogc
    {
        return rank;
    }

    /// The original value.
    double value() const nothrow @nogc
    {
        return observation;
    }

    /// Interpret the observation as nanoseconds and convert it to unit.
    double value(TimeUnit unit) const nothrow @nogc
    {
        return nanosToUnit(observation, unit);
    }

    /// Java double equality distinguishes signed zeros and equates NaNs.
    bool equals(Object other) nothrow @nogc
    {
        auto that = cast(ValueAtPercentile) other;
        return that !is null && equalHistogramValues(rank, observation, that.rank, that.observation);
    }

    /// Hash the percentile and value using Java's double bits.
    int hashCode() const nothrow @nogc
    {
        return hashHistogramValues(rank, observation);
    }

    /// Format the observation at its percentile as a percentage.
    override string toString() const
    {
        return formatHistogramValue(observation, rank * 100.0, "%)");
    }

    mixin JavaObject;
}

/// A point-in-time view of distribution statistics.
final class HistogramSnapshot
{
    private immutable long events;
    private immutable double sum;
    private immutable double maximum;

    private this(long count, double total, double max) nothrow @nogc
    {
        events = count;
        sum = total;
        maximum = max;
    }

    // Share the cold allocation across meters that capture only their scalar totals.
    /// Capture totals without percentile values or bucket counts.
    pragma(inline, false) static HistogramSnapshot empty(long count, double total, double max)
    {
        return new HistogramSnapshot(count, total, max);
    }

    /// The total number of recorded events.
    long count() const nothrow @nogc
    {
        return events;
    }

    /// The sum of the recorded values.
    double total() const nothrow @nogc
    {
        return sum;
    }

    /// Convert the sum from nanoseconds to unit.
    double total(TimeUnit unit) const nothrow @nogc
    {
        return nanosToUnit(sum, unit);
    }

    /// The maximum recorded value.
    double max() const nothrow @nogc
    {
        return maximum;
    }

    /// Convert the maximum from nanoseconds to unit.
    double max(TimeUnit unit) const nothrow @nogc
    {
        return nanosToUnit(maximum, unit);
    }

    /// The mean recorded value, or zero for an empty recording count.
    double mean() const nothrow @nogc
    {
        return events == 0 ? 0.0 : sum / events;
    }

    /// Convert the mean from nanoseconds to unit.
    double mean(TimeUnit unit) const nothrow @nogc
    {
        return nanosToUnit(mean(), unit);
    }

    /// The precomputed percentiles. An empty snapshot returns a zero-length D slice (R5).
    ValueAtPercentile[] percentileValues() const nothrow @nogc
    {
        return ValueAtPercentile[].init;
    }

    /// The bucket counts. An empty snapshot returns a zero-length D slice (R5).
    CountAtBucket[] histogramCounts() const nothrow @nogc
    {
        return CountAtBucket[].init;
    }

    /// Format the captured totals.
    override string toString() const
    {
        return "HistogramSnapshot{count=" ~ Long.toString(events) ~ ", total=" ~ Double.toString(
                sum) ~ ", mean=" ~ Double.toString(mean()) ~ ", max=" ~ Double.toString(maximum) ~ "}";
    }
}

private bool equalHistogramValues(double x, double y, double otherX, double otherY) pure nothrow @nogc
{
    return canonicalDoubleBits(x) == canonicalDoubleBits(otherX) && canonicalDoubleBits(y) == canonicalDoubleBits(
            otherY);
}

private ulong canonicalDoubleBits(double value) pure nothrow @nogc
{
    if (value != value)
        return 0x7ff8_0000_0000_0000UL;
    Sample encoded = void;
    encoded.value = value;
    return cast(ulong) encoded.bits;
}

private int hashHistogramValues(double x, double y) pure nothrow @nogc
{
    const a = canonicalDoubleBits(x);
    const b = canonicalDoubleBits(y);
    return cast(int)(31U * cast(uint)(a ^ (a >> 32)) + cast(uint)(b ^ (b >> 32)));
}

private string formatHistogramValue(double value, double boundary, string suffix)
{
    return "(" ~ Double.toString(value) ~ " at " ~ Double.toString(boundary) ~ suffix;
}

package(flint.micrometer.core.instrument.distribution) union Sample
{
    double value;
    long bits;
}
