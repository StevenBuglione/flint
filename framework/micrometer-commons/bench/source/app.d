module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util : Arrays;
import flint.micrometer.common : KeyValue, KeyValues;

@safe:

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto source = KeyValues.of("region", KeyValue.NONE_VALUE, "method", "GET");
    auto regionValue = KeyValues.of!string(Arrays.asList!string(region), (_) => "region", (name) => name);
    auto values = source.and(regionValue).and("method", "POST");
    if (values.stream().count() != 2)
        return;

    foreach (character; values.toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
