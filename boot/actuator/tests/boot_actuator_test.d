module flint.boot_actuator.boot_actuator_test;

import flint.arena : Status;
import flint.di : AppContext;
import flint.boot_actuator : ActuatorAutoConfiguration, ManagementProperties, Observability;

@safe:

@("the registry opens with the bound settings, counts, and closes with the context")
unittest
{
    AppContext!(ActuatorAutoConfiguration) context;
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
    AppContext!(ActuatorAutoConfiguration) context;
    ManagementProperties properties;
    properties.pathPrefix = "actuator/";
    assert(context.provide(properties).code == Status.ok);
    assert(context.initialize().code != Status.ok);
}
