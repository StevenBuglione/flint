// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/cache/interceptor/SimpleKeyGeneratorTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.cache.simple_key_generator_tests;

import flint.cache.interceptor : KeyGenerator, SimpleKey, SimpleKeyGenerator;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : MemberDescriptorRef;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.objects : objectEquals, objectToHash;

@safe:

private final class KeyReceiver
{
    int offset = 41;
}

private final class ReceiverKeyGenerator : KeyGenerator
{
    override Any generate(scope Any target, MemberDescriptorRef method, scope Any[] params...)
    {
        assert(target.typeName() == typeNameOf!KeyReceiver);
        scope auto receiver = cast(KeyReceiver) target.asObject();
        assert(receiver !is null);
        return Any.of(receiver.offset + params[0].get!int());
    }
}

@("custom key generators can read the borrowed receiver and arguments")
unittest
{
    KeyGenerator generator = new ReceiverKeyGenerator();
    auto result = generator.generate(Any.of(new KeyReceiver), MemberDescriptorRef.init, Any.of(1));
    assert(result.get!int() == 42);
}

@("noValues")
unittest
{
    auto generator = new SimpleKeyGenerator();
    auto first = generator.generate(Any.init, MemberDescriptorRef.init);
    auto second = generator.generate(Any.init, MemberDescriptorRef.init);
    auto different = generator.generate(Any.init, MemberDescriptorRef.init, Any.of("different"));
    assert(first.asObject() is SimpleKey.EMPTY);
    assert(first.asObject() is second.asObject());
    assert(objectToHash(first.asObject()) == objectToHash(second.asObject()));
    assert(objectToHash(first.asObject()) != different.toHash());
    assert(first != different);
}

@("singleValue")
unittest
{
    auto first = SimpleKeyGenerator.generateKey(Any.of("a"));
    auto second = SimpleKeyGenerator.generateKey(Any.of("a"));
    auto different = SimpleKeyGenerator.generateKey(Any.of("different"));
    assert(first.toHash() == second.toHash() && first.toHash() != different.toHash());
    assert(first == second && first != different && first == Any.of("a"));
}

@("multipleValues")
unittest
{
    checkKeys([Any.of("a"), Any.of(1), Any.of("b")], [Any.of("b"), Any.of(1), Any.of("a")]);
}

@("singleNullValue")
unittest
{
    auto first = SimpleKeyGenerator.generateKey(Any.init);
    auto second = SimpleKeyGenerator.generateKey(Any.init);
    auto different = SimpleKeyGenerator.generateKey(Any.of("different"));
    assert(cast(SimpleKey) first.asObject() !is null);
    assert(objectEquals(first.asObject(), second.asObject()));
    assert(objectToHash(first.asObject()) == objectToHash(second.asObject()));
    assert(objectToHash(first.asObject()) != different.toHash());
}

@("multipleNullValues")
unittest
{
    checkKeys([Any.of("a"), Any.init, Any.of("b"), Any.init], [Any.of("a"), Any.init, Any.of("b")]);
}

private void checkKeys(scope Any[] same, scope Any[] different)
{
    auto generator = new SimpleKeyGenerator();
    auto first = generator.generate(Any.init, MemberDescriptorRef.init, same).asObject();
    auto second = generator.generate(Any.init, MemberDescriptorRef.init, same).asObject();
    auto other = generator.generate(Any.init, MemberDescriptorRef.init, different).asObject();
    assert(objectEquals(first, second) && !objectEquals(first, other));
    assert(objectToHash(first) == objectToHash(second) && objectToHash(first) != objectToHash(other));
}

@("compound keys own their retained text")
@system unittest
{
    char[3] scratch = ['a', 'b', 'c'];
    auto key = SimpleKeyGenerator.generateKey(Any.of(cast(string) scratch[]), Any.of(1));
    scratch[] = "xyz";
    assert(cast(SimpleKey) key.asObject() !is null);
    assert(key.asObject().objectEquals(SimpleKeyGenerator.generateKey(Any.of("abc"), Any.of(1)).asObject()));
}

