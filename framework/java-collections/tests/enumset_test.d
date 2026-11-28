// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module enumset_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException, IllegalStateException, valueOf;
import flint.java.util : Collection, HashSet;
import flint.java.util.enumset : EnumSet;
import std.exception : assertThrown;

@safe:

private enum Color
{
    red,
    green,
    blue,
    cyan,
    magenta,
    yellow
}

// A type whose declaration order differs from its member values: ordinals are declaration order, as in Java.
private enum Jump
{
    first = 5,
    second = 9,
    third = 12
}

// More than 64 constants, so the jumbo representation is instantiated.
private enum Wide
{
    w00,
    w01,
    w02,
    w03,
    w04,
    w05,
    w06,
    w07,
    w08,
    w09,
    w10,
    w11,
    w12,
    w13,
    w14,
    w15,
    w16,
    w17,
    w18,
    w19,
    w20,
    w21,
    w22,
    w23,
    w24,
    w25,
    w26,
    w27,
    w28,
    w29,
    w30,
    w31,
    w32,
    w33,
    w34,
    w35,
    w36,
    w37,
    w38,
    w39,
    w40,
    w41,
    w42,
    w43,
    w44,
    w45,
    w46,
    w47,
    w48,
    w49,
    w50,
    w51,
    w52,
    w53,
    w54,
    w55,
    w56,
    w57,
    w58,
    w59,
    w60,
    w61,
    w62,
    w63,
    w64,
    w65,
    w66,
    w67,
    w68,
    w69
}

@("noneOf is empty and add/remove/contains follow Java's contract")
unittest
{
    auto set = EnumSet!Color.noneOf();
    assert(set.isEmpty && set.size() == 0);
    assert(!set.contains(Color.green));
    assert(!set.remove(Color.green));
    assert(set.add(Color.green));
    assert(!set.add(Color.green));
    assert(set.contains(Color.green));
    assert(set.size() == 1);
    assert(set.toString() == "[green]");
    assert(set.remove(Color.green));
    assert(set.isEmpty);
}

@("of has Java's one-to-five and varargs factories, in declaration order")
unittest
{
    assert(EnumSet!Color.of(Color.red).toArray() == [Color.red]);
    assert(EnumSet!Color.of(Color.blue, Color.red).toArray() == [Color.red, Color.blue]);
    assert(EnumSet!Color.of(Color.blue, Color.red, Color.green).toArray() == [
        Color.red, Color.green, Color.blue
    ]);
    assert(EnumSet!Color.of(Color.yellow, Color.blue, Color.red, Color.green).toArray() == [
        Color.red, Color.green, Color.blue, Color.yellow
    ]);
    assert(EnumSet!Color.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.red).toArray() == [
        Color.red, Color.blue, Color.cyan, Color.magenta, Color.yellow
    ]);
    assert(EnumSet!Color.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.green, Color.red).toArray() == [
        Color.red, Color.green, Color.blue, Color.cyan, Color.magenta, Color.yellow
    ]);
    assert(EnumSet!Color.of(Color.yellow, Color.yellow).toArray() == [Color.yellow]);
}

@("range, allOf and complementOf cover the whole universe")
unittest
{
    assert(EnumSet!Color.range(Color.green, Color.magenta).toArray() == [
        Color.green, Color.blue, Color.cyan, Color.magenta
    ]);
    assert(EnumSet!Color.range(Color.cyan, Color.cyan).toArray() == [Color.cyan]);
    assertThrown!IllegalArgumentException(EnumSet!Color.range(Color.magenta, Color.green));
    assert(EnumSet!Color.allOf().toArray() == [
        Color.red, Color.green, Color.blue, Color.cyan, Color.magenta, Color.yellow
    ]);
    assert(EnumSet!Color.complementOf(EnumSet!Color.of(Color.red, Color.yellow))
            .toArray() == [Color.green, Color.blue, Color.cyan, Color.magenta]);
    assert(EnumSet!Color.complementOf(EnumSet!Color.allOf()).isEmpty);
    assert(EnumSet!Color.complementOf(EnumSet!Color.noneOf()).toArray() == EnumSet!Color.allOf().toArray());
}

