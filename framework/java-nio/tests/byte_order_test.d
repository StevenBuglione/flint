// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 ByteOrder API.
module byte_order_test;

import flint.java.nio.byteorder : ByteOrder;

@safe:

static assert(!__traits(compiles, ByteOrder(true)));

private string orderName(ByteOrder order) pure nothrow @nogc
{
    return order.toString();
}

@("ByteOrder constants are distinct values that can be assigned")
unittest
{
    ByteOrder order = ByteOrder.BIG_ENDIAN;
    assert(orderName(order) == "BIG_ENDIAN");
    assert(order != ByteOrder.LITTLE_ENDIAN);
    assert(ByteOrder.init == order);

    order = ByteOrder.LITTLE_ENDIAN;
    assert(orderName(order) == "LITTLE_ENDIAN");
    assert(order == ByteOrder.LITTLE_ENDIAN);
}

@("ByteOrder native order matches the target")
unittest
{
    const ByteOrder order = ByteOrder.nativeOrder();
    version (LittleEndian)
        assert(order == ByteOrder.LITTLE_ENDIAN);
    else
        assert(order == ByteOrder.BIG_ENDIAN);
}
