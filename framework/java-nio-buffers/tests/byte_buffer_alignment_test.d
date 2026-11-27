// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for ByteBuffer.alignmentOffset and alignedSlice, pinned row by row against a Temurin 21.0.13
// oracle (AlignOracle.java), and the heap-buffer half of OpenJDK's test/jdk/java/nio/Buffer/Basic-X testAlign.
module byte_buffer_alignment_test;

import flint.java.lang : IllegalArgumentException, RuntimeException, UnsupportedOperationException;
import flint.java.nio.bytebuffer : ByteBuffer;

@safe:

private ByteBuffer[string] oracleBuffers()
{
    auto base = ByteBuffer.allocate(64);
    ByteBuffer[string] buffers;
    buffers["alloc64"] = base;
    buffers["slice3"] = base.slice(3, 40);
    buffers["slice5empty"] = base.slice(5, 0);
    buffers["wrap7"] = ByteBuffer.wrap(new byte[30], 7, 11);
    buffers["slice3ro"] = base.slice(3, 40).asReadOnlyBuffer();
    buffers["pos13dup"] = base.position(13).slice().duplicate();
    base.clear();
    return buffers;
}

// The oracle's rendering of a result or of the exception it threw (IAE and UOE abbreviate the class names).
private string outcome(scope string delegate() @safe action)
{
    try
        return action();
    catch (UnsupportedOperationException e)
        return "UOE:" ~ e.getMessage();
    catch (IllegalArgumentException e)
        return "IAE:" ~ e.getMessage();
}

private string decimal(long value) pure
{
    import std.conv : to;

    return value.to!string;
}

private string describe(ByteBuffer b)
{
    const access = b.isReadOnly() ? "/ro" : "";
    return decimal(b.position()) ~ "/" ~ decimal(b.limit()) ~ "/" ~ decimal(
            b.capacity()) ~ access ~ "@" ~ decimal(b.alignmentOffset(0, 8));
}

