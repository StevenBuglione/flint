// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionMessageTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use a local Test UDA for JUnit's annotation type token (R2, R4).
module autoconfigure_tests.condition_message_test;

import flint.boot.autoconfigure.condition_runtime : ConditionMessage, applyTo;
import flint.engine.aot.any : Any;
import flint.java.util : ArrayList, Collection;
import std.typecons : Nullable;

@safe:

private struct Test
{
}

@("isEmptyWhenEmptyShouldReturnTrue")
unittest
{
    assert(ConditionMessage.empty().isEmpty());
}

@("isEmptyWhenNotEmptyShouldReturnFalse")
unittest
{
    assert(!ConditionMessage.of("Test").isEmpty());
}

@("toStringWhenEmptyShouldReturnEmptyString")
unittest
{
    assert(ConditionMessage.empty().toString() == "");
}

@("toStringWhenHasMessageShouldReturnMessage")
unittest
{
    assert(ConditionMessage.of("Test").toString() == "Test");
}

@("appendWhenHasExistingMessageShouldAddSpace")
unittest
{
    assert(ConditionMessage.of("a").append(Nullable!string("b")).toString() == "a b");
}

@("appendWhenAppendingNullShouldDoNothing")
unittest
{
    auto message = ConditionMessage.of("a");
    assert(message.append(Nullable!string.init) is message);
}

@("appendWhenNoMessageShouldNotAddSpace")
unittest
{
    assert(ConditionMessage.empty().append(Nullable!string("b")).toString() == "b");
}

@("andConditionWhenUsingClassShouldIncludeCondition")
unittest
{
    auto message = ConditionMessage.empty().andCondition!Test().because(Nullable!string("OK"));
    assert(message.toString() == "@Test OK");
}

@("andConditionWhenUsingStringShouldIncludeCondition")
unittest
{
    auto message = ConditionMessage.empty().andCondition("@Test").because(Nullable!string("OK"));
    assert(message.toString() == "@Test OK");
}

@("andConditionWhenIncludingDetailsShouldIncludeCondition")
unittest
{
    auto message = ConditionMessage.empty().andCondition!Test("(a=b)").because(Nullable!string("OK"));
    assert(message.toString() == "@Test (a=b) OK");
}

@("ofCollectionShouldCombine")
unittest
{
    auto messages = new ArrayList!ConditionMessage;
    messages.add(ConditionMessage.of("a"));
    messages.add(ConditionMessage.of("b"));
    assert(ConditionMessage.of(messages).toString() == "a; b");
}

@("ofCollectionWhenNullShouldReturnEmpty")
unittest
{
    Collection!ConditionMessage messages;
    assert(ConditionMessage.of(messages).isEmpty());
}

@("forConditionShouldIncludeCondition")
unittest
{
    auto message = ConditionMessage.forCondition("@Test").because(Nullable!string("OK"));
    assert(message.toString() == "@Test OK");
}

@("forConditionShouldNotAddExtraSpaceWithEmptyCondition")
unittest
{
    auto message = ConditionMessage.forCondition("").because(Nullable!string("OK"));
    assert(message.toString() == "OK");
}

@("forConditionWhenClassShouldIncludeCondition")
unittest
{
    auto message = ConditionMessage.forCondition!Test("(a=b)").because(Nullable!string("OK"));
    assert(message.toString() == "@Test (a=b) OK");
}

@("foundExactlyShouldConstructMessage")
unittest
{
    assert(ConditionMessage.forCondition!Test().foundExactly("abc").toString() == "@Test found abc");
}

@("foundWhenSingleElementShouldUseSingular")
unittest
{
    auto message = ConditionMessage.forCondition!Test().found("bean", "beans").items("a");
    assert(message.toString() == "@Test found bean a");
}

@("foundNoneAtAllShouldConstructMessage")
unittest
{
    auto message = ConditionMessage.forCondition!Test().found("no beans").atAll();
    assert(message.toString() == "@Test found no beans");
}

@("foundWhenMultipleElementsShouldUsePlural")
unittest
{
    auto message = ConditionMessage.forCondition!Test().found("bean", "beans").items("a", "b", "c");
    assert(message.toString() == "@Test found beans a, b, c");
}