@("ordinals follow declaration order even when member values differ")
unittest
{
    auto set = EnumSet!Jump.of(Jump.third, Jump.first);
    assert(set.toArray() == [Jump.first, Jump.third]);
    assert(EnumSet!Jump.range(Jump.first, Jump.second).toArray() == [Jump.first, Jump.second]);
    assert(EnumSet!Jump.allOf().toArray() == [Jump.first, Jump.second, Jump.third]);
    assert(EnumSet!Jump.complementOf(EnumSet!Jump.of(Jump.second)).toArray() == [
        Jump.first, Jump.third
    ]);
}

@("copyOf clones an enum set and builds one from another collection")
unittest
{
    auto original = EnumSet!Color.range(Color.red, Color.blue);
    auto copy = EnumSet!Color.copyOf(original);
    assert(copy.equals(original));
    copy.add(Color.yellow);
    assert(original.toArray() == [Color.red, Color.green, Color.blue]);
    assert(copy.toArray() == [Color.red, Color.green, Color.blue, Color.yellow]);

    auto empty = new HashSet!Color();
    assertThrown!IllegalArgumentException(EnumSet!Color.copyOf(empty));

    auto source = new HashSet!Color();
    source.add(Color.yellow);
    source.add(Color.green);
    auto built = EnumSet!Color.copyOf(source);
    assert(built.toArray() == [Color.green, Color.yellow]);
    assert(EnumSet!Color.copyOf(EnumSet!Color.noneOf()).isEmpty);
}

@("bulk operations take the enum-set word path and the generic path")
unittest
{
    auto wide = EnumSet!Color.allOf();
    auto narrow = EnumSet!Color.of(Color.green, Color.cyan);
    assert(wide.containsAll(narrow));
    assert(!narrow.containsAll(wide));
    assert(narrow.containsAll(EnumSet!Color.noneOf()));

    auto added = EnumSet!Color.noneOf();
    assert(added.addAll(narrow));
    assert(!added.addAll(narrow));
    assert(added.toArray() == [Color.green, Color.cyan]);
    assert(added.removeAll(EnumSet!Color.of(Color.cyan)));
    assert(added.toArray() == [Color.green]);

    auto retained = EnumSet!Color.allOf();
    assert(retained.retainAll(narrow));
    assert(retained.toArray() == [Color.green, Color.cyan]);

    auto generic = new HashSet!Color();
    generic.add(Color.red);
    generic.add(Color.blue);
    auto throughGeneric = EnumSet!Color.noneOf();
    assert(throughGeneric.addAll(generic));
    assert(throughGeneric.toArray() == [Color.red, Color.blue]);
    assert(throughGeneric.containsAll(generic));
    assert(throughGeneric.removeAll(generic));
    assert(throughGeneric.isEmpty);
    assert(!throughGeneric.retainAll(generic));
}

@("equals and hashCode match another set with the same elements")
unittest
{
    auto left = EnumSet!Color.range(Color.green, Color.cyan);
    auto right = EnumSet!Color.of(Color.cyan, Color.blue, Color.green);
    assert(left.equals(right));
    assert(left == right);
    assert(left.hashCode() == right.hashCode());
    assert(left != EnumSet!Color.allOf());

    auto asHashSet = new HashSet!Color();
    foreach (color; left.toArray())
        asHashSet.add(color);
    assert(left.equals(asHashSet));
    assert(asHashSet.equals(left));
}

@("the iterator is weakly consistent and supports remove")
unittest
{
    auto set = EnumSet!Color.allOf();
    auto cursor = set.iterator();
    assertThrown!IllegalStateException(cursor.remove());
    assert(cursor.next() == Color.red);
    cursor.remove();
    assertThrown!IllegalStateException(cursor.remove());
    assert(set.toArray() == [Color.green, Color.blue, Color.cyan, Color.magenta, Color.yellow]);
    assert(cursor.next() == Color.green);
    assert(cursor.next() == Color.blue);
}

