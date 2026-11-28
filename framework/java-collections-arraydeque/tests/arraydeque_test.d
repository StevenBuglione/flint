// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module arraydeque_test;

import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.util : ArrayList, Collection, Iterator, NoSuchElementException;
import flint.java.util.arraydeque : ArrayDeque;
import flint.java.util.deque : Deque;
import std.exception : assertThrown;

@safe:

private Collection!int collection(int[] values)
{
    auto list = new ArrayList!int();
    foreach (value; values)
        list.add(value);
    return list;
}

@("an empty deque reports Java's empty results")
unittest
{
    auto deque = new ArrayDeque!int();
    assert(deque.size() == 0);
    assert(deque.isEmpty());
    assert(deque.peek() == 0 && deque.peekFirst() == 0 && deque.peekLast() == 0);
    assert(deque.poll() == 0 && deque.pollFirst() == 0 && deque.pollLast() == 0);
    assert(!deque.contains(0));
    assert(!deque.removeFirstOccurrence(0));
    assert(!deque.removeLastOccurrence(0));
    assert(deque.toArray().length == 0);
    assert(deque.toString() == "[]");
    assert(!deque.isSet());
    assertThrown!NoSuchElementException(deque.remove());
    assertThrown!NoSuchElementException(deque.removeFirst());
    assertThrown!NoSuchElementException(deque.removeLast());
    assertThrown!NoSuchElementException(deque.getFirst());
    assertThrown!NoSuchElementException(deque.getLast());
    assertThrown!NoSuchElementException(deque.element());
    assertThrown!NoSuchElementException(deque.pop());
}

@("queue, stack and both ends keep Java's orders")
unittest
{
    auto deque = new ArrayDeque!int();
    assert(deque.add(1) && deque.add(2) && deque.add(3));
    assert(deque.offer(4) && deque.offerLast(5));
    assert(deque.offerFirst(0));
    assert(deque.toArray() == [0, 1, 2, 3, 4, 5]);
    assert(deque.getFirst() == 0 && deque.getLast() == 5);
    assert(deque.remove() == 0);
    assert(deque.poll() == 1);
    assert(deque.element() == 2 && deque.peek() == 2);

    deque.push(9);
    assert(deque.toArray() == [9, 2, 3, 4, 5]);
    assert(deque.pop() == 9);
    deque.addFirst(7);
    deque.addLast(8);
    assert(deque.toArray() == [7, 2, 3, 4, 5, 8]);
    assert(deque.removeLast() == 8);
    assert(deque.pollLast() == 5);
    assert(deque.toArray() == [7, 2, 3, 4]);
}

