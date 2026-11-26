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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/distribution/TimeWindowMaxTest.java
// Modified by the Flint authors.
module micrometer_time_window_max_test;

import core.memory : GC;
import core.thread : Thread;
import flint.java.lang : IllegalArgumentException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : MockClock;
import flint.micrometer.core.instrument.distribution : TimeWindowMax;
import std.exception : assertThrown;

@safe:

@("decaysToZero")
unittest
{
    auto clock = new MockClock;
    enum bufferLength = 3;
    enum rotateFrequencyMillis = 60_000;
    auto maximum = new TimeWindowMax(clock, rotateFrequencyMillis, bufferLength);
    maximum.record(100);

    foreach (_; 0 .. bufferLength)
    {
        assert(maximum.poll() == 100);
        clock.add(rotateFrequencyMillis, TimeUnit.MILLISECONDS);
    }

    assert(maximum.poll() == 0);
}

@("testLongPeriodOfInactivity")
unittest
{
    auto clock = new MockClock;
    auto maximum = new TimeWindowMax(clock, 60_000, 3);
    maximum.record(32);
    assert(maximum.poll() == 32);

    clock.add(Duration.ofHours(12));
    assert(maximum.poll() == 0);

    maximum.record(666);
    assert(maximum.poll() == 666);

    clock.add(Duration.ofSeconds(62));
    maximum.record(500);
    assert(maximum.poll() == 666);

    clock.add(Duration.ofSeconds(62));
    maximum.record(100_500);
    assert(maximum.poll() == 100_500);
}

@("throwsExceptionWhenRotateFrequency0")
unittest
{
    auto clock = new MockClock;
    assertThrown!IllegalArgumentException(new TimeWindowMax(clock, 0, 3));
}

@("the time window records scaled samples without allocating, including on rotation")
unittest
{
    auto clock = new MockClock;
    auto maximum = new TimeWindowMax(clock, 60_000, 3);
    const before = GC.stats().allocatedInCurrentThread;
    maximum.record(1.25, TimeUnit.SECONDS);
    maximum.record(750, TimeUnit.MILLISECONDS);
    assert(maximum.poll(TimeUnit.MILLISECONDS) == 1250);
    clock.addSeconds(120);
    assert(maximum.poll(TimeUnit.SECONDS) == 1.25);
    maximum.record(2.5, TimeUnit.SECONDS);
    clock.addSeconds(60);
    assert(maximum.poll(TimeUnit.SECONDS) == 2.5);
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("concurrent recorders retain the largest sample without allocating")
@system unittest
{
    auto maximum = new TimeWindowMax(new MockClock, 60_000, 3);
    Thread[4] recorders;
    foreach (index, ref recorder; recorders)
    {
        recorder = recordingThread(maximum, cast(double)(index + 1));
        recorder.start();
    }
    foreach (recorder; recorders)
        recorder.join();
    assert(maximum.poll() == 4);
}

private Thread recordingThread(TimeWindowMax maximum, double sample)
{
    return new Thread(() {
        const before = GC.stats().allocatedInCurrentThread;
        foreach (_; 0 .. 1_000)
            maximum.record(sample);
        assert(GC.stats().allocatedInCurrentThread == before);
    });
}
