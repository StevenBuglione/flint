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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/TimeWindowMax.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/DistributionStatisticConfig.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/Histogram.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/NoopHistogram.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.distribution;

import core.atomic : atomicLoad, atomicStore, cas;
import core.sync.mutex : Mutex;
import flint.engine.aot.objects : statelessInstance;
import flint.java.lang : AutoCloseable, Double, IllegalArgumentException, NullPointerException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.micrometer.core.instrument : Clock;
import flint.micrometer.core.instrument.config : InvalidConfigurationException, validateDistributionBufferLength;
import flint.micrometer.core.instrument.internal : Mergeable;
import flint.micrometer.core.instrument.distribution.snapshots : Sample;
public import flint.micrometer.core.instrument : HistogramSupport;
public import flint.micrometer.core.instrument.distribution.snapshots : CountAtBucket,
    HistogramSnapshot, ValueAtPercentile;
import std.typecons : Nullable;

@safe:

/// Record distribution measurements and combine them with the meter's totals.
interface Histogram : AutoCloseable
{
    /// Record an integral measurement.
    void recordLong(long value) nothrow @nogc;

    /// Record a fractional measurement.
    void recordDouble(double value) nothrow @nogc;

    /// Capture distribution statistics with the supplied totals.
    HistogramSnapshot takeSnapshot(long count, double total, double max);

    /// Micrometer's default close method (R3).
    mixin template Defaults()
    {
        override void close() nothrow @nogc
        {
        }
    }
}

/// A histogram for meters that have disabled bucket and percentile collection.
final class NoopHistogram : Histogram
{
    // The shared stateless-instance helper constructs this once for all threads.
    package(flint) this() pure nothrow @nogc
    {
    }

    /// The shared histogram (R3).
    static @property NoopHistogram INSTANCE() nothrow @nogc
    {
        return statelessInstance!NoopHistogram();
    }

    override void recordLong(long value) nothrow @nogc
    {
    }

    override void recordDouble(double value) nothrow @nogc
    {
    }

    override HistogramSnapshot takeSnapshot(long count, double total, double max)
    {
        return HistogramSnapshot.empty(count, total, max);
    }

    mixin Histogram.Defaults;
}

private alias HistogramFlag = Nullable!bool;
private alias StatisticInt = Nullable!int;
private alias StatisticDouble = Nullable!double;
private alias StatisticLong = Nullable!long;
private alias Expiry = Nullable!Duration;
private alias Doubles = Nullable!(double[]);
private alias Longs = Nullable!(long[]);

/// Settings for distribution windows, percentile series, and service-level objectives.
class DistributionStatisticConfig : Mergeable!DistributionStatisticConfig
{
    /// Standard settings for a decaying distribution.
    static immutable DEFAULT = new immutable DistributionStatisticConfig(Duration.ofMinutes(2));

    /// A configuration with all settings unset.
    static immutable NONE = new immutable DistributionStatisticConfig;

    private HistogramFlag histogram;
    private Doubles percentileValues;
    private StatisticInt precision;
    private Doubles objectives;
    private StatisticDouble minimum;
    private StatisticDouble maximum;
    private Expiry expiryValue;
    private StatisticInt buffers;

    /// Construct a configuration with all values unset.
    this() pure nothrow @nogc
    {
    }

    private this(Duration defaultExpiry) pure nothrow @nogc
    {
        histogram = HistogramFlag(false);
        precision = StatisticInt(1);
        minimum = StatisticDouble(1.0);
        maximum = StatisticDouble(double.infinity);
        expiryValue = Expiry(defaultExpiry);
        buffers = StatisticInt(3);
    }

    /// Start a new configuration.
    static Builder builder()
    {
        return Builder();
    }

    /// Supply unset settings from the parent.
    override DistributionStatisticConfig merge(DistributionStatisticConfig parent)
    {
        return mergeFrom(this, parent);
    }