@("insertion wraps around the ring and grows in amortized constant time")
unittest
{
    auto deque = new ArrayDeque!int();
    foreach (value; 0 .. 16)
        deque.addLast(value);
    assert(deque.toArray() == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
    foreach (value; 0 .. 8)
        assert(deque.pollFirst() == value);
    foreach (value; 16 .. 40)
        deque.addLast(value);
    int[] expected;
    foreach (value; 8 .. 40)
        expected ~= value;
    assert(deque.toArray() == expected);
    assert(deque.getFirst() == 8 && deque.getLast() == 39);
    foreach (value; 0 .. 32)
        assert(deque.removeLast() == 39 - value);
    assert(deque.isEmpty());

    auto many = new ArrayDeque!int();
    foreach (value; 0 .. 1_000)
        many.addLast(value);
    assert(many.size() == 1_000);
    foreach (value; 0 .. 1_000)
        assert(many.pollFirst() == value);
    assert(many.isEmpty());
}

@("constructors take a capacity and a collection in iteration order")
unittest
{
    assert(new ArrayDeque!int().isEmpty());
    assert(new ArrayDeque!int(0).isEmpty());
    assert(new ArrayDeque!int(-3).isEmpty());
    auto sized = new ArrayDeque!int(2);
    sized.addLast(1);
    sized.addLast(2);
    sized.addLast(3);
    assert(sized.toArray() == [1, 2, 3]);

    auto deque = new ArrayDeque!int(collection([4, 5, 6]));
    assert(deque.toArray() == [4, 5, 6]);
    foreach (value; [4, 5, 6])
        assert(deque.removeFirst() == value);

    Collection!int none = null;
    assertThrown!NullPointerException(new ArrayDeque!int(none));
}

@("reference element types reject null elements")
unittest
{
    auto deque = new ArrayDeque!string();
    string none = null;
    assertThrown!NullPointerException(deque.addFirst(none));
    assertThrown!NullPointerException(deque.addLast(none));
    assertThrown!NullPointerException(deque.add(none));
    assertThrown!NullPointerException(deque.offer(none));
    assertThrown!NullPointerException(deque.offerFirst(none));
    assertThrown!NullPointerException(deque.offerLast(none));
    assertThrown!NullPointerException(deque.push(none));
    assert(deque.isEmpty());
    deque.add("x");
    assert(deque.peek() == "x");
    assert(!deque.removeFirstOccurrence(none));
    assert(!deque.contains(none));
    assert(deque.size() == 1);
}

@("iterators traverse both directions and support removal")
unittest
{
    auto deque = new ArrayDeque!int();
    foreach (value; 1 .. 6)
        deque.addLast(value);
    int[] seen;
    for (Iterator!int cursor = deque.iterator(); cursor.hasNext();)
        seen ~= cursor.next();
    assert(seen == [1, 2, 3, 4, 5]);
    seen = null;
    for (Iterator!int cursor = deque.descendingIterator(); cursor.hasNext();)
        seen ~= cursor.next();
    assert(seen == [5, 4, 3, 2, 1]);

    auto cursor = deque.iterator();
    assertThrown!IllegalStateException(cursor.remove());
    assert(cursor.next() == 1);
    assert(cursor.next() == 2);
    cursor.remove();
    assertThrown!IllegalStateException(cursor.remove());
    assert(deque.toArray() == [1, 3, 4, 5]);
    assert(cursor.next() == 3);
    assert(cursor.next() == 4);
    cursor.remove();
    assert(deque.toArray() == [1, 3, 5]);

    auto backwards = deque.descendingIterator();
    assert(backwards.next() == 5);
    backwards.remove();
    assert(deque.toArray() == [1, 3]);
    assert(backwards.next() == 3);
    backwards.remove();
    assert(deque.toArray() == [1]);
}

@("bulk operations follow the collection contract")
unittest
{
    auto deque = new ArrayDeque!int();
    assert(deque.addAll(collection([1, 2, 3, 2])));
    assert(!deque.addAll(collection([])));
    assert(deque.contains(2) && deque.containsAll(collection([1, 2])));
    assert(deque.removeFirstOccurrence(2));
    assert(deque.toArray() == [1, 3, 2]);
    assert(deque.removeLastOccurrence(2));
    assert(deque.toArray() == [1, 3]);
    deque.addLast(5);
    assert(deque.removeFirstOccurrence(5));
    assert(deque.remove(3));
    assert(!deque.remove(3));
    assert(deque.toArray() == [1]);
    deque.addAll(collection([2, 3, 4]));
    assert(deque.removeAll(collection([2, 4])));
    assert(deque.toArray() == [1, 3]);
    assert(deque.retainAll(collection([3, 9])));
    assert(deque.toArray() == [3]);
    assert(deque.removeIf((int value) => value == 3));
    assert(deque.isEmpty());
    deque.addAll(collection([1, 2, 3]));
    deque.clear();
    assert(deque.isEmpty() && deque.toArray().length == 0);

    Collection!int none = null;
    assertThrown!NullPointerException(deque.addAll(none));
    assertThrown!NullPointerException(deque.removeAll(none));
    assertThrown!NullPointerException(deque.retainAll(none));
    assertThrown!NullPointerException(deque.removeIf(null));
}

@("clone copies the contents and iterates independently")
unittest
{
    auto deque = new ArrayDeque!int(collection([1, 2, 3, 4]));
    auto copy = deque.clone();
    assert(copy.toArray() == [1, 2, 3, 4]);
    assert(copy.toString() == deque.toString());
    assert(copy.equals(copy));
    assert(!copy.equals(deque));
    deque.addFirst(0);
    deque.removeLast();
    assert(copy.toArray() == [1, 2, 3, 4]);
    assert(deque.toArray() == [0, 1, 2, 3]);
    copy.pollFirst();
    assert(deque.toArray() == [0, 1, 2, 3]);
    assert(copy.toArray() == [2, 3, 4]);
}

@("the reversed view delegates to the other end")
unittest
{
    auto deque = new ArrayDeque!int(collection([1, 2, 3]));
    Deque!int reversed = deque.reversed();
    assert(reversed.reversed() is deque);
    assert(reversed.peekFirst() == 3 && reversed.peekLast() == 1);
    assert(reversed.pollFirst() == 3);
    assert(deque.toArray() == [1, 2]);
    reversed.addFirst(9);
    assert(deque.toArray() == [1, 2, 9]);
    assert(reversed.pop() == 9);
    assert(deque.toArray() == [1, 2]);
}

@("randomized operations agree with a reference model")
unittest
{
    auto deque = new ArrayDeque!int();
    int[] model;
    uint state = 0x1357_9bdf;
    foreach (step; 0 .. 4_000)
    {
        state = state * 1_664_525 + 1_013_904_223;
        const value = cast(int)(state % 97);
        switch ((state >> 16) % 7)
        {
        case 0:
            deque.addFirst(value);
            model = value ~ model;
            break;
        case 1:
            deque.addLast(value);
            model = model ~ value;
            break;
        case 2:
            if (model.length)
            {
                assert(deque.pollFirst() == model[0]);
                model = model[1 .. $];
            }
            break;
        case 3:
            if (model.length)
            {
                assert(deque.pollLast() == model[$ - 1]);
                model = model[0 .. $ - 1];
            }
            break;
        case 4:
            assert(deque.removeFirstOccurrence(value) == removeFirst(model, value));
            break;
        case 5:
            assert(deque.removeLastOccurrence(value) == removeLast(model, value));
            break;
        default:
            if (model.length)
            {
                assert(deque.getFirst() == model[0]);
                assert(deque.getLast() == model[$ - 1]);
            }
            break;
        }
        assert(deque.size() == cast(int) model.length);
        assert(deque.toArray() == model);
        assert(deque.isEmpty() == (model.length == 0));
    }
}

private bool removeFirst(ref int[] model, int value)
{
    foreach (index, element; model)
        if (element == value)
        {
            model = model[0 .. index] ~ model[index + 1 .. $];
            return true;
        }
    return false;
}

private bool removeLast(ref int[] model, int value)
{
    foreach_reverse (index, element; model)
        if (element == value)
        {
            model = model[0 .. index] ~ model[index + 1 .. $];
            return true;
        }
    return false;
}
