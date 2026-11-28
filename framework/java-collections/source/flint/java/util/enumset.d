/*
 * Copyright (c) 2003, 2022, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Ported from openjdk 21.0.13, src/java.base/share/classes/java/util/EnumSet.java,
// src/java.base/share/classes/java/util/RegularEnumSet.java and
// src/java.base/share/classes/java/util/JumboEnumSet.java.
// Modified by the Flint authors.
module flint.java.util.enumset;

import core.bitop : bsf, popcnt;
import flint.java.lang : ClassCastException, IllegalArgumentException, IllegalStateException,
    NullPointerException, javaHashCode, valueOf;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, Set;

@safe:

/++
Java's `EnumSet`, a specialized set for one enum type, stored as a bit vector over the type's constants in
declaration order.

Java names the element type with a `Class<E>` token; D makes it the template parameter (R4), so a set of one enum
type cannot hold a constant of another. `EnumSet!E.noneOf()` is Java's `EnumSet.noneOf(E.class)`. Java's
`AbstractSet` superclass is not yet available, so this class derives from `AbstractCollection` and `Set` and is
reparented when sol-jdk-core lands `AbstractSet`; `equals`, `hashCode` and `isSet` supply what `AbstractSet`
would. Java's serialization proxy has no D equivalent and is not ported. A null element is a compile error, as
the 2026-11-26 no throw-only typed-null rule requires (R5, R20).
+/
abstract class EnumSet(E) : AbstractCollection!E, Set!E if (is(E == enum))
{
    /// How many constants the element type declares.
    enum size_t universeSize = __traits(allMembers, E).length;

    /// The element type's constants, indexed by ordinal.
    static immutable E[universeSize] universe = buildUniverse();

    private static E[universeSize] buildUniverse() pure nothrow @nogc
    {
        E[universeSize] result;
        static foreach (ordinal, member; __traits(allMembers, E))
            result[ordinal] = __traits(getMember, E, member);
        return result;
    }

    /// The declaration-order position of `value`, or -1 when it is not one of `E`'s constants.
    private static ptrdiff_t ordinalOf(E value) pure nothrow @nogc
    {
        switch (value)
        {
            static foreach (ordinal, member; __traits(allMembers, E))
            {
        case __traits(getMember, E, member):
                return ordinal;
            }
        default:
            return -1;
        }
    }

    private this() pure nothrow @nogc
    {
    }

    /// An empty set of `E`.
    static EnumSet!E noneOf()
    {
        static if (universeSize <= 64)
            return new RegularEnumSet!E();
        else
            return new JumboEnumSet!E();
    }

    /// A set of every constant of `E`.
    static EnumSet!E allOf()
    {
        auto result = noneOf();
        result.fillAll();
        return result;
    }

    /// A copy of `s` with the same concrete representation.
    static EnumSet!E copyOf(EnumSet!E s)
    {
        if (s is null)
            throw new NullPointerException();
        return s.clone();
    }

    /// An enum set initialized from `c`; an empty `c` cannot name its element type.
    static EnumSet!E copyOf(Collection!E c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto es = cast(EnumSet!E) c)
            return es.clone();
        if (c.isEmpty())
            throw new IllegalArgumentException("Collection is empty");
        auto cursor = c.iterator();
        auto result = of(cursor.next());
        while (cursor.hasNext())
            result.add(cursor.next());
        return result;
    }

    /// The complement of `s` in `E`.
    static EnumSet!E complementOf(EnumSet!E s)
    {
        auto result = copyOf(s);
        result.complementWords();
        return result;
    }

    /// A set of one constant.
    static EnumSet!E of(E e1)
    {
        auto result = noneOf();
        result.add(e1);
        return result;
    }

    /// A set of two constants.
    static EnumSet!E of(E e1, E e2)
    {
        auto result = noneOf();
        result.add(e1);
        result.add(e2);
        return result;
    }

    /// A set of three constants.
    static EnumSet!E of(E e1, E e2, E e3)
    {
        auto result = noneOf();
        result.add(e1);
        result.add(e2);
        result.add(e3);
        return result;
    }

    /// A set of four constants.
    static EnumSet!E of(E e1, E e2, E e3, E e4)
    {
        auto result = noneOf();
        result.add(e1);
        result.add(e2);
        result.add(e3);
        result.add(e4);
        return result;
    }

    /// A set of five constants.
    static EnumSet!E of(E e1, E e2, E e3, E e4, E e5)
    {
        auto result = noneOf();
        result.add(e1);
        result.add(e2);
        result.add(e3);
        result.add(e4);
        result.add(e5);
        return result;
    }

    /// A set of `first` and every constant of `rest`.
    static EnumSet!E of(E first, scope E[] rest...)
    {
        auto result = noneOf();
        result.add(first);
        foreach (value; rest)
            result.add(value);
        return result;
    }

    /// Every constant from `from` to `to` inclusive; `from` must not follow `to`.
    static EnumSet!E range(E from, E to)
    {
        const first = ordinalOf(from), last = ordinalOf(to);
        if (first > last)
            throw new IllegalArgumentException(valueOf(from) ~ " > " ~ valueOf(to));
        auto result = noneOf();
        result.fillRange(cast(size_t) first, cast(size_t) last);
        return result;
    }

    /// A copy of this set, independent of it.
    abstract EnumSet!E clone();

    /// Fill the set, which is empty, with every constant.
    protected abstract void fillAll() pure nothrow @nogc;

    /// Fill the set, which is empty, with ordinals `from` through `to` inclusive.
    protected abstract void fillRange(size_t from, size_t to) pure nothrow @nogc;

    /// Complement the set in its universe.
    protected abstract void complementWords() pure nothrow @nogc;

    /// How many machine words hold the bit vector.
    protected abstract size_t wordCount() const pure nothrow @nogc;

    /// The word at `index`.
    protected abstract ulong wordAt(size_t index) const pure nothrow @nogc;

    /// Replace the word at `index`, keeping the reported size.
    protected abstract void setWord(size_t index, ulong value) pure nothrow @nogc;

    /// Whether every element of `other` is present.
    private bool subsetOf(EnumSet!E other) pure nothrow @nogc
    {
        foreach (index; 0 .. wordCount())
            if ((other.wordAt(index) & ~wordAt(index)) != 0)
                return false;
        return true;
    }

    /// Whether the two sets hold the same bits.
    private bool sameWords(EnumSet!E other) pure nothrow @nogc
    {
        foreach (index; 0 .. wordCount())
            if (other.wordAt(index) != wordAt(index))
                return false;
        return true;
    }

    /// Union `other` into this set; whether it changed.
    private bool unionWith(EnumSet!E other) pure nothrow @nogc
    {
        bool changed;
        foreach (index; 0 .. wordCount())
        {
            const combined = wordAt(index) | other.wordAt(index);
            if (combined != wordAt(index))
            {
                setWord(index, combined);
                changed = true;
            }
        }
        return changed;
    }

    /// Remove every element of `other`; whether this set changed.
    private bool subtractWith(EnumSet!E other) pure nothrow @nogc
    {
        bool changed;
        foreach (index; 0 .. wordCount())
        {
            const kept = wordAt(index) & ~other.wordAt(index);
            if (kept != wordAt(index))
            {
                setWord(index, kept);
                changed = true;
            }
        }
        return changed;
    }

    /// Keep only the elements of `other`; whether this set changed.
    private bool intersectWith(EnumSet!E other) pure nothrow @nogc
    {
        bool changed;
        foreach (index; 0 .. wordCount())
        {
            const kept = wordAt(index) & other.wordAt(index);
            if (kept != wordAt(index))
            {
                setWord(index, kept);
                changed = true;
            }
        }
        return changed;
    }

    /// Java's `AbstractSet.containsAll`, with the enum-set word path when `c` is one.
    override bool containsAll(Collection!E c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto es = cast(EnumSet!E) c)
            return subsetOf(es);
        return super.containsAll(c);
    }

    /// Java's `AbstractCollection.addAll`, with the enum-set word path when `c` is one.
    override bool addAll(Collection!E c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto es = cast(EnumSet!E) c)
            return unionWith(es);
        return super.addAll(c);
    }

    /// Java's `AbstractSet.removeAll`, with the enum-set word path when `c` is one.
    override bool removeAll(Collection!E c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto es = cast(EnumSet!E) c)
            return subtractWith(es);
        return super.removeAll(c);
    }

    /// Java's `AbstractCollection.retainAll`, with the enum-set word path when `c` is one.
    override bool retainAll(Collection!E c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto es = cast(EnumSet!E) c)
            return intersectWith(es);
        return super.retainAll(c);
    }

    /// A set is a set for descriptor-driven engines.
    override bool isSet() pure nothrow @nogc
    {
        return true;
    }

    /// Java's `Set.equals`: another set with the same elements.
    bool equals(Object o)
    {
        if (o is this)
            return true;
        if (auto es = cast(EnumSet!E) o)
            return sameWords(es);
        auto that = cast(Set!E) o;
        return that !is null && that.size() == size() && containsAll(that);
    }

    /// Java's `Set.hashCode`: the sum of the elements' hash codes.
    int hashCode()
    {
        int hash;
        for (auto cursor = iterator(); cursor.hasNext();)
            hash += javaHashCode(cursor.next());
        return hash;
    }

    override bool opEquals(Object o)
    {
        return equals(o);
    }

    override size_t toHash() @safe nothrow
    {
        try
            return cast(uint) hashCode();
        catch (Exception)
            return 0;
    }
}

/// The <= 64-constant representation: one machine word, one bit per ordinal.
private final class RegularEnumSet(E) : EnumSet!E if (is(E == enum))
{
    private ulong elements;

    private this() pure nothrow @nogc
    {
    }

    private static ulong universeMask() pure nothrow @nogc
    {
        return EnumSet!E.universeSize == 64 ? ulong.max : (1UL << EnumSet!E.universeSize) - 1;
    }

    protected override void fillAll() pure nothrow @nogc
    {
        elements = universeMask();
    }

    protected override void fillRange(size_t from, size_t to) pure nothrow @nogc
    {
        elements = (ulong.max << from) & (ulong.max >>> (63 - to));
    }

    protected override void complementWords() pure nothrow @nogc
    {
        elements = ~elements & universeMask();
    }

    protected override size_t wordCount() const pure nothrow @nogc
    {
        return 1;
    }

    protected override ulong wordAt(size_t index) const pure nothrow @nogc
    {
        return elements;
    }

    protected override void setWord(size_t index, ulong value) pure nothrow @nogc
    {
        elements = value;
    }

    override int size() pure nothrow @nogc
    {
        return popcnt(elements);
    }

    override bool isEmpty() pure nothrow @nogc
    {
        return elements == 0;
    }

    override bool contains(E o) pure nothrow @nogc
    {
        const ordinal = EnumSet!E.ordinalOf(o);
        return ordinal >= 0 && (elements & (1UL << ordinal)) != 0;
    }

    override bool add(E e)
    {
        const ordinal = EnumSet!E.ordinalOf(e);
        if (ordinal < 0)
            throw new ClassCastException();
        const previous = elements;
        elements |= 1UL << ordinal;
        return previous != elements;
    }

    override bool remove(E o) pure nothrow @nogc
    {
        const ordinal = EnumSet!E.ordinalOf(o);
        if (ordinal < 0)
            return false;
        const previous = elements;
        elements &= ~(1UL << ordinal);
        return previous != elements;
    }

    override void clear() pure nothrow @nogc
    {
        elements = 0;
    }

    override Iterator!E iterator()
    {
        return new Cursor(this);
    }

    override EnumSet!E clone()
    {
        auto result = new RegularEnumSet!E();
        result.elements = elements;
        return result;
    }

    private static final class Cursor : Iterator!E
    {
        private RegularEnumSet!E set;
        private ulong unseen;
        private ulong lastReturned;

        private this(RegularEnumSet!E set) pure nothrow @nogc
        {
            this.set = set;
            unseen = set.elements;
        }

        bool hasNext() pure nothrow @nogc
        {
            return unseen != 0;
        }

        E next()
        {
            if (unseen == 0)
                throw new NoSuchElementException();
            lastReturned = unseen & -unseen;
            unseen -= lastReturned;
            return EnumSet!E.universe[bsf(lastReturned)];
        }

        void remove()
        {
            if (lastReturned == 0)
                throw new IllegalStateException();
            set.elements &= ~lastReturned;
            lastReturned = 0;
        }
    }
}

/// The > 64-constant representation: one machine word per 64 ordinals.
private final class JumboEnumSet(E) : EnumSet!E if (is(E == enum))
{
    private ulong[] elements;
    private int count;

    private this()
    {
        elements = new ulong[wordCountStatic()];
    }

    private static size_t wordCountStatic() pure nothrow @nogc
    {
        return (EnumSet!E.universeSize + 63) / 64;
    }

    private static size_t lastWordBits() pure nothrow @nogc
    {
        const remainder = EnumSet!E.universeSize % 64;
        return remainder == 0 ? 64 : remainder;
    }

    protected override void fillAll() pure nothrow @nogc
    {
        foreach (ref word; elements)
            word = ulong.max;
        const remainder = EnumSet!E.universeSize % 64;
        if (remainder != 0)
            elements[$ - 1] = (1UL << remainder) - 1;
        count = cast(int) EnumSet!E.universeSize;
    }

    protected override void fillRange(size_t from, size_t to) pure nothrow @nogc
    {
        const firstWord = from / 64, lastWord = to / 64;
        if (firstWord == lastWord)
            elements[firstWord] |= (ulong.max << (from % 64)) & (ulong.max >>> (63 - (to % 64)));
        else
        {
            elements[firstWord] |= ulong.max << (from % 64);
            foreach (index; firstWord + 1 .. lastWord)
                elements[index] = ulong.max;
            elements[lastWord] |= ulong.max >>> (63 - (to % 64));
        }
        count = cast(int)(to - from + 1);
    }

    protected override void complementWords() pure nothrow @nogc
    {
        foreach (ref word; elements)
            word = ~word;
        const remainder = EnumSet!E.universeSize % 64;
        if (remainder != 0)
            elements[$ - 1] &= (1UL << remainder) - 1;
        count = cast(int) EnumSet!E.universeSize - count;
    }

    protected override size_t wordCount() const pure nothrow @nogc
    {
        return elements.length;
    }

    protected override ulong wordAt(size_t index) const pure nothrow @nogc
    {
        return elements[index];
    }

    protected override void setWord(size_t index, ulong value) pure nothrow @nogc
    {
        count += popcnt(value) - popcnt(elements[index]);
        elements[index] = value;
    }

    override int size() pure nothrow @nogc
    {
        return count;
    }

    override bool isEmpty() pure nothrow @nogc
    {
        return count == 0;
    }

    override bool contains(E o) pure nothrow @nogc
    {
        const ordinal = EnumSet!E.ordinalOf(o);
        return ordinal >= 0 && (elements[ordinal / 64] & (1UL << (ordinal % 64))) != 0;
    }

    override bool add(E e)
    {
        const ordinal = EnumSet!E.ordinalOf(e);
        if (ordinal < 0)
            throw new ClassCastException();
        auto ref word = elements[ordinal / 64];
        const previous = word;
        word |= 1UL << (ordinal % 64);
        if (word == previous)
            return false;
        ++count;
        return true;
    }

    override bool remove(E o) pure nothrow @nogc
    {
        const ordinal = EnumSet!E.ordinalOf(o);
        if (ordinal < 0)
            return false;
        auto ref word = elements[ordinal / 64];
        const previous = word;
        word &= ~(1UL << (ordinal % 64));
        if (word == previous)
            return false;
        --count;
        return true;
    }

    override void clear() pure nothrow @nogc
    {
        elements[] = 0;
        count = 0;
    }

    override Iterator!E iterator()
    {
        return new Cursor(this);
    }

    override EnumSet!E clone()
    {
        auto result = new JumboEnumSet!E();
        result.elements[] = elements[];
        result.count = count;
        return result;
    }

    private static final class Cursor : Iterator!E
    {
        private JumboEnumSet!E set;
        private size_t currentWord;
        private ulong unseen;
        private ulong lastReturned;
        private size_t lastReturnedWord;

        private this(JumboEnumSet!E set) pure nothrow @nogc
        {
            this.set = set;
            unseen = set.elements[0];
        }

        bool hasNext() pure nothrow @nogc
        {
            while (unseen == 0 && currentWord + 1 < set.elements.length)
                unseen = set.elements[++currentWord];
            return unseen != 0;
        }

        E next()
        {
            if (!hasNext())
                throw new NoSuchElementException();
            lastReturned = unseen & -unseen;
            lastReturnedWord = currentWord;
            unseen -= lastReturned;
            return EnumSet!E.universe[currentWord * 64 + bsf(lastReturned)];
        }

        void remove()
        {
            if (lastReturned == 0)
                throw new IllegalStateException();
            const previous = set.elements[lastReturnedWord];
            set.elements[lastReturnedWord] &= ~lastReturned;
            if (previous != set.elements[lastReturnedWord])
                --set.count;
            lastReturned = 0;
        }
    }
}