    /// Supply unset settings from a read-only parent, including DEFAULT or NONE.
    override DistributionStatisticConfig merge(const DistributionStatisticConfig parent)
    {
        return mergeFrom(this, parent);
    }

    /// Merge from a read-only child and parent.
    override DistributionStatisticConfig merge(const DistributionStatisticConfig parent) const
    {
        return mergeFrom(this, parent);
    }

    private static DistributionStatisticConfig mergeFrom(Child, Parent)(Child child, Parent parent)
    {
        auto merged = child.mergeScalars(parent);
        merged.percentileValues = child.percentileValues.isNull()
            ? owned(parent.percentileValues) : owned(child.percentileValues);
        merged.objectives = child.objectives.isNull() ? owned(parent.objectives) : owned(child.objectives);
        validate(merged);
        return merged;
    }

    private DistributionStatisticConfig mergeScalars(const DistributionStatisticConfig parent) const
    {
        if (parent is null && hasUnsetSettings())
            throw missingSetting("parent");
        auto merged = new DistributionStatisticConfig;
        merged.histogram = histogram.isNull() ? parent.histogram : histogram;
        merged.precision = precision.isNull() ? parent.precision : precision;
        merged.minimum = minimum.isNull() ? parent.minimum : minimum;
        merged.maximum = maximum.isNull() ? parent.maximum : maximum;
        merged.expiryValue = expiryValue.isNull() ? parent.expiryValue : expiryValue;
        merged.buffers = buffers.isNull() ? parent.buffers : buffers;
        return merged;
    }

    private bool hasUnsetSettings() const nothrow @nogc
    {
        return histogram.isNull() || percentileValues.isNull() || precision.isNull()
            || objectives.isNull() || minimum.isNull() || maximum.isNull() || expiryValue.isNull() || buffers.isNull();
    }

    private static Doubles owned(Doubles values) nothrow @nogc
    {
        return values;
    }

    private static Doubles owned(const Doubles values)
    {
        return values.isNull() ? Doubles.init : Doubles(values.get().dup);
    }

    /// Whether to publish aggregable histogram buckets.
    HistogramFlag isPercentileHistogram() const nothrow @nogc
    {
        return histogram;
    }

    /// Requested percentiles, or absent when unspecified.
    inout(Doubles) getPercentiles() inout nothrow @nogc
    {
        return percentileValues;
    }

    /// Digits of precision used for percentile approximations.
    StatisticInt getPercentilePrecision() const nothrow @nogc
    {
        return precision;
    }

    /// The lower bound for histogram buckets.
    deprecated("Use getMinimumExpectedValueAsDouble") StatisticDouble getMinimumExpectedValue() const nothrow @nogc
    {
        return getMinimumExpectedValueAsDouble();
    }

    /// The lower bound for histogram buckets.
    StatisticDouble getMinimumExpectedValueAsDouble() const nothrow @nogc
    {
        return minimum;
    }

    /// The upper bound for histogram buckets.
    deprecated("Use getMaximumExpectedValueAsDouble") StatisticDouble getMaximumExpectedValue() const nothrow @nogc
    {
        return getMaximumExpectedValueAsDouble();
    }

    /// The upper bound for histogram buckets.
    StatisticDouble getMaximumExpectedValueAsDouble() const nothrow @nogc
    {
        return maximum;
    }

    /// The duration of one rotation bucket.
    Expiry getExpiry() const nothrow @nogc
    {
        return expiryValue;
    }

    /// The number of buckets in the ring.
    StatisticInt getBufferLength() const nothrow @nogc
    {
        return buffers;
    }

    /// Individually configured histogram boundaries.
    deprecated("Use getServiceLevelObjectiveBoundaries") inout(Doubles) getSlaBoundaries() inout nothrow @nogc
    {
        return getServiceLevelObjectiveBoundaries();
    }

    /// Individually configured histogram boundaries.
    inout(Doubles) getServiceLevelObjectiveBoundaries() inout nothrow @nogc
    {
        return objectives;
    }