// AlignOracle.java's output (exception names abbreviated): buffer, call, result (and the source cursor for alignedSlice), tab-separated.
private immutable string oracle = q"ORACLE
alloc64	alignmentOffset(0,1)	0
alloc64	alignmentOffset(0,2)	0
alloc64	alignmentOffset(1,2)	1
alloc64	alignmentOffset(3,4)	3
alloc64	alignmentOffset(5,8)	5
alloc64	alignmentOffset(7,8)	7
alloc64	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
alloc64	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
alloc64	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
alloc64	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
alloc64	alignmentOffset(-1,1)	IAE:Index less than zero: -1
alloc64	alignmentOffset(-1,3)	IAE:Index less than zero: -1
alloc64	alignmentOffset(2147483647,8)	7
alloc64	alignmentOffset(2147483647,1)	0
alloc64	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
alloc64	alignmentOffset(100,8)	4
alloc64	alignedSlice(8)@0-64	0/64/64@0	src=0/64
alloc64	alignedSlice(4)@1-64	0/60/60@4	src=1/64
alloc64	alignedSlice(8)@3-63	0/48/48@0	src=3/63
alloc64	alignedSlice(8)@2-4	0/0/0@2	src=2/4
alloc64	alignedSlice(8)@6-9	0/0/0@0	src=6/9
alloc64	alignedSlice(2)@1-2	0/0/0@2	src=1/2
alloc64	alignedSlice(1)@0-0	0/0/0@0	src=0/0
alloc64	alignedSlice(16)@1-5	UOE:Unit size unsupported for non-direct buffers: 16	src=1/5
alloc64	alignedSlice(6)@1-5	IAE:Unit size not a power of two: 6	src=1/5
slice3	alignmentOffset(0,1)	0
slice3	alignmentOffset(0,2)	1
slice3	alignmentOffset(1,2)	0
slice3	alignmentOffset(3,4)	2
slice3	alignmentOffset(5,8)	0
slice3	alignmentOffset(7,8)	2
slice3	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
slice3	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
slice3	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
slice3	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
slice3	alignmentOffset(-1,1)	IAE:Index less than zero: -1
slice3	alignmentOffset(-1,3)	IAE:Index less than zero: -1
slice3	alignmentOffset(2147483647,8)	2
slice3	alignmentOffset(2147483647,1)	0
slice3	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
slice3	alignmentOffset(100,8)	7
slice3	alignedSlice(8)@0-40	0/32/32@0	src=0/40
slice3	alignedSlice(4)@1-40	0/36/36@4	src=1/40
slice3	alignedSlice(8)@3-39	0/32/32@0	src=3/39
slice3	alignedSlice(8)@2-4	0/0/0@5	src=2/4
slice3	alignedSlice(8)@6-9	0/0/0@1	src=6/9
slice3	alignedSlice(2)@1-2	0/0/0@4	src=1/2
slice3	alignedSlice(1)@0-0	0/0/0@3	src=0/0
slice3	alignedSlice(16)@1-5	UOE:Unit size unsupported for non-direct buffers: 16	src=1/5
slice3	alignedSlice(6)@1-5	IAE:Unit size not a power of two: 6	src=1/5
slice5empty	alignmentOffset(0,1)	0
slice5empty	alignmentOffset(0,2)	1
slice5empty	alignmentOffset(1,2)	0
slice5empty	alignmentOffset(3,4)	0
slice5empty	alignmentOffset(5,8)	2
slice5empty	alignmentOffset(7,8)	4
slice5empty	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
slice5empty	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
slice5empty	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
slice5empty	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
slice5empty	alignmentOffset(-1,1)	IAE:Index less than zero: -1
slice5empty	alignmentOffset(-1,3)	IAE:Index less than zero: -1
slice5empty	alignmentOffset(2147483647,8)	4
slice5empty	alignmentOffset(2147483647,1)	0
slice5empty	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
slice5empty	alignmentOffset(100,8)	1
slice5empty	alignedSlice(8)@0-0	0/0/0@5	src=0/0
slice5empty	alignedSlice(1)@0-0	0/0/0@5	src=0/0
wrap7	alignmentOffset(0,1)	0
wrap7	alignmentOffset(0,2)	0
wrap7	alignmentOffset(1,2)	1
wrap7	alignmentOffset(3,4)	3
wrap7	alignmentOffset(5,8)	5
wrap7	alignmentOffset(7,8)	7
wrap7	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
wrap7	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
wrap7	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
wrap7	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
wrap7	alignmentOffset(-1,1)	IAE:Index less than zero: -1
wrap7	alignmentOffset(-1,3)	IAE:Index less than zero: -1
wrap7	alignmentOffset(2147483647,8)	7
wrap7	alignmentOffset(2147483647,1)	0
wrap7	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
wrap7	alignmentOffset(100,8)	4
wrap7	alignedSlice(8)@0-18	0/16/16@0	src=0/18
wrap7	alignedSlice(4)@1-18	0/12/12@4	src=1/18
wrap7	alignedSlice(8)@3-17	0/8/8@0	src=3/17
wrap7	alignedSlice(8)@2-4	0/0/0@2	src=2/4
wrap7	alignedSlice(8)@6-9	0/0/0@0	src=6/9
wrap7	alignedSlice(2)@1-2	0/0/0@2	src=1/2
wrap7	alignedSlice(1)@0-0	0/0/0@0	src=0/0
wrap7	alignedSlice(16)@1-5	UOE:Unit size unsupported for non-direct buffers: 16	src=1/5
wrap7	alignedSlice(6)@1-5	IAE:Unit size not a power of two: 6	src=1/5
slice3ro	alignmentOffset(0,1)	0
slice3ro	alignmentOffset(0,2)	1
slice3ro	alignmentOffset(1,2)	0
slice3ro	alignmentOffset(3,4)	2
slice3ro	alignmentOffset(5,8)	0
slice3ro	alignmentOffset(7,8)	2
slice3ro	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
slice3ro	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
slice3ro	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
slice3ro	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
slice3ro	alignmentOffset(-1,1)	IAE:Index less than zero: -1
slice3ro	alignmentOffset(-1,3)	IAE:Index less than zero: -1
slice3ro	alignmentOffset(2147483647,8)	2
slice3ro	alignmentOffset(2147483647,1)	0
slice3ro	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
slice3ro	alignmentOffset(100,8)	7
slice3ro	alignedSlice(8)@0-40	0/32/32/ro@0	src=0/40
slice3ro	alignedSlice(4)@1-40	0/36/36/ro@4	src=1/40
slice3ro	alignedSlice(8)@3-39	0/32/32/ro@0	src=3/39
slice3ro	alignedSlice(8)@2-4	0/0/0/ro@5	src=2/4
slice3ro	alignedSlice(8)@6-9	0/0/0/ro@1	src=6/9
slice3ro	alignedSlice(2)@1-2	0/0/0/ro@4	src=1/2
slice3ro	alignedSlice(1)@0-0	0/0/0/ro@3	src=0/0
slice3ro	alignedSlice(16)@1-5	UOE:Unit size unsupported for non-direct buffers: 16	src=1/5
slice3ro	alignedSlice(6)@1-5	IAE:Unit size not a power of two: 6	src=1/5
pos13dup	alignmentOffset(0,1)	0
pos13dup	alignmentOffset(0,2)	1
pos13dup	alignmentOffset(1,2)	0
pos13dup	alignmentOffset(3,4)	0
pos13dup	alignmentOffset(5,8)	2
pos13dup	alignmentOffset(7,8)	4
pos13dup	alignmentOffset(0,0)	IAE:Unit size not a power of two: 0
pos13dup	alignmentOffset(0,3)	IAE:Unit size not a power of two: 3
pos13dup	alignmentOffset(0,16)	UOE:Unit size unsupported for non-direct buffers: 16
pos13dup	alignmentOffset(0,-4)	IAE:Unit size not a power of two: -4
pos13dup	alignmentOffset(-1,1)	IAE:Index less than zero: -1
pos13dup	alignmentOffset(-1,3)	IAE:Index less than zero: -1
pos13dup	alignmentOffset(2147483647,8)	4
pos13dup	alignmentOffset(2147483647,1)	0
pos13dup	alignmentOffset(0,-2147483648)	IAE:Unit size not a power of two: -2147483648
pos13dup	alignmentOffset(100,8)	1
pos13dup	alignedSlice(8)@0-51	0/48/48@0	src=0/51
pos13dup	alignedSlice(4)@1-51	0/48/48@0	src=1/51
pos13dup	alignedSlice(8)@3-50	0/40/40@0	src=3/50
pos13dup	alignedSlice(8)@2-4	0/0/0@0	src=2/4
pos13dup	alignedSlice(8)@6-9	0/0/0@3	src=6/9
pos13dup	alignedSlice(2)@1-2	0/0/0@6	src=1/2
pos13dup	alignedSlice(1)@0-0	0/0/0@5	src=0/0
pos13dup	alignedSlice(16)@1-5	UOE:Unit size unsupported for non-direct buffers: 16	src=1/5
pos13dup	alignedSlice(6)@1-5	IAE:Unit size not a power of two: 6	src=1/5
ORACLE";

