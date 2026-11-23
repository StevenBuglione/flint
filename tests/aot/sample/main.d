/// Boots the conformance runtime from the generated registry and prints what the sample did; the Flint AOT test
/// compares the output with the expected text.
module sample_main;

import aot_context : AotContext;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor;
import flint.engine.aot.mapping : HandlerArguments;
import flint.engine.aot.proxy : Advisor, DetachedExecutor, Invocation, Proceed;
import flint.engine.aot.registry : installedRegistry;
import shop.config : AuditLog, ClockReport, Greeter;
import shop.data : OwnerStatus;
import shop.owners : OwnerService, OwnerStore;
import shop.web : Greeting;
import std.stdio : writeln;

@safe:

/// Logs every advised call and serves `@Cacheable` methods from a map.
final class Recorder : Advisor
{
    string[] log;
    Any[string] cache;

    bool appliesTo(const Descriptor descriptor, const(MethodDescriptor)* method)
    {
        return method.annotations.length > 0;
    }

    int getOrder()
    {
        return 0;
    }

    void invoke(ref Invocation invocation, scope Proceed next)
    {
        import std.algorithm.searching : endsWith;
        import std.conv : to;

        string names;
        bool cacheable;
        foreach (ref annotation; invocation.method.annotations)
        {
            names ~= " " ~ annotation.type;
            cacheable = cacheable || annotation.type.endsWith(".Cacheable");
        }
        log ~= invocation.method.name ~ ":" ~ names;
        if (!cacheable)
            return next(invocation);
        const key = invocation.method.name ~ invocation.arguments[0].get!long.to!string;
        if (auto hit = key in cache)
        {
            invocation.result = *hit;
            return;
        }
        next(invocation);
        cache[key] = invocation.result;
    }
}

/// Queues @Async work until `drain`.
final class Queue : DetachedExecutor
{
    void delegate() @safe[] pending;

    void execute(void delegate() @safe task)
    {
        pending ~= task;
    }

    void drain()
    {
        auto work = pending;
        pending = null;
        foreach (item; work)
            item();
    }
}

final class Arguments : HandlerArguments
{
    Any[] values;

    this(Any[] values)
    {
        this.values = values;
    }

    Any get(size_t index)
    {
        return values[index];
    }
}

void scenario(string label, string[] profiles, string[string] properties)
{
    import std.array : join;
    import std.conv : to;

    auto recorder = new Recorder;
    auto queue = new Queue;
    auto context = new AotContext(profiles, properties);
    context.provide("flint.engine.aot.proxy.Advisor", recorder);
    context.provide("flint.engine.aot.proxy.DetachedExecutor", queue);
    installedRegistry()(context);
    context.refresh();
    writeln("== ", label);
    writeln("application: ", context.applicationType);
    string[] names;
    foreach (ref definition; context.active)
        names ~= definition.name;
    writeln("beans: ", names.join(" "));
    writeln("greeter: ", (cast(Greeter) context.getBeanOfType("shop.config.Greeter")).greet("Ada"));
    writeln("audit: ", context.findBeanOfType("shop.config.AuditLog") !is null);
    writeln("clock: ", (cast(ClockReport) context.getBean("clockReport")).singleton ? "singleton" : "created twice");
    auto service = cast(OwnerService) context.getBean("ownerService");
    writeln("proxy: ", typeid(service).name, " ready=", service.isReady(), " (proxy field ready=", service.ready, ")");
    writeln("findName: ", service.findName(1), " calls=", service.callCount());
    writeln("findName again: ", service.findName(1), " calls=", service.callCount(), " (cache hit)");
    writeln("describe: ", service.describe(1), " calls=", service.callCount(), " (self-invocation skips the cache)");
    service.notifyOwner(1);
    writeln("async queued: ", queue.pending.length, " calls=", service.callCount());
    queue.drain();
    writeln("async drained: calls=", service.callCount());
    writeln("advice: ", recorder.log.join(" | "));
    foreach (ref mapping; context.mappings)
    {
        Any result;
        mapping.invoke(context.getBean(mapping.bean), new Arguments([Any.of(2L), Any.of("Hello")]), result);
        const greeting = result.get!Greeting;
        writeln("mapping: ", mapping.methods.join(","), " ", mapping.paths.join(","), " -> ", greeting.id, " ",
                greeting.content, " (", mapping.arguments.length.to!string, " arguments, ",
                mapping.arguments[1].defaultValue, ")");
    }
    foreach (ref query; context.queries)
        writeln("query: ", query.method, ": ", query.sql);
    foreach (descriptor; context.descriptors)
    {
        if (descriptor.name == "shop.web.Greeting")
        {
            auto value = descriptor.create();
            descriptor.properties[1].set(value, Any.of("set through the descriptor"));
            writeln("descriptor: ", descriptor.properties.length, " properties, content = ",
                    descriptor.properties[1].get(value).get!string);
            auto made = descriptor.constructors[0].invoke([Any.of(7L), Any.of("built by the canonical constructor")]);
            writeln("creator: ", descriptor.constructors.length, " constructor(s), parameters ",
                    descriptor.constructors[0].parameters[0].name, ", ", descriptor.constructors[0].parameters[1].name,
                    " -> ", made.get!Greeting.id, " ", made.get!Greeting.content);
        }
    }
    foreach (descriptor; context.descriptors)
    {
        if (descriptor.name == "shop.data.OwnerStatus")
            writeln("enum: ", descriptor.enumConstants.length, " constants, ordinal 1 = ",
                    descriptor.enumValue(1).get!OwnerStatus, ", ordinal 9 null = ", descriptor.enumValue(9).isNull);
    }
    auto store = cast(OwnerStore) context.getBean("ownerStore");
    context.close();
    writeln("shutdown: ", store.events.join(", "));
}

void main()
{
    scenario("default profile, audit on", null, ["shop.audit.enabled": "true"]);
    scenario("prod profile", ["prod"], null);
}
