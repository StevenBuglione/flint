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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/TagsTest.java
// Modified by the Flint authors.
module micrometer_tags_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : Arrays, Collections;
import flint.micrometer.core.instrument : ImmutableTag, Tag, Tags;
import std.exception : assertThrown;

@safe:

private void assertTags(Tags tags, scope const(string)[] expected...)
{
    auto iter = tags.iterator();
    for (size_t index = 0; index < expected.length; index += 2)
    {
        assert(iter.hasNext());
        auto tag = iter.next();
        assert(tag.getKey() == expected[index]);
        assert(tag.getValue() == expected[index + 1]);
    }
    assert(!iter.hasNext());
}

@("dedup")
unittest
{
    assertTags(Tags.of("k1", "v1", "k2", "v2"), "k1", "v1", "k2", "v2");
    assertTags(Tags.of("k1", "v1", "k1", "v2"), "k1", "v2");
    assertTags(Tags.of("k3", "v3", "k1", "v1", "k1", "v2"), "k1", "v2", "k3", "v3");
    assertTags(Tags.of("k2", "v2", "k1", "v1", "k2", "v3"), "k1", "v1", "k2", "v3");
}

@("tagsEquality")
unittest
{
    auto tags = Tags.of(Tag.of("k1", "v1"), Tag.of("k1", "v1"), Tag.of("k2", "v2"));
    assert(tags.equals(Tags.of("k2", "v2", "k1", "v1")));
    assert(!tags.equals(Tags.of("k1", "v1", "k2", "different")));
}

@("tagsHashCode")
unittest
{
    auto tags = Tags.of(Tag.of("k1", "v1"), Tag.of("k1", "v1"), Tag.of("k2", "v2"));
    assert(tags.hashCode() == Tags.of("k1", "v1", "k2", "v2").hashCode());
}

@("tagsToString")
unittest
{
    auto tags = Tags.of(Tag.of("k1", "v1"), Tag.of("k1", "v1"), Tag.of("k2", "v2"));
    assert(tags.toString() == "[tag(k1=v1),tag(k2=v2)]");
}

@("nullTagIterableShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(cast(Iterable!Tag) null) is Tags.empty());
}

@("nullKeyValueArrayShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(cast(string[]) null) is Tags.empty());
}

@("nullKeyValuesShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(cast(string) null) is Tags.empty());
}

@("nullTagArrayShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(cast(Tag[]) null) is Tags.empty());
}

@("nullTagShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(cast(Tag) null) is Tags.empty());
}

@("emptyTagIterableShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(Collections.emptyList!Tag()) is Tags.empty());
}

@("emptyKeyValueArrayShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(new string[0]) is Tags.empty());
}

@("emptyTagArrayShouldProduceEmptyTags")
unittest
{
    assert(Tags.of(new Tag[0]) is Tags.empty());
}

@("createsListWithSingleTag")
unittest
{
    assertTags(Tags.of("k1", "v1"), "k1", "v1");
}

@("concatOnTwoTagsWithSameKeyAreMergedIntoOneTag")
unittest
{
    assertTags(Tags.concat(Tags.of("t1", "v1"), Tags.of("t1", "v2")), "t1", "v2");
}

@("concatWhenKeyValuesAreNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(Tags.concat(source, cast(string[]) null) is source);
}

@("zipOnTwoTagsWithSameKeyAreMergedIntoOneTag")
unittest
{
    assertTags(Tags.of("t1", "v1", "t1", "v2"), "t1", "v2");
}

@("andKeyValueShouldReturnNewInstanceWithAddedTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = source.and("t2", "v2");
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2");
}

@("andKeyValuesShouldReturnNewInstanceWithAddedTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = source.and("t2", "v2", "t3", "v3");
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2", "t3", "v3");
}

@("andKeyValuesWhenKeyValuesAreOddShouldThrowException")
unittest
{
    assertThrown!IllegalArgumentException(Tags.of("t1", "v1").and("t2"));
}

@("andKeyValuesWhenKeyValuesAreEmptyShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(new string[0]) is source);
}

@("andKeyValuesWhenKeyValuesArrayIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(cast(string[]) null) is source);
}

@("andKeyValuesWhenKeyValuesAreNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(cast(string) null) is source);
}

@("andTagsShouldReturnANewInstanceWithTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = source.and(Tag.of("t2", "v2"));
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2");
}

@("andTagsWhenTagsAreEmptyShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(new Tag[0]) is source);
}

@("andTagsWhenTagsAreNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(cast(Tag[]) null) is source);
}