@("removeIf and clear work through the collection contract")
unittest
{
    auto set = EnumSet!Color.allOf();
    assert(set.removeIf((Color color) => color == Color.blue || color == Color.magenta));
    assert(set.toArray() == [Color.red, Color.green, Color.cyan, Color.yellow]);
    assert(!set.removeIf((Color) => false));
    set.clear();
    assert(set.isEmpty && set.toArray().length == 0);
}

@("a jumbo set handles a universe larger than 64 constants")
unittest
{
    auto set = EnumSet!Wide.noneOf();
    assert(set.isEmpty && set.size() == 0);
    assert(set.add(Wide.w65) && set.add(Wide.w00) && set.add(Wide.w64));
    assert(!set.add(Wide.w65));
    assert(set.contains(Wide.w64) && !set.contains(Wide.w63));
    assert(set.toArray() == [Wide.w00, Wide.w64, Wide.w65]);
    assert(set.remove(Wide.w64));
    assert(!set.contains(Wide.w64) && set.size() == 2);

    auto whole = EnumSet!Wide.allOf();
    assert(whole.size() == 70);
    assert(whole.containsAll(set));
    auto window = EnumSet!Wide.range(Wide.w60, Wide.w69);
    assert(window.toArray() == [
        Wide.w60, Wide.w61, Wide.w62, Wide.w63, Wide.w64, Wide.w65, Wide.w66, Wide.w67, Wide.w68,
        Wide.w69
    ]);
    auto outside = EnumSet!Wide.complementOf(window);
    assert(outside.size() == 60);
    assert(outside.contains(Wide.w59) && !outside.contains(Wide.w60));

    auto cursor = whole.iterator();
    assert(cursor.next() == Wide.w00);
    cursor.remove();
    assert(!whole.contains(Wide.w00) && whole.size() == 69);

    auto kept = EnumSet!Wide.copyOf(whole);
    assert(kept.retainAll(EnumSet!Wide.range(Wide.w05, Wide.w15)));
    assert(kept.size() == 11);
    assert(kept.toArray()[0] == Wide.w05 && kept.toArray()[$ - 1] == Wide.w15);
    kept.add(Wide.w00);
    assert(!whole.contains(Wide.w00));
}

@("the jumbo representation crosses word boundaries in addRange and complement")
unittest
{
    auto crossed = EnumSet!Wide.range(Wide.w62, Wide.w66);
    assert(crossed.toArray() == [Wide.w62, Wide.w63, Wide.w64, Wide.w65, Wide.w66]);
    assert(EnumSet!Wide.range(Wide.w00, Wide.w63).size() == 64);
    assert(EnumSet!Wide.range(Wide.w00, Wide.w69).equals(EnumSet!Wide.allOf()));
    auto complemented = EnumSet!Wide.complementOf(crossed);
    assert(complemented.size() == 65);
    assert(complemented.contains(Wide.w61) && complemented.contains(Wide.w67));
    assert(!complemented.contains(Wide.w62) && !complemented.contains(Wide.w66));
}

