/++
Flint tests: bean property names written from their prepared form (BeanPropertyWriter's SerializedString) come out
exactly as `JsonGenerator.writeName` writes them, under every feature that changes how a name is written.
+/
module prepared_names_test;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.jackson.annotation : JsonProperty;
import flint.jackson.core.json : JsonWriteFeature;
import flint.jackson.databind : JsonMapper;

@safe:

private struct Plain
{
    int plain = 1;
}

private struct Slash
{
    @JsonProperty("a/b")
    int slash = 2;
}

private struct Accent
{
    @JsonProperty("ü")
    int accent = 3;
}

private struct Quote
{
    @JsonProperty("q\"t")
    int quote = 4;
}

// `{name:value}` written by hand through the mapper's own generator.
private string byHand(JsonMapper mapper, string name, int value)
{
    string text;
    auto g = mapper.createGenerator((scope const(ubyte)[] bytes) { text ~= cast(const(char)[]) bytes; });
    g.writeStartObject();
    g.writeName(name);
    g.writeNumber(value);
    g.writeEndObject();
    g.close();
    return text;
}

@("a prepared property name writes what writeName writes, quoted or not, escaped or not")
unittest
{
    auto table = DescriptorTable.withBuiltins();
    table.add(descriptorOf!Plain());
    table.add(descriptorOf!Slash());
    table.add(descriptorOf!Accent());
    table.add(descriptorOf!Quote());
    foreach (quote; [true, false])
        foreach (nonAscii; [false, true])
            foreach (slash; [true, false])
            {
                auto mapper = JsonMapper.builder().descriptors(table)
                    .configure(JsonWriteFeature.QUOTE_PROPERTY_NAMES, quote)
                    .configure(JsonWriteFeature.ESCAPE_NON_ASCII, nonAscii).configure(
                        JsonWriteFeature.ESCAPE_FORWARD_SLASHES, slash).build();
                assert(mapper.writeValueAsString(Plain()) == byHand(mapper, "plain", 1));
                assert(mapper.writeValueAsString(Slash()) == byHand(mapper, "a/b", 2));
                assert(mapper.writeValueAsString(Accent()) == byHand(mapper, "ü", 3));
                assert(mapper.writeValueAsString(Quote()) == byHand(mapper, "q\"t", 4));
            }
}