    /// Whether any local percentile series are configured.
    bool isPublishingPercentiles() const nothrow @nogc
    {
        return !percentileValues.isNull() && percentileValues.get().length != 0;
    }

    /// Whether aggregable buckets or service-level-objective buckets are configured.
    bool isPublishingHistogram() const nothrow @nogc
    {
        return (!histogram.isNull() && histogram.get()) || (!objectives.isNull() && objectives.get().length != 0);
    }

    /// Configure distribution statistics before registering a meter.
    static struct Builder
    {
        private DistributionStatisticConfig config;

        /// Construct a builder with its own configuration.
        static Builder opCall()
        {
            Builder builder;
            builder.config = new DistributionStatisticConfig;
            return builder;
        }

        private DistributionStatisticConfig settings()
        {
            if (config is null)
                config = new DistributionStatisticConfig;
            return config;
        }

        /// Enable or disable aggregable histogram buckets.
        ref Builder percentilesHistogram(bool enabled) return
        {
            return percentilesHistogram(HistogramFlag(enabled));
        }

        /// Enable, disable, or unset aggregable histogram buckets.
        ref Builder percentilesHistogram(HistogramFlag enabled) return
        {
            settings().histogram = enabled;
            return this;
        }

        /// Set local percentiles, copying any borrowed variadic input.
        ref Builder percentiles(scope const(double)[] values...) return
        {
            return percentiles(Doubles(values.dup));
        }

        /// Supply an owned percentile array or unset the option.
        ref Builder percentiles(Doubles values) return
        {
            settings().percentileValues = values;
            return this;
        }

        /// Set the digits of precision for percentile calculations.
        ref Builder percentilePrecision(int digits) return
        {
            return percentilePrecision(StatisticInt(digits));
        }

        /// Set or unset the digits of precision.
        ref Builder percentilePrecision(StatisticInt digits) return
        {
            settings().precision = digits;
            return this;
        }

        /// Set explicit histogram boundaries, copying any borrowed variadic input.
        ref Builder serviceLevelObjectives(scope const(double)[] values...) return
        {
            return serviceLevelObjectives(Doubles(values.dup));
        }

        /// Supply an owned array of explicit boundaries or unset the option.
        ref Builder serviceLevelObjectives(Doubles values) return
        {
            settings().objectives = values;
            return this;
        }

        /// Set explicit histogram boundaries.
        deprecated("Use serviceLevelObjectives") ref Builder sla(scope const(double)[] values...) return
        {
            return serviceLevelObjectives(values);
        }

        /// Supply an owned array of histogram boundaries or unset the option.
        deprecated("Use serviceLevelObjectives") ref Builder sla(Doubles values) return
        {
            return serviceLevelObjectives(values);
        }

        /// Convert a legacy integral boundary array to double.
        deprecated("Use serviceLevelObjectives") ref Builder sla(scope const(long)[] values) return
        {
            auto converted = new double[values.length];
            foreach (i, value; values)
                converted[i] = cast(double) value;
            return serviceLevelObjectives(Doubles(converted));
        }

        /// Convert legacy integral boundaries when present.
        deprecated("Use serviceLevelObjectives") ref Builder sla(Longs values) return
        {
            if (values.isNull())
                return this;
            return sla(values.get());
        }

        /// Set the lower bound for buckets.
        ref Builder minimumExpectedValue(double value) return
        {
            return minimumExpectedValue(StatisticDouble(value));
        }

        /// Set or unset the lower bound.
        ref Builder minimumExpectedValue(StatisticDouble value) return
        {
            settings().minimum = value;
            return this;
        }

        /// Set the legacy integral lower bound when present.
        deprecated("Use the double lower bound") ref Builder minimumExpectedValue(StatisticLong value) return
        {
            if (value.isNull())
                return this;
            return minimumExpectedValue(cast(double) value.get());
        }

