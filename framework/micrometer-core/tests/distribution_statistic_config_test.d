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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/distribution/DistributionStatisticConfigTest.java
// Modified by the Flint authors.
module micrometer_distribution_statistic_config_test;

import core.memory : GC;
import flint.java.lang : ArithmeticException, IllegalArgumentException, IllegalStateException, NullPointerException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : MockClock;
import flint.micrometer.core.instrument.config : InvalidConfigurationException;
import flint.micrometer.core.instrument.distribution : DistributionStatisticConfig, TimeWindowMax;
import flint.micrometer.core.instrument.internal : Mergeable;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private alias Config = DistributionStatisticConfig;
private alias Doubles = Nullable!(double[]);

private void rejects(scope Config delegate() @safe build, string reason)
{
    try
        build();
    catch (InvalidConfigurationException error)
    {
        assert(error.getMessage() == "Invalid distribution configuration: " ~ reason);
        return;
    }
    assert(0, "expected InvalidConfigurationException");
}

@("merge")
unittest
{
    auto first = Config.builder().percentiles(0.95).build();
    auto second = Config.builder().percentiles(0.90).build();
    Mergeable!Config withPercentiles = second.merge(first);
    auto merged = withPercentiles.merge(Config.DEFAULT);
    assert(merged.getPercentiles().get() == [0.90]);
    assert(merged.getExpiry().get() == Duration.ofMinutes(2));
    assert(merged.getBufferLength().get() == 3);
    const(Mergeable!Config) defaults = Config.DEFAULT;
    assert(defaults.merge(Config.NONE).getExpiry().get() == Duration.ofMinutes(2));
}

@("bufferLengthValidation")
unittest
{
    rejects(() => Config.builder().bufferLength(0).build(), "bufferLength (0) must be greater than zero");
    rejects(() => Config.builder().bufferLength(-1).build(), "bufferLength (-1) must be greater than zero");
}

@("merge reads a parent only for unset settings")
unittest
{
    auto complete = Config.builder().percentilesHistogram(false).percentiles().percentilePrecision(1)
        .serviceLevelObjectives().minimumExpectedValue(1.0).maximumExpectedValue(2.0)
        .expiry(Duration.ofMillis(1)).bufferLength(2).build();
    auto merged = complete.merge(cast(Config) null);
    assert(merged !is complete && merged.getBufferLength().get() == 2);
    assertThrown!NullPointerException(new Config().merge(cast(Config) null));
}

@("serviceLevelObjectiveBoundariesValidation")
unittest
{
    enum reason = "serviceLevelObjectiveBoundaries must contain only the values greater than 0. Found ";
    rejects(() => Config.builder().serviceLevelObjectives(0.0).build(), reason ~ "0.0");
    rejects(() => Config.builder().serviceLevelObjectives(-1.0).build(), reason ~ "-1.0");
    rejects(() => Config.builder().serviceLevelObjectives(-1.0, 2.0, 10.0).build(), reason ~ "-1.0");
}

@("percentilesValidation")
unittest
{
    enum reason = "percentiles must contain only the values between 0.0 and 1.0. Found ";
    rejects(() => Config.builder().percentiles(-0.01).build(), reason ~ "-0.01");
    rejects(() => Config.builder().percentiles(1.01).build(), reason ~ "1.01");
}

@("expectedValueRangeValidation")
unittest
{
    rejects(() => Config.builder().minimumExpectedValue(0.0).build(),
            "minimumExpectedValue (0.0) must be greater than 0.");
    rejects(() => Config.builder().maximumExpectedValue(0.0).build(),
            "maximumExpectedValue (0.0) must be greater than 0.");
    rejects(() => Config.builder().minimumExpectedValue(10.0).maximumExpectedValue(9.0).build(),
            "maximumExpectedValue (9.0) must be equal to or greater than minimumExpectedValue (10.0).");
}

