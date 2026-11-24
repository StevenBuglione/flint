/++
Flint tests: a bean property remembers how a value of its exact declared type is written (bean, Nullable or
collection), and writes exactly what the full dispatch writes, also when later values have another runtime class, are
null, or are empty.
+/
module property_route_test;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.jackson.databind : JsonMapper;
import flint.java.util : ArrayList, List;
import std.typecons : Nullable;

@safe:

private class Animal
{
    string name = "a";
}

private final class Dog : Animal
{
    int barks = 2;
}

private final class PetHolder
{
    Animal pet;
}

private final class IdHolder
{
    Nullable!int id;
}

private final class ListHolder
{
    List!Animal pets;
}

private JsonMapper mapper()
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!Animal());
    table.add(descriptorOf!Dog());
    table.add(descriptorOf!PetHolder());
    table.add(descriptorOf!IdHolder());
    table.add(descriptorOf!ListHolder());
    table.add(descriptorOf!(Nullable!int)());
    table.add(descriptorOf!(List!Animal)());
    return JsonMapper.builder().descriptors(table).build();
}

@("a bean property written by its route matches the full dispatch, whatever class each value has")
unittest
{
    auto m = mapper();
    auto holder = new PetHolder();
    foreach (round; 0 .. 2)
        foreach (Animal pet; [new Animal(), new Dog(), new Animal(), null])
        {
            holder.pet = pet;
            const inner = pet is null ? "null" : m.writeValueAsString(pet);
            assert(m.writeValueAsString(holder) == `{"pet":` ~ inner ~ `}`, m.writeValueAsString(holder));
        }
}

@("a Nullable property written by its route: its value, or null")
unittest
{
    auto m = mapper();
    auto holder = new IdHolder();
    foreach (id; [Nullable!int(7), Nullable!int.init, Nullable!int(-1)])
    {
        holder.id = id;
        const expected = id.isNull ? `{"id":null}` : id.get == 7 ? `{"id":7}` : `{"id":-1}`;
        assert(m.writeValueAsString(holder) == expected, m.writeValueAsString(holder));
    }
}

@("a collection property written by its route: each element by its own class")
unittest
{
    auto m = mapper();
    auto holder = new ListHolder();
    foreach (round; 0 .. 2)
    {
        auto pets = new ArrayList!Animal();
        holder.pets = pets;
        assert(m.writeValueAsString(holder) == `{"pets":[]}`, m.writeValueAsString(holder));
        pets.add(new Dog());
        pets.add(new Animal());
        const expected = `{"pets":[` ~ m.writeValueAsString(
                cast(Animal) new Dog()) ~ "," ~ m.writeValueAsString(new Animal()) ~ `]}`;
        assert(m.writeValueAsString(holder) == expected, m.writeValueAsString(holder));
    }
}
