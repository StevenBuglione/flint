module app;

import core.stdc.stdio : fputc, stdout;
import flint.micrometer.common : KeyValue, KeyValues;
import flint.micrometer.observation : Observation;

@safe:

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto context = new Observation.Context;
    context.addLowCardinalityKeyValues(KeyValues.of("method", "GET", "region", region, "transport",
            "http")).addHighCardinalityKeyValue(KeyValue.of("method", "POST"))
        .removeLowCardinalityKeyValues("transport");
    foreach (character; context.getAllKeyValues().toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