@("explicit empty and false override inherited values")
unittest
{
    assert(Config.DEFAULT is Config.DEFAULT);
    assert(Config.NONE is Config.NONE && Config.NONE !is Config.DEFAULT);
    assert(Config.NONE.getPercentiles().isNull() && Config.NONE.isPercentileHistogram().isNull());
    auto parent = Config.builder().percentilesHistogram(true).percentiles(0.9).serviceLevelObjectives(4.0).build();
    auto child = Config.builder().percentilesHistogram(false).percentiles().serviceLevelObjectives().build();
    auto merged = child.merge(parent);
    assert(!merged.isPercentileHistogram().get());
    assert(!merged.getPercentiles().isNull() && merged.getPercentiles().get().length == 0);
    assert(!merged.getServiceLevelObjectiveBoundaries().isNull()
            && merged.getServiceLevelObjectiveBoundaries().get().length == 0);
    assert(!merged.isPublishingHistogram() && !merged.isPublishingPercentiles());

    auto provided = [0.75];
    auto builder = Config.builder().percentiles(Doubles(provided)).bufferLength(2);
    auto config = builder.build();
    assert(builder.bufferLength(3).build() is config);
    assert(config.getBufferLength().get() == 3);
    auto inherited = new Config;
    inherited = inherited.merge(config).merge(Config.DEFAULT);
    provided[0] = 0.8;
    assert(inherited.getPercentiles().get()[0] == 0.8);
    assert(inherited.getPercentilePrecision().get() == 1);

    auto direct = Config.Builder();
    auto copied = direct;
    assert(direct.bufferLength(4).build() is copied.build());
}

@("legacy nullable overloads and causes")
unittest
{
    auto builder = Config.builder().minimumExpectedValue(2.0).maximumExpectedValue(8.0);
    builder.minimumExpectedValue(Nullable!long.init).maximumExpectedValue(Nullable!long.init);
    auto config = builder.build();
    assert(config.getMinimumExpectedValueAsDouble().get() == 2.0);
    assert(config.getMaximumExpectedValueAsDouble().get() == 8.0);
    builder.minimumExpectedValue(Nullable!double.init).maximumExpectedValue(Nullable!double.init);
    assert(config.getMinimumExpectedValueAsDouble().isNull());
    assert(config.getMaximumExpectedValueAsDouble().isNull());

    builder.serviceLevelObjectives(2.0).sla(Nullable!(long[]).init);
    assert(config.getServiceLevelObjectiveBoundaries().get() == [2.0]);
    builder.sla(Doubles.init);
    assert(config.getServiceLevelObjectiveBoundaries().isNull());
    builder.sla(3L, 5L);
    assert(config.getSlaBoundaries().get() == [3.0, 5.0]);
    builder.sla([6L, 7L]);
    assert(config.getSlaBoundaries().get() == [6.0, 7.0]);

    auto cause = new IllegalStateException("bad upstream value");
    auto error = new InvalidConfigurationException("bad configuration", cause);
    assert(error.getMessage() == "bad configuration" && error.getCause() is cause);
}

@("variadic settings outlive caller storage")
unittest
{
    static Config fromTemporaryArray()
    {
        double[2] values = [0.5, 0.95];
        auto builder = Config.Builder();
        auto built = builder.percentiles(values[]).build();
        values[0] = 0.0;
        return built;
    }

    assert(fromTemporaryArray().getPercentiles().get() == [0.5, 0.95]);
}

@("configured maximum uses expiry and buffer length without recording allocations")
unittest
{
    auto clock = new MockClock;
    auto config = Config.builder().expiry(Duration.ofMillis(2)).bufferLength(2).build();
    auto maximum = new TimeWindowMax(clock, config);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    maximum.record(3.0);
    clock.add(3, TimeUnit.MILLISECONDS);
    assert(maximum.poll() == 3.0);
    clock.add(1, TimeUnit.MILLISECONDS);
    assert(maximum.poll() == 0.0);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);

    assertThrown!NullPointerException(new TimeWindowMax(clock, Config.NONE));
    assertThrown!NullPointerException(new TimeWindowMax(null, Config.DEFAULT));
    assertThrown!IllegalArgumentException(new TimeWindowMax(clock, Config.builder()
            .expiry(Duration.ofNanos(1)).bufferLength(2).build()));
    assertThrown!ArithmeticException(new TimeWindowMax(clock, Config.builder()
            .expiry(Duration.ofSeconds(long.max)).bufferLength(2).build()));
    assertThrown!ArithmeticException(new TimeWindowMax(clock, Config.builder()
            .expiry(Duration.ofSeconds(long.min)).bufferLength(2).build()));
    assertThrown!IllegalArgumentException(new TimeWindowMax(clock, Config.builder()
            .expiry(Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_001)).bufferLength(2).build()));
    assertThrown!ArithmeticException(new TimeWindowMax(clock, Config.builder()
            .expiry(Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_000)).bufferLength(2).build()));
}
