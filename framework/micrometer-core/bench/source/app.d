module app;

import core.stdc.stdio : fputc, stdout;
import flint.micrometer.core.instrument : Tags;

@safe:

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto tags = Tags.of("region", region, "method", "GET").and("method", "POST");
    foreach (character; tags.toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