        /// Set the upper bound for buckets.
        ref Builder maximumExpectedValue(double value) return
        {
            return maximumExpectedValue(StatisticDouble(value));
        }

        /// Set or unset the upper bound.
        ref Builder maximumExpectedValue(StatisticDouble value) return
        {
            settings().maximum = value;
            return this;
        }

        /// Set the legacy integral upper bound when present.
        deprecated("Use the double upper bound") ref Builder maximumExpectedValue(StatisticLong value) return
        {
            if (value.isNull())
                return this;
            return maximumExpectedValue(cast(double) value.get());
        }

        /// Set the duration of each rotation bucket.
        ref Builder expiry(Duration duration) return
        {
            return expiry(Expiry(duration));
        }

        /// Set or unset the duration of each rotation bucket.
        ref Builder expiry(Expiry duration) return
        {
            settings().expiryValue = duration;
            return this;
        }

        /// Set the number of rotation buckets.
        ref Builder bufferLength(int length) return
        {
            return bufferLength(StatisticInt(length));
        }

        /// Set or unset the number of rotation buckets.
        ref Builder bufferLength(StatisticInt length) return
        {
            settings().buffers = length;
            return this;
        }

        /// Validate and return the configuration held by this builder.
        DistributionStatisticConfig build()
        {
            auto result = settings();
            validate(result);
            return result;
        }
    }

    private static void validate(const DistributionStatisticConfig config)
    {
        if (!config.buffers.isNull())
            validateDistributionBufferLength(config.buffers.get());

        if (!config.percentileValues.isNull())
            foreach (value; config.percentileValues.get())
                if (value < 0.0 || value > 1.0)
                    reject(
                            "percentiles must contain only the values between 0.0 and 1.0. Found " ~ Double.toString(
                            value));

        if (!config.minimum.isNull() && config.minimum.get() <= 0.0)
            reject("minimumExpectedValue (" ~ Double.toString(config.minimum.get()) ~ ") must be greater than 0.");
        if (!config.maximum.isNull() && config.maximum.get() <= 0.0)
            reject("maximumExpectedValue (" ~ Double.toString(config.maximum.get()) ~ ") must be greater than 0.");
        if (!config.minimum.isNull() && !config.maximum.isNull() && config.minimum.get() > config.maximum.get())
        {
            const maximum = Double.toString(config.maximum.get());
            const minimum = Double.toString(config.minimum.get());
            reject("maximumExpectedValue (" ~ maximum
                    ~ ") must be equal to or greater than minimumExpectedValue (" ~ minimum ~ ").");
        }

        if (!config.objectives.isNull())
            foreach (value; config.objectives.get())
                if (value <= 0.0)
                    reject("serviceLevelObjectiveBoundaries must contain only the values greater than 0. Found "
                            ~ Double.toString(value));
    }

    private static void reject(string message)
    {
        throw new InvalidConfigurationException("Invalid distribution configuration: " ~ message);
    }
}

/// A distribution maximum that returns to zero when all of its time buckets expire.
class TimeWindowMax
{
    private Clock wallClock;
    private immutable long rotateFrequencyMillis;
    private shared(long)[] buckets;
    private shared long lastRotateMillis;
    private shared bool rotating;
    private Mutex rotationGate;
    private size_t currentBucket;

    /// Preallocate the expiration window defined by the distribution configuration.
    this(Clock clock, const DistributionStatisticConfig config)
    {
        this(configuredRotationMillis(config), configuredBucketCount(config), clock);
    }

    private this(long rotateMillis, int bucketCount, Clock clock)
    {
        this(configuredClock(clock, rotateMillis), rotateMillis, bucketCount);
    }

    private static Clock configuredClock(Clock clock, long rotateMillis)
    {
        if (rotateMillis > 0 && clock is null)
            throw missingSetting("clock");
        return clock;
    }

