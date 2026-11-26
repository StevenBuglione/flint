/*
 * Copyright 2019 VMware, Inc.
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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopTimerTest.java
// Modified by the Flint authors.
module micrometer_timer_runnable_test;

import flint.java.lang : NullPointerException, Runnable;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;

@safe:

@("recordRunnable")
unittest
{
    static final class Action : Runnable
    {
        int runs;

        override void run()
        {
            ++runs;
        }
    }

    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    auto action = new Action;
    timer.record(action);
    assert(action.runs == 1 && timer.count() == 0);
    assertThrown!NullPointerException(timer.record(cast(Runnable) null));
    assertThrown!NullPointerException(timer.record(cast(void delegate() @safe) null));
}