@("foundWhenQuoteStyleShouldQuote")
unittest
{
    auto message = ConditionMessage.forCondition!Test().found("bean", "beans")
        .items(ConditionMessage.Style.QUOTE, "a", "b", "c");
    assert(message.toString() == "@Test found beans 'a', 'b', 'c'");
}

@("didNotFindWhenSingleElementShouldUseSingular")
unittest
{
    auto message = ConditionMessage.forCondition!Test().didNotFind("class", "classes").items("a");
    assert(message.toString() == "@Test did not find class a");
}

@("didNotFindWhenMultipleElementsShouldUsePlural")
unittest
{
    auto message = ConditionMessage.forCondition!Test().didNotFind("class", "classes").items("a", "b", "c");
    assert(message.toString() == "@Test did not find classes a, b, c");
}

@("resultedInShouldConstructMessage")
unittest
{
    auto message = ConditionMessage.forCondition!Test().resultedIn("Green");
    assert(message.toString() == "@Test resulted in Green");
}

@("notAvailableShouldConstructMessage")
unittest
{
    auto message = ConditionMessage.forCondition!Test().notAvailable("JMX");
    assert(message.toString() == "@Test JMX is not available");
}

@("availableShouldConstructMessage")
unittest
{
    auto message = ConditionMessage.forCondition!Test().available("JMX");
    assert(message.toString() == "@Test JMX is available");
}

@("itemsTolerateNullInput")
unittest
{
    Collection!Any items;
    auto message = ConditionMessage.forCondition!Test().didNotFind("item").items(items);
    assert(message.toString() == "@Test did not find item");
}

@("quotedItemsTolerateNullInput")
unittest
{
    Collection!Any items;
    auto message = ConditionMessage.forCondition!Test().didNotFind("item").items(ConditionMessage.Style.QUOTE, items);
    assert(message.toString() == "@Test did not find item");
}

@("condition message formats Java arguments and joins successive conditions")
unittest
{
    auto prior = ConditionMessage.of("count=%d, state=%s", 3, "ready");
    auto next = prior.andCondition!Test().because(Nullable!string("OK"));
    assert(next.toString() == "count=3, state=ready; @Test OK");
    assert(prior.toString() == "count=3, state=ready");
}

@("condition message equality preserves a missing message")
unittest
{
    auto missing = ConditionMessage.empty();
    auto explicitEmpty = ConditionMessage.of("");
    assert(missing == ConditionMessage.empty());
    assert(missing.hashCode() == ConditionMessage.empty().hashCode());
    assert(explicitEmpty.isEmpty());
    assert(!missing.equals(explicitEmpty));
    assert(!missing.equals(null));
}

@("condition message styles non-null items and preserves their encounter order")
unittest
{
    alias Style = ConditionMessage.Style;
    auto values = new ArrayList!Any([Any.of("first"), Any.init, Any.of("second")]);
    auto items = ConditionMessage.forCondition!Test().found("item", "items");
    assert(items.items(Style.QUOTE, values).toString() == "@Test found items 'first', 'second'");
    assert(items.items(Style.QUOTE).toString() == "@Test found item");

    const plain = Style.NORMAL.applyTo(values).toArray();
    assert(plain == [Any.of("first"), Any.of("second")]);
    const quoted = Style.QUOTE.applyTo(values).toArray();
    assert(quoted == [Any.of("'first'"), Any.of("'second'")]);
    assert(Style.QUOTE.applyTo(null) is null);
}

@("condition message keeps or drops null arguments according to the method")
unittest
{
    assert(ConditionMessage.of("%s", null).toString() == "null");
    auto builder = ConditionMessage.forCondition!Test();
    assert(builder.resultedIn(null).toString() == "@Test resulted in null");
    assert(builder.foundExactly(null).toString() == "@Test found");
    assert(builder.found("item", "items").items(null, "present").toString() == "@Test found item present");

    string missing;
    assert(ConditionMessage.of(missing).equals(ConditionMessage.empty()));
}