private int number(scope const(char)[] text) pure
{
    import std.conv : to;

    return text.to!int;
}

@("alignmentOffset matches Temurin 21 for heap buffers, slices, wrapped and read-only buffers")
unittest
{
    import std.algorithm.searching : findSplit, startsWith;
    import std.string : lineSplitter, split;

    auto buffers = oracleBuffers();
    size_t checked;
    foreach (line; oracle.lineSplitter)
    {
        const row = line.split('\t');
        if (!row[1].startsWith("alignmentOffset("))
            continue;
        const args = row[1]["alignmentOffset(".length .. $ - 1].findSplit(",");
        auto b = buffers[row[0]];
        const actual = outcome(() => decimal(b.alignmentOffset(number(args[0]), number(args[2]))));
        assert(actual == row[2], line ~ " got " ~ actual);
        ++checked;
    }
    assert(checked == 96);
}

@("alignedSlice matches Temurin 21 and leaves the source cursor alone")
unittest
{
    import std.algorithm.searching : findSplit, startsWith;
    import std.string : lineSplitter, split;

    auto buffers = oracleBuffers();
    size_t checked;
    foreach (line; oracle.lineSplitter)
    {
        const row = line.split('\t');
        if (!row[1].startsWith("alignedSlice("))
            continue;
        const call = row[1]["alignedSlice(".length .. $].findSplit(")@");
        const range = call[2].findSplit("-");
        const position = number(range[0]), limit = number(range[2]);
        auto d = buffers[row[0]].duplicate().limit(limit).position(position);
        const actual = outcome(() => describe(d.alignedSlice(number(call[0]))));
        assert(actual == row[2], line ~ " got " ~ actual);
        assert("src=" ~ decimal(d.position()) ~ "/" ~ decimal(d.limit()) == row[3]);
        ++checked;
    }
    assert(checked == 47);
}

