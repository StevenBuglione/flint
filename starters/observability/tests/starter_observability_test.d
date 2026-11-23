module flint.starter_observability.starter_observability_test;

import flint.arena : Status;
import flint.di : AppContext;
import flint.starter_observability : ManagementProperties, Observability, ObservabilityAutoConfiguration;

@safe:

@("the registry opens with the bound settings, counts, and closes with the context")
unittest
{
    AppContext!(ObservabilityAutoConfiguration) context;
    ManagementProperties properties;
    properties.serviceName = "orders";
    assert(context.provide(properties).code == Status.ok);
    assert(context.initialize().code == Status.ok);
    auto counter = context.get!Observability().registry().counter("orders_created_total", "Orders created");
    assert(counter.ok);
    context.shutdown();
}

@("an invalid path prefix fails start-up")
unittest
{
    AppContext!(ObservabilityAutoConfiguration) context;
    ManagementProperties properties;
    properties.pathPrefix = "actuator/";
    assert(context.provide(properties).code == Status.ok);
    assert(context.initialize().code != Status.ok);
}
