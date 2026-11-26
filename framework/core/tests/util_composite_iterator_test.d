/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from spring-framework v7.1.0, spring-core/src/test/java/org/springframework/util/CompositeIteratorTests.java
// Modified by the Flint authors.

module util_composite_iterator_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException,
    UnsupportedOperationException;
import flint.java.util : Arrays, NoSuchElementException;
import flint.util : CompositeIterator;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("noIterators")
unittest
{
    auto iterator = new CompositeIterator!string;
    assert(!iterator.hasNext());
    assertThrown!NoSuchElementException(iterator.next());
}

@("singleIterator")
unittest
{
    auto iterator = new CompositeIterator!string;
    iterator.add(Arrays.asList!string("0", "1").iterator());
    foreach (expected; ["0", "1"])
    {
        assert(iterator.hasNext());
        assert(iterator.next() == expected);
    }
    assert(!iterator.hasNext());
    assertThrown!NoSuchElementException(iterator.next());
}

@("multipleIterators")
unittest
{
    auto iterator = new CompositeIterator!string;
    iterator.add(Arrays.asList!string("0", "1").iterator());
    iterator.add(Arrays.asList!string("2").iterator());
    iterator.add(Arrays.asList!string("3", "4").iterator());
    foreach (expected; ["0", "1", "2", "3", "4"])
    {
        assert(iterator.hasNext());
        assert(iterator.next() == expected);
    }
    assert(!iterator.hasNext());
    assertThrown!NoSuchElementException(iterator.next());
}

@("inUse")
unittest
{
    auto list = Arrays.asList!string("0", "1");
    auto throughHasNext = new CompositeIterator!string;
    throughHasNext.add(list.iterator());
    assert(throughHasNext.hasNext());
    assertThrown!IllegalStateException(throughHasNext.add(list.iterator()));

    auto throughNext = new CompositeIterator!string;
    throughNext.add(list.iterator());
    assert(throughNext.next() == "0");
    assertThrown!IllegalStateException(throughNext.add(list.iterator()));
}

@("duplicateIterators")
unittest
{
    auto list = Arrays.asList!string("0", "1");
    auto first = list.iterator();
    auto iterator = new CompositeIterator!string;
    iterator.add(first);
    iterator.add(list.iterator());
    assertThrown!IllegalArgumentException(iterator.add(first));
}

@("nullable")
unittest
{
    alias Text = Nullable!string;
    auto iterator = new CompositeIterator!Text;
    iterator.add(Arrays.asList(Text("1"), Text.init).iterator());
    iterator.add(Arrays.asList(Text("2"), Text.init).iterator());
    assert(iterator.next().get() == "1");
    assert(iterator.next().isNull);
    assert(iterator.next().get() == "2");
    assert(iterator.next().isNull);
    assert(!iterator.hasNext());
}

@("remove is unsupported and null iterators fail when reached")
unittest
{
    auto iterator = new CompositeIterator!string;
    iterator.add(Arrays.asList!string("0").iterator());
    iterator.add(null);
    assertThrown!IllegalArgumentException(iterator.add(null));
    assert(iterator.next() == "0");
    assertThrown!UnsupportedOperationException(iterator.remove());
    assertThrown!NullPointerException(iterator.hasNext());
}