    /// Preallocate the number of buckets in the maximum's expiration window.
    this(Clock clock, long rotateFrequencyMillis, int bufferLength)
    {
        if (rotateFrequencyMillis <= 0)
            throw new IllegalArgumentException("Rotate frequency must be a positive number");
        wallClock = clock;
        this.rotateFrequencyMillis = rotateFrequencyMillis;
        lastRotateMillis = clock.wallTime();
        buckets = new shared(long)[bufferLength];
        rotationGate = new Mutex;
    }

    private static long configuredRotationMillis(const DistributionStatisticConfig config)
    {
        if (config is null)
            throw missingSetting("config");
        const expiry = config.getExpiry();
        if (expiry.isNull())
            throw missingSetting("expiry");
        return expiryMillis(expiry.get());
    }

    // Share the startup conversion between configured maxima and simple summaries.
    pragma(inline, false) package(flint.micrometer.core.instrument) static long expiryMillis(Duration expiry)
    {
        return expiry.toMillis();
    }

    private static int configuredBucketCount(const DistributionStatisticConfig config)
    {
        const count = config.getBufferLength();
        if (count.isNull())
            throw missingSetting("bufferLength");
        return count.get();
    }

    /// Record an unscaled observation.
    void record(double sample) nothrow @nogc
    {
        Sample encoded = void;
        encoded.value = sample;
        // Match Java's canonical NaN bits before comparing encoded samples.
        recordBits(sample != sample ? 0x7ff8_0000_0000_0000L : encoded.bits);
    }

    /// Record a duration, converting the input to a count of nanoseconds.
    void record(double sample, TimeUnit unit) nothrow @nogc
    {
        const nanos = sample * unit.toNanos(1);
        if (nanos != nanos || nanos <= 0)
            recordBits(0);
        else
            recordBits(nanos >= long.max ? long.max : cast(long) nanos);
    }

    /// Read the maximum unscaled observation in the current window.
    double poll() nothrow @nogc
    {
        Sample encoded = void;
        encoded.bits = pollBits();
        return encoded.value;
    }

    /// Read the current maximum duration in the given unit.
    double poll(TimeUnit unit) nothrow @nogc
    {
        return cast(double) pollBits() / unit.toNanos(1);
    }

    private void recordBits(long bits) nothrow @nogc
    {
        rotate();
        foreach (ref bucket; buckets)
        {
            auto previous = atomicLoad(bucket);
            while (bits > previous && !cas(&bucket, previous, bits))
                previous = atomicLoad(bucket);
        }
    }

    private long pollBits() nothrow @nogc
    {
        rotate();
        rotationGate.lock_nothrow();
        scope (exit)
            rotationGate.unlock_nothrow();
        return atomicLoad(buckets[currentBucket]);
    }

    private void rotate() nothrow @nogc
    {
        const now = wallClock.wallTime();
        if (now - atomicLoad(lastRotateMillis) < rotateFrequencyMillis || !cas(&rotating, false, true))
            return;
        scope (exit)
            atomicStore(rotating, false);
        rotationGate.lock_nothrow();
        scope (exit)
            rotationGate.unlock_nothrow();

        // A different recorder may have rotated between the timestamp check and our claim.
        const elapsed = now - atomicLoad(lastRotateMillis);
        const expired = elapsed / rotateFrequencyMillis;
        if (expired <= 0)
            return;
        if (cast(ulong) expired >= buckets.length)
        {
            foreach (ref bucket; buckets)
                atomicStore(bucket, 0L);
            currentBucket = 0;
        }
        else
        {
            foreach (_; 0 .. expired)
            {
                atomicStore(buckets[currentBucket], 0L);
                if (++currentBucket == buckets.length)
                    currentBucket = 0;
            }
        }
        atomicStore(lastRotateMillis, now - elapsed % rotateFrequencyMillis);
    }
}

private NullPointerException missingSetting(string name)
{
    return new NullPointerException(name);
}
