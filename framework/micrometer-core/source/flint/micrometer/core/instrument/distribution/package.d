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
// Modified by the Flint authors.
module flint.micrometer.core.instrument.distribution;

import core.atomic : atomicLoad, atomicStore, cas;
import core.sync.mutex : Mutex;
import flint.java.lang : IllegalArgumentException;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.micrometer.core.instrument : Clock;

@safe:

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

private union Sample
{
    double value;
    long bits;
}