@("andTagsWhenTagIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(cast(Tag) null) is source);
}

@("andTagsMultipleTimesShouldWork")
unittest
{
    auto source = Tags.empty().and(Tag.of("t1", "v1"));
    auto once = source.and(Tag.of("t1", "v1"));
    assert(once.equals(source));
    assert(once.and(Tag.of("t1", "v1")).equals(source));
}

@("andIterableShouldReturnNewInstanceWithTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = source.and(Arrays.asList!Tag(Tag.of("t2", "v2")));
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2");
}

@("andIterableWhenIterableIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(source.and(cast(Iterable!Tag) null) is source);
}

@("andWhenAlreadyContainsKeyShouldReplaceValue")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = source.and("t2", "v2", "t1", "v3");
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v3", "t2", "v2");
}

@("iteratorShouldIterateTags")
unittest
{
    assertTags(Tags.of("t1", "v1"), "t1", "v1");
}

@("stream")
unittest
{
    assert(Tags.of(Tag.of("k1", "v1"), Tag.of("k1", "v1"), Tag.of("k2", "v2")).stream().count() == 2);
}

@("streamShouldStreamTags")
unittest
{
    auto items = Tags.of("t1", "v1").stream().toList();
    assert(items.size() == 1);
    assert(items.get(0).getKey() == "t1");
    assert(items.get(0).getValue() == "v1");
}

@("concatIterableShouldReturnNewInstanceWithAddedTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = Tags.concat(source, Arrays.asList!Tag(Tag.of("t2", "v2")));
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2");
}

@("concatStringsShouldReturnNewInstanceWithAddedTags")
unittest
{
    auto source = Tags.of("t1", "v1");
    auto merged = Tags.concat(source, "t2", "v2");
    assert(merged !is source);
    assertTags(source, "t1", "v1");
    assertTags(merged, "t1", "v1", "t2", "v2");
}

@("zipShouldReturnNewInstanceWithTags")
unittest
{
    assertTags(Tags.of("t1", "v1", "t2", "v2"), "t1", "v1", "t2", "v2");
}

@("ofIterableShouldReturnNewInstanceWithTags")
unittest
{
    assertTags(Tags.of(Arrays.asList!Tag(Tag.of("t1", "v1"))), "t1", "v1");
}

@("ofIterableWhenIterableIsTagsShouldReturnSameInstance")
unittest
{
    auto source = Tags.of("t1", "v1");
    assert(Tags.of(source) is source);
}

@("ofKeyValueShouldReturnNewInstance")
unittest
{
    assertTags(Tags.of("t1", "v1"), "t1", "v1");
}

@("ofKeyValuesShouldReturnNewInstance")
unittest
{
    assertTags(Tags.of("t1", "v1", "t2", "v2"), "t1", "v1", "t2", "v2");
}

@("emptyShouldNotContainTags")
unittest
{
    assert(!Tags.empty().iterator().hasNext());
}

@("andEmptyDoesNotAllocate")
unittest
{
    auto tags = Tags.of("a", "b");
    auto empty = Tags.empty();
    const before = GC.stats().allocatedInCurrentThread;
    const combined = tags.and(empty);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(combined is tags);
}

@("ofEmptyDoesNotAllocate")
unittest
{
    auto empty = Tags.empty();
    const before = GC.stats().allocatedInCurrentThread;
    const copy = Tags.of(empty);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(copy is empty);
}

@("Tags own their array and preserve the input order of duplicate keys")
unittest
{
    Tag[] input = [Tag.of("b", "before"), Tag.of("a", "one"), Tag.of("b", "after")];
    auto tags = Tags.of(input);
    assert(input[0].getValue() == "before");
    input[0] = Tag.of("a", "mutated");
    assertTags(tags, "a", "one", "b", "after");
}

@("Tags sort in Java UTF-16 key order")
unittest
{
    assertTags(Tags.of("\uE000", "bmp", "\U00010000", "supplementary"), "\U00010000",
            "supplementary", "\uE000", "bmp");
    assert(Tag.of("a", "").compareTo(Tag.of("a\U00010000z", "")) == -3);
    assert(Tag.of("\U00010000", "").compareTo(Tag.of("\U00010002", "")) == -2);
}

@("Tag distinguishes empty strings from null")
unittest
{
    assertThrown!NullPointerException(new ImmutableTag(null, ""));
    assertThrown!NullPointerException(Tag.of("", null));
    assertTags(Tags.of("", ""), "", "");
}
