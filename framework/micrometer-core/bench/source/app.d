module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Tags;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;

@safe:

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto tags = Tags.of("region", region, "method", "GET").and("method", "POST");
    auto timer = (new SimpleMeterRegistry).timer("request.duration", tags);
    timer.record(250, TimeUnit.MILLISECONDS);
    if (timer.count() != 1 || timer.totalTime(TimeUnit.SECONDS) != 0.25 || timer.max(TimeUnit.SECONDS) != 0.25)
        return;
    foreach (character; tags.toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
