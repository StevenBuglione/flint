module id_generator_contract_tests;

import flint.ai.document.id : IdGenerator;
import flint.engine.aot.any : Any;

@safe:

private final class FixtureGenerator : IdGenerator
{
    alias generateId = IdGenerator.generateId;

    override string generateId(scope Any[] contents)
    {
        if (contents.length == 0)
            return contents is null ? "null-array" : "empty-array";

        if (contents.length == 1)
        {
            assert(contents[0].isNull);
            return "null-value";
        }

        assert(contents.length == 3);
        assert(contents[0].get!string == "document");
        assert(contents[1].get!int == 7);
        assert(contents[2].isNull);
        contents[1] = Any.of(8);
        return "generated";
    }
}

@("document ID varargs preserve the type, order, and null argument")
unittest
{
    auto generator = new FixtureGenerator();
    assert(generator.generateId("document", Any.of(7), null) == "generated");
    assert(generator.generateId() == "empty-array");
}

@("document ID implementations receive the supplied erased array")
unittest
{
    IdGenerator generator = new FixtureGenerator();
    Any[3] contents = [Any.of("document"), Any.of(7), Any.init];
    assert(generator.generateId(contents[]) == "generated");
    assert(contents[1].get!int == 8);
    assert(generator.generateId(cast(Any[]) null) == "null-array");
    assert(generator.generateId(null) == "null-array");
    assert(generator.generateId(Any.init) == "null-value");
}