@("point operations allocate nothing in either representation")
unittest
{
    auto small = EnumSet!Color.range(Color.red, Color.blue);
    auto jumbo = EnumSet!Wide.range(Wide.w00, Wide.w10);
    foreach (step; 0 .. 16)
    {
        assert(small.contains(Color.green));
        assert(small.size() == 3);
        assert(!jumbo.isEmpty);
        assert(jumbo.contains(Wide.w05));
        jumbo.add(Wide.w30);
        jumbo.remove(Wide.w30);
    }
    const before = GC.stats().allocatedInCurrentThread;
    foreach (step; 0 .. 64)
    {
        assert(small.contains(Color.green));
        assert(small.size() == 3);
        assert(!small.isEmpty);
        assert(jumbo.contains(Wide.w05));
        jumbo.add(Wide.w30);
        assert(jumbo.remove(Wide.w30));
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

// A null element is not representable: Java throws NullPointerException, D rejects the call (R5, R20).
static assert(!__traits(compiles, EnumSet!Color.of(null)));
static assert(!__traits(compiles, EnumSet!Color.noneOf().add(null)));
static assert(!__traits(compiles, EnumSet!Color.noneOf().contains(null)));

private int fold(int digest, int value) pure nothrow @nogc
{
    return 31 * digest + value;
}

private int foldText(int digest, string text) pure nothrow @nogc
{
    foreach (unit; text)
        digest = 31 * digest + unit;
    return digest;
}

private void foldAll(E)(ref int digest, EnumSet!E set)
{
    auto items = set.toArray();
    digest = fold(digest, cast(int) items.length);
    foreach (item; items)
        digest = foldText(digest, valueOf(item));
}

private int oracleSmallFactories()
{
    int digest = 0x51a11;
    auto set = EnumSet!Color.noneOf();
    digest = fold(digest, set.size());
    digest = fold(digest, set.isEmpty ? 1 : 0);
    digest = fold(digest, set.add(Color.green) ? 1 : 0);
    digest = fold(digest, set.add(Color.green) ? 1 : 0);
    digest = fold(digest, set.contains(Color.green) ? 1 : 0);
    digest = fold(digest, set.contains(Color.red) ? 1 : 0);
    digest = fold(digest, set.remove(Color.red) ? 1 : 0);
    digest = fold(digest, set.remove(Color.green) ? 1 : 0);
    foldAll(digest, set);
    foldAll(digest, EnumSet!Color.of(Color.red));
    foldAll(digest, EnumSet!Color.of(Color.blue, Color.red));
    foldAll(digest, EnumSet!Color.of(Color.blue, Color.red, Color.green));
    foldAll(digest, EnumSet!Color.of(Color.yellow, Color.blue, Color.red, Color.green));
    foldAll(digest, EnumSet!Color.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.red));
    foldAll(digest, EnumSet!Color.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.green, Color.red));
    foldAll(digest, EnumSet!Color.range(Color.green, Color.magenta));
    try
    {
        EnumSet!Color.range(Color.magenta, Color.green);
        digest = fold(digest, 0);
    }
    catch (IllegalArgumentException)
    {
        digest = fold(digest, 7);
    }
    foldAll(digest, EnumSet!Color.allOf());
    foldAll(digest, EnumSet!Color.complementOf(EnumSet!Color.of(Color.red, Color.yellow)));
    auto original = EnumSet!Color.range(Color.red, Color.blue);
    auto copy = EnumSet!Color.copyOf(original);
    copy.add(Color.yellow);
    foldAll(digest, original);
    foldAll(digest, copy);
    return digest;
}

private int oracleSmallBulk()
{
    int digest = 0x6b1a1;
    auto all = EnumSet!Color.allOf();
    auto narrow = EnumSet!Color.of(Color.green, Color.cyan);
    digest = fold(digest, all.containsAll(narrow) ? 1 : 0);
    digest = fold(digest, narrow.containsAll(all) ? 1 : 0);
    digest = fold(digest, narrow.containsAll(EnumSet!Color.noneOf()) ? 1 : 0);
    auto added = EnumSet!Color.noneOf();
    digest = fold(digest, added.addAll(narrow) ? 1 : 0);
    digest = fold(digest, added.addAll(narrow) ? 1 : 0);
    foldAll(digest, added);
    digest = fold(digest, added.removeAll(EnumSet!Color.of(Color.cyan)) ? 1 : 0);
    foldAll(digest, added);
    auto retained = EnumSet!Color.allOf();
    digest = fold(digest, retained.retainAll(narrow) ? 1 : 0);
    foldAll(digest, retained);
    auto generic = new HashSet!Color();
    generic.add(Color.red);
    generic.add(Color.blue);
    auto throughGeneric = EnumSet!Color.noneOf();
    digest = fold(digest, throughGeneric.addAll(generic) ? 1 : 0);
    foldAll(digest, throughGeneric);
    digest = fold(digest, throughGeneric.containsAll(generic) ? 1 : 0);
    digest = fold(digest, throughGeneric.removeAll(generic) ? 1 : 0);
    digest = fold(digest, throughGeneric.isEmpty ? 1 : 0);
    auto left = EnumSet!Color.range(Color.green, Color.cyan);
    auto right = EnumSet!Color.of(Color.cyan, Color.blue, Color.green);
    digest = fold(digest, left.equals(right) ? 1 : 0);
    digest = fold(digest, left.hashCode() == right.hashCode() ? 1 : 0);
    auto asHashSet = new HashSet!Color();
    foreach (color; left.toArray())
        asHashSet.add(color);
    digest = fold(digest, left.equals(asHashSet) ? 1 : 0);
    digest = fold(digest, asHashSet.equals(left) ? 1 : 0);
    return digest;
}

