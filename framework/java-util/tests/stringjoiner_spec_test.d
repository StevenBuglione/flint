/*
 * Copyright Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
module stringjoiner_spec_test;

import flint.java.lang : NullPointerException;
import flint.java.util.stringjoiner : StringJoiner;
import std.exception : assertThrown;

@safe:

@("StringJoiner counts UTF-16 units through custom empty output, merge and self-merge") unittest
{
    auto first = new StringJoiner("💚", "α", "β").setEmptyValue("");
    assert(first.length() == 0 && first.toString() == "");
    assert(first.add("").add(null).add("😀") is first);
    assert(first.length() == 12 && first.toString() == "α💚null💚😀β");

    auto second = new StringJoiner(":", "<", ">").add("x").add("y");
    assert(first.merge(second) is first);
    assert(first.length() == 17 && first.toString() == "α💚null💚😀💚x:yβ");
    assert(first.merge(first).length() == 34);
    assert(first.toString() == "α💚null💚😀💚x:y💚💚null💚😀💚x:yβ");
    assert(second.add("z").toString() == "<x:y:z>");
}

@("StringJoiner distinguishes an empty joiner from a joiner containing an empty string") unittest
{
    auto receiver = new StringJoiner(" | ", "(", ")").setEmptyValue("unpopulated");
    auto incoming = new StringJoiner("/", "begin", "end").setEmptyValue("ignored");
    assert(receiver.merge(incoming).toString() == "unpopulated");
    incoming.add("");
    assert(receiver.merge(incoming).toString() == "()");
    incoming.add("later");
    assert(receiver.add("new").toString() == "( | new)");
}

@("StringJoiner validates separators, framing, empty values and merge arguments") unittest
{
    assertThrown!NullPointerException(new StringJoiner(null));
    assertThrown!NullPointerException(new StringJoiner(";", null, "end"));
    assertThrown!NullPointerException(new StringJoiner(";", "begin", null));
    auto joiner = new StringJoiner("=", "«", "»");
    assertThrown!NullPointerException(joiner.setEmptyValue(null));
    assertThrown!NullPointerException(joiner.merge(null));
    assert(joiner.toString() == "«»");
}

@("StringJoiner preserves order and its snapshot while expanding element storage") unittest
{
    auto joiner = new StringJoiner(",", "[", "]");
    foreach (element; ["a", "b", "c", "d", "e", "f", "g", "h"])
        joiner.add(element);
    assert(joiner.merge(joiner).toString() == "[a,b,c,d,e,f,g,h,a,b,c,d,e,f,g,h]");
    assert(joiner.length() == 33);
    assert(joiner.add("i").toString() == "[a,b,c,d,e,f,g,h,a,b,c,d,e,f,g,h,i]");
}
