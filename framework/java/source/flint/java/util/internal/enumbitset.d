/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

/++
An unmodifiable `Set!E` of enum members over one `ulong`, as Java's `Collections.unmodifiableSet(EnumSet.of(...))`
over a `RegularEnumSet`: iteration follows declaration order, and every mutator throws
`UnsupportedOperationException`. The seed of a later `java.util.EnumSet` port. Internal: applications receive it only
as a `Set!E`.
+/
module flint.java.util.internal.enumbitset;

import flint.java.lang : UnsupportedOperationException, javaHashCode;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, Set;

@safe:

/// An unmodifiable set of members of `E`, which may have at most 64 members.
final class EnumBitSet(E) : AbstractCollection!E, Set!E if (is(E == enum))
{
    private static immutable E[] members = memberValues();
    static assert(members.length <= 64, E.stringof ~ " has more than 64 members");

    private ulong mask;

    private this(ulong mask) pure nothrow @nogc
    {
        this.mask = mask;
    }

    /// The set of `elements`; a repeated member counts once, as in `EnumSet.of`.
    static EnumBitSet!E of(scope E[] elements...)
    {
        ulong bits;
        foreach (e; elements)
            bits |= bit(e);
        return new EnumBitSet!E(bits);
    }

    private static E[] memberValues()
    {
        E[] result;
        static foreach (name; __traits(allMembers, E))
            result ~= __traits(getMember, E, name);
        return result;
    }

    // The member's bit, or 0 for a value that is not a declared member.
    private static ulong bit(E e) pure nothrow @nogc
    {
        foreach (i, member; members)
            if (member == e)
                return 1UL << i;
        return 0;
    }

    override int size()
    {
        import core.bitop : popcnt;

        return popcnt(mask);
    }

    override bool isEmpty()
    {
        return mask == 0;
    }

    override bool contains(E o)
    {
        return (mask & bit(o)) != 0;
    }

    override bool containsAll(Collection!E c)
    {
        if (auto that = cast(EnumBitSet!E) c)
            return (that.mask & ~mask) == 0;
        return super.containsAll(c);
    }

    override Iterator!E iterator()
    {
        return new BitIterator(mask);
    }

    override int opApply(scope int delegate(E) @safe dg)
    {
        for (ulong rest = mask; rest != 0; rest &= rest - 1)
            if (const result = dg(members[lowest(rest)]))
                return result;
        return 0;
    }

    override void forEach(void delegate(E) @safe action)
    {
        for (ulong rest = mask; rest != 0; rest &= rest - 1)
            action(members[lowest(rest)]);
    }

    override E[] toArray()
    {
        E[] result;
        result.reserve(size());
        for (ulong rest = mask; rest != 0; rest &= rest - 1)
            result ~= members[lowest(rest)];
        return result;
    }

    override bool add(E)
    {
        throw new UnsupportedOperationException();
    }

    override bool remove(E)
    {
        throw new UnsupportedOperationException();
    }

    override bool addAll(Collection!E)
    {
        throw new UnsupportedOperationException();
    }

    override bool removeAll(Collection!E)
    {
        throw new UnsupportedOperationException();
    }

    override bool retainAll(Collection!E)
    {
        throw new UnsupportedOperationException();
    }

    override bool removeIf(bool delegate(E) @safe)
    {
        throw new UnsupportedOperationException();
    }

    override void clear()
    {
        throw new UnsupportedOperationException();
    }

    override bool isSet()
    {
        return true;
    }

    /// Java's `Set.equals`: another set with the same elements.
    bool equals(Object o)
    {
        if (o is this)
            return true;
        if (auto that = cast(EnumBitSet!E) o)
            return that.mask == mask;
        auto that = cast(Set!E) o;
        return that !is null && that.size() == size() && containsAll(that);
    }

    /// Java's `Set.hashCode`: the sum of the elements' hash codes.
    int hashCode()
    {
        int h;
        for (ulong rest = mask; rest != 0; rest &= rest - 1)
            h += javaHashCode(members[lowest(rest)]);
        return h;
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

    private static size_t lowest(ulong rest) pure nothrow @nogc
    {
        import core.bitop : bsf;

        return bsf(rest);
    }

    private static final class BitIterator : Iterator!E
    {
        private ulong rest;

        this(ulong rest) pure nothrow @nogc
        {
            this.rest = rest;
        }

        bool hasNext()
        {
            return rest != 0;
        }

        E next()
        {
            if (rest == 0)
                throw new NoSuchElementException();
            const index = lowest(rest);
            rest &= rest - 1;
            return members[index];
        }

        void remove()
        {
            throw new UnsupportedOperationException();
        }
    }
}