private int oracleSmallIteratorClone()
{
    int digest = 0x1c10e;
    auto cursorSet = EnumSet!Color.allOf();
    auto cursor = cursorSet.iterator();
    digest = fold(digest, cursor.hasNext() ? 1 : 0);
    digest = foldText(digest, valueOf(cursor.next()));
    cursor.remove();
    try
    {
        cursor.remove();
        digest = fold(digest, 0);
    }
    catch (IllegalStateException)
    {
        digest = fold(digest, 9);
    }
    foldAll(digest, cursorSet);
    auto removable = EnumSet!Color.allOf();
    digest = fold(digest, removable.removeIf((Color color) => color == Color.blue || color == Color.magenta) ? 1 : 0);
    foldAll(digest, removable);
    auto source = EnumSet!Color.range(Color.red, Color.cyan);
    auto cloned = source.clone();
    cloned.add(Color.yellow);
    foldAll(digest, source);
    foldAll(digest, cloned);
    return digest;
}

private int oracleJumbo()
{
    int digest = 0x70001;
    auto wide = EnumSet!Wide.noneOf();
    digest = fold(digest, wide.size());
    digest = fold(digest, wide.add(Wide.w65) ? 1 : 0);
    digest = fold(digest, wide.add(Wide.w00) ? 1 : 0);
    digest = fold(digest, wide.add(Wide.w64) ? 1 : 0);
    digest = fold(digest, wide.add(Wide.w65) ? 1 : 0);
    digest = fold(digest, wide.contains(Wide.w64) ? 1 : 0);
    digest = fold(digest, wide.contains(Wide.w63) ? 1 : 0);
    foldAll(digest, wide);
    digest = fold(digest, wide.remove(Wide.w64) ? 1 : 0);
    digest = fold(digest, wide.size());
    auto whole = EnumSet!Wide.allOf();
    digest = fold(digest, whole.size());
    foldAll(digest, EnumSet!Wide.range(Wide.w60, Wide.w69));
    auto outside = EnumSet!Wide.complementOf(EnumSet!Wide.range(Wide.w60, Wide.w69));
    digest = fold(digest, outside.size());
    digest = fold(digest, outside.contains(Wide.w59) ? 1 : 0);
    digest = fold(digest, outside.contains(Wide.w60) ? 1 : 0);
    auto wideCursor = whole.iterator();
    digest = foldText(digest, valueOf(wideCursor.next()));
    wideCursor.remove();
    digest = fold(digest, whole.size());
    auto kept = EnumSet!Wide.copyOf(whole);
    digest = fold(digest, kept.retainAll(EnumSet!Wide.range(Wide.w05, Wide.w15)) ? 1 : 0);
    digest = fold(digest, kept.size());
    auto keptItems = kept.toArray();
    digest = foldText(digest, valueOf(keptItems[0]));
    digest = foldText(digest, valueOf(keptItems[$ - 1]));
    return digest;
}

@("matches the Temurin 21.0.13+9 EnumSet factory and range transcript")
unittest
{
    assert(cast(uint) oracleSmallFactories() == 771_932_321u);
}

@("matches the Temurin 21.0.13+9 EnumSet bulk transcript")
unittest
{
    assert(cast(uint) oracleSmallBulk() == 1_246_634_589u);
}

@("matches the Temurin 21.0.13+9 EnumSet iterator and clone transcript")
unittest
{
    assert(cast(uint) oracleSmallIteratorClone() == 1_576_919_768u);
}

@("matches the Temurin 21.0.13+9 EnumSet jumbo transcript")
unittest
{
    assert(cast(uint) oracleJumbo() == 4_080_130_070u);
}