@("empty and scalar key generation allocates no memory after startup")
unittest
{
    import core.memory : GC;

    auto input = Any.of("scalar");
    const empty = SimpleKeyGenerator.generateKey();
    const before = GC.stats().allocatedInCurrentThread;
    foreach (i; 0 .. 1_000)
    {
        assert(SimpleKeyGenerator.generateKey() == empty);
        assert(SimpleKeyGenerator.generateKey(input) == input);
        assert(SimpleKeyGenerator.generateKey(3) == Any.of(3));
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("array values make a deep key that owns the supplied elements")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;

    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!(int[]));
    descriptors.add(descriptorOf!(int[][]));
    descriptors.add(descriptorOf!(string[]));
    auto generator = new SimpleKeyGenerator(descriptors);

    auto numbers = [[1, 2], [3]];
    auto words = ["text", ""];
    auto key = generator.generate(Any.init, MemberDescriptorRef.init, Any.of(numbers), Any.of(words)).asObject();
    numbers[0][1] = 8;
    numbers[1] = [9];
    words[0] = "replaced";
    auto matchingWords = Any.of(["text", ""]);
    auto same = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([[1, 2], [3]]), matchingWords).asObject();
    auto different = generator.generate(Any.init, MemberDescriptorRef.init, Any.of(numbers), Any.of(words)).asObject();
    assert(objectEquals(key, same) && !objectEquals(key, different));
    assert(objectToHash(key) == objectToHash(same));
    assert((cast(SimpleKey) key).toString() == "SimpleKey [[[1, 2], [3]], [text, ]]");

    auto one = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([1, 2])).asObject();
    auto another = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([1, 2])).asObject();
    assert(cast(SimpleKey) one !is null && objectEquals(one, another));
    assert(cast(int) objectToHash(one) == -1_908_927_496);
    assert(generator.generate(Any.init, MemberDescriptorRef.init, Any.of(cast(int[]) null))
            .asObject().objectEquals(SimpleKeyGenerator.generateKey(Any.init).asObject()));
}

@("primitive array keys distinguish array types and floating-point signs")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;

    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!(int[]));
    descriptors.add(descriptorOf!(long[]));
    descriptors.add(descriptorOf!(double[]));
    auto generator = new SimpleKeyGenerator(descriptors);

    auto ints = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([1])).asObject();
    auto longs = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([1L])).asObject();
    assert(!objectEquals(ints, longs));
    assert(objectToHash(ints) == objectToHash(longs));

    auto positive = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([0.0, double.nan])).asObject();
    auto negative = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([
        -0.0, double.nan
    ])).asObject();
    auto same = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([0.0, -double.nan])).asObject();
    assert(!objectEquals(positive, negative) && objectEquals(positive, same));
    assert(objectToHash(positive) == objectToHash(same));
}

@("array key snapshots own strings copied out of reused buffers")
@system unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;

    auto descriptors = new DescriptorTable();
    descriptors.add(descriptorOf!(string[]));
    auto generator = new SimpleKeyGenerator(descriptors);
    char[3] scratch = ['a', 'b', 'c'];
    auto key = generator.generate(Any.init, MemberDescriptorRef.init, Any.of([cast(string) scratch[]])).asObject();
    scratch[] = "xyz";
    auto same = generator.generate(Any.init, MemberDescriptorRef.init, Any.of(["abc"])).asObject();
    assert(objectEquals(key, same) && objectToHash(key) == objectToHash(same));
}

@("unregistered arrays and cyclic erased arrays are rejected")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
    import flint.java.lang : IllegalArgumentException;
    import std.exception : assertThrown;

    assertThrown!IllegalArgumentException(SimpleKeyGenerator.generateKey(Any.of([1, 2])));
    auto descriptors = new DescriptorTable();
    descriptors.add(descriptorOf!(Any[]));
    auto generator = new SimpleKeyGenerator(descriptors);
    auto values = new Any[1];
    auto array = Any.of(values);
    values[0] = array;
    assertThrown!IllegalArgumentException(generator.generate(Any.init, MemberDescriptorRef.init, array));
}