@("alignedSlice shares the source's storage")
unittest
{
    auto b = ByteBuffer.allocate(32);
    auto aligned = b.position(3).alignedSlice(8);
    aligned.put(0, cast(byte) 42);
    assert(b.get(8) == 42);
}

// Ported from OpenJDK 21.0.13 test/jdk/java/nio/Buffer/Basic-X.java.template testAlign (heap buffers only;
// direct and mapped buffers are not ported). Modified by the Flint authors.
private void testAlign(ByteBuffer b)
{
    assert(outcome(() => decimal(b.alignmentOffset(-1, 1)))[0 .. 4] == "IAE:");
    assert(outcome(() => decimal(b.alignmentOffset(0, 0)))[0 .. 4] == "IAE:");
    foreach (us; 1 .. 65)
    {
        if ((us & (us - 1)) != 0)
            assert(outcome(() => decimal(b.alignmentOffset(0, us)))[0 .. 4] == "IAE:");
        else if (us <= 8)
            b.alignmentOffset(0, us);
        else
            assert(outcome(() => decimal(b.alignmentOffset(0, us)))[0 .. 4] == "UOE:");
    }

    const longMisalignmentAtZero = ByteBuffer.allocate(0).alignmentOffset(0, 8);
    assert(longMisalignmentAtZero == 0); // a 64-bit byte array starts 16 bytes into its 8-byte-aligned object
    assert(b.alignmentOffset(0, 8) == longMisalignmentAtZero);

    foreach (us; [1, 2, 4, 8])
        foreach (i; 0 .. us * 2)
            assert(b.alignmentOffset(i, us) == (longMisalignmentAtZero + i) % us);

    const ap = 8 - longMisalignmentAtZero;
    const al = b.limit() - b.alignmentOffset(b.limit(), 8);
    auto ab = b.position(ap).limit(al).slice();
    assert(ab.limit() != 0);
    assert(ab.alignmentOffset(0, 8) == 0);

    foreach (us; [1, 2, 4, 8])
    {
        for (int p = 1; p < 16; p++)
        {
            int l = ab.limit() - p;
            auto as = ab.slice().position(p).limit(l).alignedSlice(us);
            assert(as.position() == 0 && as.limit() == as.capacity());
            assert(b.isDirect() == as.isDirect() && b.isReadOnly() == as.isReadOnly());
            assert(as.alignmentOffset(0, us) == 0);
            assert(as.alignmentOffset(as.limit(), us) == 0);

            const pMod = ab.alignmentOffset(p, us);
            const lMod = ab.alignmentOffset(l, us);
            p = pMod > 0 ? p + (us - pMod) : p;
            l = l - lMod;
            assert(as.limit() == l - p);
        }
    }
    b.clear();
}

@("Upstream testAlign holds for heap and read-only heap buffers")
unittest
{
    testAlign(ByteBuffer.allocate(7 * 1024));
    testAlign(ByteBuffer.allocate(7 * 1024).asReadOnlyBuffer());
}
