// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module priorityqueue_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException;
import flint.java.util : ArrayList, Collection, Comparator, ConcurrentModificationException,
    Iterator, NoSuchElementException;
import flint.java.util.priorityqueue : PriorityQueue;
import std.exception : assertThrown;

@safe:

private Collection!int collection(int[] values)
{
    auto list = new ArrayList!int();
    foreach (value; values)
        list.add(value);
    return list;
}

@("an empty queue reports Java's empty results")
unittest
{
    auto queue = new PriorityQueue!int();
    assert(queue.size() == 0);
    assert(queue.isEmpty());
    assert(queue.peek() == 0);
    assert(queue.poll() == 0);
    assert(!queue.contains(0));
    assert(!queue.remove(0));
    assert(queue.toArray().length == 0);
    assert(queue.comparator() is null);
    assertThrown!NoSuchElementException(queue.remove());
    assertThrown!NoSuchElementException(queue.element());
    queue.clear();
    assert(queue.isEmpty());
}

@("the head is the least element under the natural ordering")
unittest
{
    auto queue = new PriorityQueue!int();
    foreach (value; [5, 1, 9, 3, 7, 2, 8, 4, 6, 0])
        assert(queue.offer(value));
    assert(queue.peek() == 0);
    assert(queue.element() == 0);
    assert(queue.size() == 10);
    int previous = queue.remove();
    while (!queue.isEmpty())
    {
        const current = queue.remove();
        assert(current >= previous);
        previous = current;
    }
    assert(queue.poll() == 0);
}

@("strings order naturally and reject null elements")
unittest
{
    auto queue = new PriorityQueue!string();
    foreach (value; ["banana", "apple", "cherry"])
        queue.add(value);
    assert(queue.poll() == "apple");
    assert(queue.poll() == "banana");
    assert(queue.poll() == "cherry");

    assertThrown!NullPointerException(queue.offer(null));
    assertThrown!NullPointerException(queue.add(null));

    auto withNull = new ArrayList!string();
    withNull.add("a");
    withNull.add(null);
    Collection!string source = withNull;
    assertThrown!NullPointerException(new PriorityQueue!string(source));
}

@("a comparator defines the ordering")
unittest
{
    auto reverse = Comparator!int.of((int a, int b) => b - a);
    auto queue = new PriorityQueue!int(reverse);
    foreach (value; [5, 1, 9, 3, 7])
        queue.add(value);
    assert(queue.comparator() is reverse);
    assert(queue.poll() == 9);
    assert(queue.poll() == 7);
    assert(queue.poll() == 5);
    assert(queue.poll() == 3);
    assert(queue.poll() == 1);
    assert(queue.poll() == 0);

    auto firstChar = Comparator!string.of((string a, string b) => cast(int) a[0] - cast(int) b[0]);
    auto words = new PriorityQueue!string(firstChar);
    foreach (word; ["foo", "fee", "fi", "fo", "fum", "Englishman"])
        words.add(word);
    foreach (word; ["foo", "fee", "fi", "fo", "fum", "Englishman"])
        assert(words.contains(word));
    assert(!words.contains("flurble"));
    assert(words.remove("fi"));
    foreach (word; ["foo", "fee", "fi", "fo", "fum", "Englishman"])
        assert(words.contains(word) ^ (word == "fi"));
    assert(!words.remove("fi"));
    assert(!words.remove("flurble"));
}

@("constructors take a capacity, a comparator, a collection and another queue")
unittest
{
    assertThrown!IllegalArgumentException(new PriorityQueue!int(0));
    assertThrown!IllegalArgumentException(new PriorityQueue!int(-3));

    auto sized = new PriorityQueue!int(1);
    sized.add(2);
    sized.add(1);
    assert(sized.poll() == 1);
    assert(sized.poll() == 2);

    auto fromCollection = new PriorityQueue!int(collection([4, 5, 6, 1, 2]));
    foreach (value; [1, 2, 4, 5, 6])
        assert(fromCollection.poll() == value);

    Collection!int none = null;
    assertThrown!NullPointerException(new PriorityQueue!int(none));

    auto reverse = Comparator!int.of((int a, int b) => b - a);
    auto source = new PriorityQueue!int(reverse);
    foreach (value; [1, 2, 3])
        source.add(value);
    auto copy = new PriorityQueue!int(source);
    assert(copy.comparator() is reverse);
    assert(copy.poll() == 3);
    assert(copy.poll() == 2);
    assert(copy.poll() == 1);
    assert(source.size() == 3);

    Collection!int asCollection = source;
    auto throughCollection = new PriorityQueue!int(asCollection);
    assert(throughCollection.comparator() is reverse);
    assert(throughCollection.poll() == 3);
    assert(throughCollection.poll() == 2);
    assert(throughCollection.poll() == 1);
    assert(source.size() == 3);
}

@("the heap array matches Java's ForgetMeNot transcript")
unittest
{
    auto queue = new PriorityQueue!int();
    queue.addAll(collection([0, 4, 1, 6, 7, 2, 3]));
    assert(queue.toArray() == [0, 4, 1, 6, 7, 2, 3]);

    auto it = queue.iterator();
    assertThrown!IllegalStateException(it.remove());
    assert(it.next() == 0);
    assert(it.next() == 4);
    assert(it.next() == 1);
    assert(it.next() == 6);
    it.remove();
    assertThrown!IllegalStateException(it.remove());
    assert(queue.toArray() == [0, 3, 1, 4, 7, 2]);
    assert(it.hasNext());
    assert(it.next() == 7);
    it.remove();
    assert(queue.toArray() == [0, 2, 1, 4, 3]);
    assert(it.next() == 3);
    assert(it.next() == 2);
    it.remove();
    assert(queue.toArray() == [0, 3, 1, 4]);
    assert(!it.hasNext());
    assertThrown!NoSuchElementException(it.next());
    assertThrown!IllegalStateException(it.remove());
}

@("the iterator is fail-fast")
unittest
{
    auto queue = new PriorityQueue!int();
    queue.add(1);
    queue.add(2);
    auto it = queue.iterator();
    queue.add(3);
    assertThrown!ConcurrentModificationException(it.next());

    auto second = queue.iterator();
    assert(second.next() == 1);
    queue.clear();
    assertThrown!ConcurrentModificationException(second.remove());
}

@("remove takes one equal occurrence and clear resets the queue")
unittest
{
    auto queue = new PriorityQueue!int();
    foreach (value; [3, 1, 2, 1, 4])
        queue.add(value);
    assert(queue.remove(1));
    assert(queue.size() == 4);
    assert(queue.remove(1));
    assert(!queue.remove(1));
    queue.clear();
    assert(queue.isEmpty());
    assert(queue.toArray().length == 0);
    queue.add(7);
    assert(queue.poll() == 7);
}

@("a large insertion keeps the heap invariant")
unittest
{
    auto queue = new PriorityQueue!int();
    int seed = 12_345;
    foreach (i; 0 .. 2_000)
    {
        seed = (seed * 1_103_515_245 + 12_345) & 0x7fff_ffff;
        queue.offer(seed % 1_000);
    }
    int previous = -1;
    while (!queue.isEmpty())
    {
        const current = queue.poll();
        assert(current >= previous);
        previous = current;
    }
}
