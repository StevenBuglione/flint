module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.function_ : Supplier;
import flint.micrometer.core.instrument : Clock, MockClock, Tags, Timer;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;

@safe:

private alias RegionCallable = Callable!string;
private alias RegionSupplier = Supplier!string;

private final class Region : RegionCallable, RegionSupplier
{
    private const string value;

    this(string region)
    {
        value = region;
    }

    override string call()
    {
        return value;
    }

    override string get()
    {
        return value;
    }
}

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    auto tags = Tags.of("region", region, "method", "GET").and("method", "POST");
    auto registry = new SimpleMeterRegistry;
    if (registry.config().clock() !is Clock.SYSTEM)
        return;
    auto timer = Timer.builder("request.duration").tags(tags).register(registry);
    auto clock = new MockClock;
    auto sample = Timer.start(clock);
    clock.add(250, TimeUnit.MILLISECONDS);
    if (sample.stop(timer) != 250_000_000 || timer.count() != 1
            || timer.totalTime(TimeUnit.SECONDS) != 0.25 || timer.max(TimeUnit.SECONDS) != 0.25)
        return;
    auto action = new Region(region);
    RegionCallable callable = action;
    if (timer.recordCallable(callable) != region || timer.count() != 2)
        return;
    RegionSupplier supplier = action;
    if (timer.record(supplier) != region || timer.count() != 3)
        return;
    foreach (character; tags.toString())
        fputc(character, stdout);
    fputc('\n', stdout);
}
