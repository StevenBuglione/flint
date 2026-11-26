module random_id_generator_contract_tests;

import flint.ai.document.id : IdGenerator, RandomIdGenerator;
import flint.engine.aot.any : Any;

@safe:

@("random document IDs use the canonical version 4 UUID text")
unittest
{
    auto generator = new RandomIdGenerator();
    const id = generator.generateId();
    assert(id.length == 36);
    assert(id[14] == '4');
    assert(id[19] == '8' || id[19] == '9' || id[19] == 'a' || id[19] == 'b');
    foreach (i, character; id)
    {
        if (i == 8 || i == 13 || i == 18 || i == 23)
            assert(character == '-');
        else
            assert((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'));
    }
}

@("random document IDs ignore contents on both virtual and typed calls")
unittest
{
    auto random = new RandomIdGenerator();
    IdGenerator generator = random;
    Any[2] contents = [Any.of("same document"), Any.of(7)];
    const first = generator.generateId(contents[]);
    const second = random.generateId("same document", 7);
    const third = generator.generateId(cast(Any[]) null);
    assert(first != second && first != third && second != third);
    assert(contents[0].get!string == "same document" && contents[1].get!int == 7);
}
