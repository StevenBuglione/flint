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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/MeterIdTest.java
// Modified by the Flint authors.
module micrometer_meter_id_test;

import flint.micrometer.core.instrument : Meter, Statistic, Tags;
import std.typecons : Nullable;

@safe:

@("withStatistic")
unittest
{
    auto id = new Meter.Id("my.id", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    auto statistic = id.withTag(Statistic.TOTAL_TIME);
    assert(statistic.getTag("statistic").get() == "total");
    assert(id.getTag("statistic").isNull);
}

@("equalsAndHashCode")
unittest
{
    auto id = new Meter.Id("my.id", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.COUNTER);
    auto other = new Meter.Id("my.id", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.COUNTER);
    assert(id.equals(other));
    assert(id.hashCode() == other.hashCode());
}

@("withTags")
unittest
{
    auto id = new Meter.Id("my.id", Tags.of("k1", "v1", "k2", "v2"), Nullable!string.init,
            Nullable!string.init, Meter.Type.COUNTER);
    auto transformed = id.withTags(Tags.of("k1", "n1", "k", "n"));
    assert(Tags.of(transformed.getTags()).equals(Tags.of("k2", "v2", "k1", "n1", "k", "n")));
    assert(id.getTag("k1").get() == "v1");
}

@("replaceTags")
unittest
{
    auto id = new Meter.Id("my.id", Tags.of("k1", "v1", "k2", "v2"), Nullable!string.init,
            Nullable!string.init, Meter.Type.COUNTER);
    auto transformed = id.replaceTags(Tags.of("k1", "n1", "k", "n"));
    assert(Tags.of(transformed.getTags()).equals(Tags.of("k1", "n1", "k", "n")));
    assert(transformed.getTag("k2").isNull);
}

@("meter identity ignores descriptive metadata and meter type")
unittest
{
    auto id = new Meter.Id("my.id", Tags.of("a", "first", "b", "second"),
            Nullable!string("bytes"), Nullable!string("old description"), Meter.Type.COUNTER);
    auto other = new Meter.Id("my.id", Tags.of("b", "second", "a", "first"),
            Nullable!string("seconds"), Nullable!string("new description"), Meter.Type.TIMER);
    assert(id.hashCode() == other.hashCode());
    assert(id.equals(other));
    assert(!id.equals(id.withName("another.id")));
    assert(!id.equals(id.withTags(Tags.of("a", "changed"))));
}

@("meter metadata distinguishes null from empty strings")
unittest
{
    auto id = new Meter.Id("my.id", Tags.of("", "empty key", "key", ""), Nullable!string.init,
            Nullable!string(""), Meter.Type.GAUGE);
    assert(id.getBaseUnit().isNull);
    assert(!id.getDescription().isNull);
    assert(id.getDescription().get() == "");
    assert(id.getTag("").get() == "empty key");
    assert(id.getTag(null).isNull);
    assert(id.getTag("key").get() == "");
    assert(id.getTag("absent").isNull);
}

@("meter id lists expose sorted tags and reject mutation")
unittest
{
    import flint.java.lang : UnsupportedOperationException;
    import flint.micrometer.core.instrument : Tag;
    import std.exception : assertThrown;

    auto id = new Meter.Id("my.id", Tags.of("z", "last", "a", "first"), Nullable!string.init,
            Nullable!string.init, Meter.Type.COUNTER);
    auto tags = id.getTags();
    assert(tags.get(0).getKey() == "a");
    assertThrown!UnsupportedOperationException(tags.add(Tag.of("tag", "value")));
}

@("meter id tag lookup allocates no bytes after registration")
unittest
{
    import core.memory : GC;

    auto id = new Meter.Id("my.id", Tags.of("a", "first", "b", "second"), Nullable!string.init,
            Nullable!string.init, Meter.Type.COUNTER);
    const before = GC.stats().allocatedInCurrentThread;
    const present = id.getTag("b");
    const missing = id.getTag("c");
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(present.get() == "second");
    assert(missing.isNull);
}