@("typed varargs build the same key as the erased AOT path")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;

    auto nested = [[1, 2], [3]];
    auto constructed = new SimpleKey(nested, "catalog", 7);
    auto generated = SimpleKeyGenerator.generateKey(nested, "catalog", 7).asObject();
    nested[0][0] = 9;

    auto descriptors = new DescriptorTable();
    descriptors.add(descriptorOf!(int[]));
    descriptors.add(descriptorOf!(int[][]));
    auto generator = new SimpleKeyGenerator(descriptors);
    auto sameNested = Any.of([[1, 2], [3]]);
    auto erased = generator.generate(Any.init, MemberDescriptorRef.init, sameNested, Any.of("catalog"), Any.of(7));
    assert(objectEquals(constructed, generated) && objectEquals(generated, erased.asObject()));
    assert(objectToHash(constructed) == objectToHash(erased.asObject()));
    assert(!objectEquals(generated, SimpleKeyGenerator.generateKey(nested, "catalog", 7).asObject()));
}

@("typed scalar and null arguments preserve default key selection")
unittest
{
    assert(SimpleKeyGenerator.generateKey(3) == Any.of(3));
    assert(SimpleKeyGenerator.generateKey("name") == Any.of("name"));
    auto nullKey = SimpleKeyGenerator.generateKey(cast(Object) null).asObject();
    auto nullArrayKey = SimpleKeyGenerator.generateKey(cast(int[]) null).asObject();
    assert(objectEquals(nullKey, nullArrayKey));
    auto emptyArray = new int[1];
    auto emptyArrayKey = SimpleKeyGenerator.generateKey(emptyArray[0 .. 0]).asObject();
    assert(cast(SimpleKey) emptyArrayKey !is null);
    assert(!objectEquals(emptyArrayKey, nullArrayKey));
}

@("compound keys preserve Java floating-point equality")
unittest
{
    auto first = SimpleKeyGenerator.generateKey("scale", double.nan).asObject();
    auto same = SimpleKeyGenerator.generateKey("scale", -double.nan).asObject();
    auto positiveZero = SimpleKeyGenerator.generateKey("scale", 0.0).asObject();
    auto negativeZero = SimpleKeyGenerator.generateKey("scale", -0.0).asObject();
    assert(objectEquals(first, same) && objectToHash(first) == objectToHash(same));
    assert(!objectEquals(positiveZero, negativeZero));
}

@("readonly array components keep the same Java primitive key type")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;

    const(int)[] readonly = [1, 2];
    auto direct = SimpleKeyGenerator.generateKey([1, 2]).asObject();
    auto qualified = SimpleKeyGenerator.generateKey(readonly).asObject();
    auto descriptors = new DescriptorTable();
    descriptors.add(descriptorOf!(const(int)[]));
    auto generator = new SimpleKeyGenerator(descriptors);
    auto erased = generator.generate(Any.init, MemberDescriptorRef.init, Any.of(readonly)).asObject();
    assert(objectEquals(direct, qualified) && objectEquals(direct, erased));
    assert(objectToHash(direct) == objectToHash(qualified) && objectToHash(direct) == objectToHash(erased));
}

@("plainArray")
unittest
{
    auto first = SimpleKeyGenerator.generateKey(["a", "b"]).asObject();
    auto same = SimpleKeyGenerator.generateKey(["a", "b"]).asObject();
    auto different = SimpleKeyGenerator.generateKey(["b", "a"]).asObject();
    assert(objectEquals(first, same) && !objectEquals(first, different));
    assert(objectToHash(first) == objectToHash(same) && objectToHash(first) != objectToHash(different));
}

@("arrayWithExtraParameter")
unittest
{
    auto first = SimpleKeyGenerator.generateKey(["a", "b"], "c").asObject();
    auto same = SimpleKeyGenerator.generateKey(["a", "b"], "c").asObject();
    auto different = SimpleKeyGenerator.generateKey(["b", "a"], "c").asObject();
    assert(objectEquals(first, same) && !objectEquals(first, different));
    assert(objectToHash(first) == objectToHash(same) && objectToHash(first) != objectToHash(different));
}

@("packed Any arguments use the erased varargs overload")
unittest
{
    Any[2] arguments = [Any.of("catalog"), Any.of(7)];
    auto packed = SimpleKeyGenerator.generateKey(arguments[]).asObject();
    auto typed = SimpleKeyGenerator.generateKey("catalog", 7).asObject();
    assert(objectEquals(packed, typed));
    assert(objectEquals(new SimpleKey(arguments[]), typed));
}
