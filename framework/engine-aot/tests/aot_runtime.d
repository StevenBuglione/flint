module flint.engine.aot.aot_runtime_test;

import flint.engine.aot.any : Any, AnyTypeException, Box;
import flint.engine.aot.bean : BeanDefinition, BeanFactory, ScopeKind;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, MergedAnnotation,
    MethodDescriptor, TypeKind, descriptorOf, findAnnotation;
import flint.engine.aot.event : EventListenerSpec;
import flint.engine.aot.mapping : ExceptionHandlerSpec, HandlerMapping;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.proxy : AdviceChain, Advisor, Invocation, Proceed, adviceChain, allocateProxy;
import flint.engine.aot.query : DerivedQuery;
import flint.engine.aot.registry : AotContractException, AotRegistry, aotContractVersion,
    checkContractVersion, installRegistry, installedRegistry;
import flint.engine.aot_test_annotations : AliasFor, Component, GetMapping, Mapping, Service, Special;

@safe:

private interface Repository
{
}

private class Base : Repository
{
}

@Service("owners")
@GetMapping("/owners")
private class OwnerService : Base
{
    string city = "Madison";
    int visits;
    private int hidden;
    private string name_ = "Betty";

    string getName()
    {
        return name_;
    }

    void setName(string name)
    {
        name_ = name;
    }

    bool isActive()
    {
        return true;
    }
}

private struct Pet
{
    string name;
    int age;
    immutable int id = 7;
}

private enum Colour : int
{
    red = 1,
    blue = 2,
}

private enum Shade : string
{
    light = "l",
}

unittest
{
    // Canonical names: fully qualified, qualifiers ignored.
    auto owner = descriptorOf!OwnerService;
    assert(owner.name == "flint.engine.aot.aot_runtime_test.OwnerService");
    assert(owner.kind == TypeKind.class_ && owner.simpleName == "OwnerService");
    assert(descriptorOf!(const OwnerService).name == owner.name);
    // Supertypes: classes and interfaces, nearest first, without Object.
    assert(owner.supertypes == [
        "flint.engine.aot.aot_runtime_test.Base", "flint.engine.aot.aot_runtime_test.Repository"
    ]);
    assert(owner.isAssignableTo(typeNameOf!Repository) && owner.isAssignableTo(owner.name));
    assert(!descriptorOf!Base.isAssignableTo(owner.name));
    assert(descriptorOf!Colour.kind == TypeKind.enum_ && descriptorOf!Colour.enumConstants == [
        "red", "blue"
    ]);
    assert(descriptorOf!(int[]).kind == TypeKind.array && descriptorOf!(int[]).elementType == "int");
    assert(descriptorOf!(int[string]).keyType == "string");
    assert(descriptorOf!string.kind == TypeKind.string_ && descriptorOf!long.kind == TypeKind.scalar);
}

unittest
{
    // Merged annotations: declared first, then meta-annotations by distance, @AliasFor applied.
    auto owner = descriptorOf!OwnerService;
    assert(owner.annotations.length == 4);
    assert(owner.annotations[0].type == typeNameOf!Service && owner.annotations[0].distance == 0);
    assert(owner.annotations[0].value.get!Service.value == "owners");
    assert(owner.annotations[1].type == typeNameOf!GetMapping);
    const component = owner.annotation(typeNameOf!Component);
    assert(component !is null && component.distance == 1);
    assert(component.value.get!Component.value == "owners");
    // @Mapping keeps its own method and gets value from @GetMapping, mirrored onto path.
    const mapping = owner.annotation(typeNameOf!Mapping).value.get!Mapping;
    assert(mapping.method == "GET" && mapping.value == "/owners" && mapping.path == "/owners");
    assert(owner.annotation("no.such.Annotation") is null);
}

unittest
{
    // Two levels: @Special(name) -> @Service(value) -> @Component(value). An unset alias keeps the default.
    @Special("deep") static final class Deep
    {
    }

    auto deep = descriptorOf!Deep;
    assert(deep.annotations.length == 3);
    assert(deep.annotation(typeNameOf!Service).value.get!Service.value == "deep");
    assert(deep.annotation(typeNameOf!Component).distance == 2);
    assert(deep.annotation(typeNameOf!Component).value.get!Component.value == "deep");

    @Special static final class Plain
    {
    }

    assert(descriptorOf!Plain.annotation(typeNameOf!Component).value.get!Component.value == "");
    // A declared annotation beats the same annotation reached as a meta-annotation.
    @Component("direct") @Service("viaService") static final class Both
    {
    }

    const both = descriptorOf!Both.annotation(typeNameOf!Component);
    assert(both.distance == 0 && both.value.get!Component.value == "direct");
}

unittest
{
    // Properties: public fields, then Java Beans accessors, decapitalized.
    auto owner = descriptorOf!OwnerService;
    assert(owner.property("city") !is null && owner.property("visits") !is null);
    assert(owner.property("hidden") is null);
    auto name = owner.property("name");
    assert(name !is null && name.type == "string" && name.get !is null && name.set !is null);
    auto active = owner.property("active");
    assert(active !is null && active.set is null);

    auto service = new OwnerService;
    auto self = Any.of(service);
    assert(owner.property("city").get(self).get!string == "Madison");
    owner.property("city").set(self, Any.of("Monona"));
    assert(service.city == "Monona");
    name.set(self, Any.of("Jean"));
    assert(service.getName() == "Jean" && name.get(self).get!string == "Jean");
    assert(active.get(self).get!bool);
    assert(owner.create !is null && owner.create().get!OwnerService !is null);

    // Struct values are boxed; setters write through the box. Immutable fields have no setter.
    auto pet = Any.of(Pet("Leo", 3));
    auto age = descriptorOf!Pet.property("age");
    assert(age.get(pet).get!int == 3);
    age.set(pet, Any.of(4));
    assert(pet.get!Pet.age == 4);
    pet.get!Pet.age = 5; // a ref into the box
    assert(pet.get!Pet.age == 5);
    assert(descriptorOf!Pet.property("id").set is null);
    assert(descriptorOf!Pet.create().get!Pet.name is null);
}

unittest
{
    // Scalars, strings, enums, floating point and arrays.
    assert(Any.init.isNull && Any.init.typeName == "");
    assert(Any.of(42).get!int == 42 && Any.of(42).typeName == "int");
    assert(Any.of(42).get!long == 42 && Any.of(42L).get!ubyte == 42);
    assert(Any.of(3).get!double == 3.0 && Any.of(2.5).get!double == 2.5);
    assert(Any.of(true).get!bool && Any.of('x').get!char == 'x');
    assert(Any.of("x").get!string == "x" && Any.of("x").typeName == "string");
    char[] buffer = ['a', 'b'];
    const copied = Any.of(buffer);
    buffer[0] = 'z';
    assert(copied.get!string == "ab");
    assert(Any.of(Colour.blue).get!Colour == Colour.blue);
    assert(descriptorOf!Colour.enumValues == [1, 2]);
    assert(Any.ofEnum(typeNameOf!Colour, 2).get!Colour == Colour.blue && Any.of(Colour.red).enumBits == 1);
    assert(Any.of(Colour.red).isEnum && !Any.of(1).isEnum);
    assert(Any.of(Shade.light).get!Shade == Shade.light);
    assert(Any.of(300).holds!int && !Any.of(300).holds!ubyte);
    assert(Any.of(-1).holds!long && !Any.of(-1).holds!ulong);
    assert(Any.of(ulong.max).get!ulong == ulong.max && !Any.of(ulong.max).holds!long);
    assert(Any.of([1, 2, 3]).get!(int[]) == [1, 2, 3]);
    int[] none;
    assert(Any.of(none).isNull);
    assert(Any.of(42).toString == "42" && Any.of(true).toString == "true" && Any.of("s").toString == "s");

    bool threw;
    try
        Any.of(300).get!ubyte;
    catch (AnyTypeException e)
        threw = e.msg == "Any holds int, not ubyte";
    assert(threw);
    threw = false;
    try
        Any.of("x").get!int;
    catch (AnyTypeException)
        threw = true;
    assert(threw);
    threw = false;
    try
        Any.of(Colour.red).get!int;
    catch (AnyTypeException)
        threw = true;
    assert(threw, "an enum is not its base type");
}

unittest
{
    // References: dynamic casts to bases and interfaces, const views, null stays null.
    auto service = new OwnerService;
    const any = Any.of(service);
    assert(any.get!Base is service && any.get!Repository is service);
    assert(any.get!(const OwnerService) is service);
    assert(any.asObject is service && Any.of(1).asObject is null);
    OwnerService nothing;
    assert(Any.of(nothing).isNull && Any.of(nothing).get!Base is null);
    const named = Any.ofObject(service, typeNameOf!Repository);
    assert(named.typeName == typeNameOf!Repository && named.get!OwnerService is service);
    const frozen = any;
    assert(frozen.get!OwnerService is service);
    bool threw;
    try
        Any.of(new Base).get!OwnerService;
    catch (AnyTypeException)
        threw = true;
    assert(threw);
    assert(new Box!Pet(Pet("a", 1)) == new Box!Pet(Pet("a", 1)));
}

unittest
{
    // The runtime's own descriptors, looked up by name.
    auto table = DescriptorTable.withBuiltins();
    assert(table.find("int").kind == TypeKind.scalar && table.find("string").kind == TypeKind.string_);
    assert(table.find("petclinic.Owner") is null);
    table.add(descriptorOf!Pet);
    assert(table.find(typeNameOf!Pet).property("name") !is null);
}

// -------------------------------------------------------------------------------------------------------------
// A hand-written module in the shape Flint AOT generates (contract sections 3, 5 and 7).

private class Greeter
{
    string greet(string name)
    {
        return "Hello, " ~ name;
    }

    string twice(string name)
    {
        return greet(name) ~ " " ~ greet(name); // self-invocation: no advice
    }
}

private final class Greeter__FlintProxy : Greeter
{
    private Greeter __flintTarget;
    private AdviceChain __flintChain;
    private Descriptor __flintDescriptor;

    void __flintBind(Greeter target, AdviceChain chain, Descriptor descriptor) @safe
    {
        __flintTarget = target;
        __flintChain = chain;
        __flintDescriptor = descriptor;
    }

    override string greet(string name) @safe
    {
        Invocation invocation = Invocation(&__flintDescriptor.methods[0], __flintTarget, [
            Any.of(name)
        ]);
        __flintChain.invoke(invocation, (ref Invocation i) @safe {
            i.result = Any.of(__flintTarget.greet(name));
        });
        return invocation.result.get!string;
    }

    override string twice(string name) @safe
    {
        return __flintTarget.twice(name);
    }
}

private Descriptor greeterDescriptor() @safe
{
    auto d = new Descriptor(typeNameOf!Greeter, TypeKind.class_);
    d.methods = [
        MethodDescriptor("greet", "string", null, [MergedAnnotation("test.Shout", Any.init, 0)], 0)
    ];
    return d;
}

private final class Shout : Advisor
{
    int calls;

    bool appliesTo(const Descriptor, const(MethodDescriptor)* method)
    {
        return findAnnotation(method.annotations, "test.Shout") !is null;
    }

    int getOrder()
    {
        return 10;
    }

    void invoke(ref Invocation invocation, scope Proceed proceed)
    {
        calls++;
        proceed(invocation);
        invocation.result = Any.of(invocation.result.get!string ~ "!");
    }
}

private final class Log : Advisor
{
    string[] events;

    bool appliesTo(const Descriptor, const(MethodDescriptor)* method)
    {
        return true;
    }

    int getOrder()
    {
        return 1;
    }

    void invoke(ref Invocation invocation, scope Proceed proceed)
    {
        events ~= "before " ~ invocation.method.name;
        if (invocation.arguments[0].get!string == "nobody")
        {
            invocation.result = Any.of("short-circuited");
            return;
        }
        proceed(invocation);
        events ~= "after " ~ invocation.result.get!string;
    }
}

private final class Factory : BeanFactory
{
    Object[] advisors;

    Object getBean(string)
    {
        return null;
    }

    Object getBeanOfType(string, string = null)
    {
        return null;
    }

    Object findBeanOfType(string, string = null)
    {
        return null;
    }

    Object[] getBeansOfType(string type)
    {
        return type == typeNameOf!Advisor ? advisors : null;
    }

    Any resolveValue(string expression, string)
    {
        return Any.of(expression);
    }

    void bind(string, Any)
    {
    }

    Any bindConstructor(string, string)
    {
        return Any.init;
    }
}

private Object create_greeter(BeanFactory) @safe
{
    return new Greeter;
}

private Object proxy_greeter(Object target, BeanFactory factory) @safe
{
    auto descriptor = greeterDescriptor();
    auto proxy = cast(Greeter__FlintProxy) allocateProxy(typeid(Greeter__FlintProxy));
    proxy.__flintBind(cast(Greeter) target, adviceChain(factory, descriptor), descriptor);
    return proxy;
}

/// The entry point Flint AOT would generate for this module.
extern (C) void flint_aot_register_5flint6engine3aot16aot_runtime_test(scope AotRegistry registry) @safe
{
    registry.descriptor(greeterDescriptor());
    BeanDefinition greeter = {
        name: "greeter", type: typeNameOf!Greeter, types: [typeNameOf!Greeter], scope_: ScopeKind.singleton,
        source: "tests/aot_runtime.d:250", create: &create_greeter, proxy: &proxy_greeter
    };
    registry.bean(greeter);
}

private void populate(scope AotRegistry registry) @safe
{
    registry.begin(1, 1);
    flint_aot_register_5flint6engine3aot16aot_runtime_test(registry);
    registry.end();
}

private final class Recorder : AotRegistry
{
    string[] events;
    BeanDefinition[] beans;

    void begin(uint contractVersion, size_t) scope
    {
        checkContractVersion(contractVersion);
        events ~= "begin";
    }

    void bean(BeanDefinition definition) scope
    {
        beans ~= definition;
        events ~= "bean " ~ definition.name;
    }

    void descriptor(Descriptor descriptor) scope
    {
        events ~= "descriptor " ~ descriptor.simpleName;
    }

    void mapping(HandlerMapping) scope
    {
    }

    void exceptionHandler(ExceptionHandlerSpec) scope
    {
    }

    void listener(EventListenerSpec) scope
    {
    }

    void query(DerivedQuery) scope
    {
    }

    void application(string, string[]) scope
    {
    }

    void end() scope
    {
        events ~= "end";
    }
}

unittest
{
    // The registry installs from a module constructor in generated code; here, directly.
    assert(aotContractVersion == 3);
    checkContractVersion(1); // contracts 2 and 3 are additive: older generated code still runs
    checkContractVersion(2);
    installRegistry(&populate);
    assert(installedRegistry() is &populate);
    auto recorder = new Recorder;
    installedRegistry()(recorder);
    assert(recorder.events == ["begin", "descriptor Greeter", "bean greeter", "end"]);
    assert(recorder.beans[0].order == int.max && recorder.beans[0].condition is null);

    bool threw;
    try
        checkContractVersion(4);
    catch (AotContractException e)
        threw = e.msg == "generated code targets Flint AOT contract 4; this runtime implements contract 3. "
            ~ "Rebuild with flint build.";
    assert(threw);
}

unittest
{
    // Proxies: advisors ordered by getOrder, short-circuiting, and Spring's self-invocation semantics.
    auto factory = new Factory;
    auto shout = new Shout;
    auto log = new Log;
    factory.advisors = [shout, log];
    auto target = create_greeter(factory);
    auto proxy = cast(Greeter) proxy_greeter(target, factory);
    assert(proxy !is target && cast(Greeter__FlintProxy) proxy !is null);
    assert(proxy.greet("Ada") == "Hello, Ada!");
    assert(log.events == ["before greet", "after Hello, Ada!"], "Log (order 1) runs outside Shout (order 10)");
    assert(proxy.greet("nobody") == "short-circuited" && shout.calls == 1);
    // twice() is not advised: it forwards, and the target's own calls to greet() run no advice.
    assert(proxy.twice("Bo") == "Hello, Bo Hello, Bo" && shout.calls == 1);
}

unittest
{
    // invokeDetached runs inline without a DetachedExecutor bean.
    auto factory = new Factory;
    auto d = greeterDescriptor();
    auto chain = adviceChain(factory, d);
    string ran;
    chain.invokeDetached(Invocation(&d.methods[0], null, [Any.of("x")]), (ref Invocation i) @safe {
        ran = i.arguments[0].get!string;
    });
    assert(ran == "x");
}

unittest
{
    // Arrays of Any box @safe (web-mvc's error attributes): Box!(Any[]) hashes through Any.toHash.
    Any[] none;
    assert(Any.of(none).isNull && Any.of(none).holds!(Any[]));
    auto values = Any.of([Any.of(1), Any.of("two")]);
    assert(values.get!(Any[])[1].get!string == "two");
    assert(Any.of(1) == Any.of(1) && Any.of(1) != Any.of(2) && Any.of("a").toHash == Any.of("a").toHash);
}

unittest
{
    // Contract 2 builders: enums by ordinal, arrays, maps.
    auto colour = descriptorOf!Colour;
    assert(colour.enumValue(1).get!Colour == Colour.blue && colour.enumValue(9).isNull);
    auto ints = descriptorOf!(int[]);
    auto three = ints.fromElements([Any.of(1), Any.of(2), Any.of(3)]);
    assert(three.get!(int[]) == [1, 2, 3] && ints.length(three) == 3 && ints.element(three, 2).get!int == 3);
    auto aa = descriptorOf!(int[string]);
    auto map = aa.fromEntries([Any.of("a")], [Any.of(1)]);
    assert(map.get!(int[string])["a"] == 1 && aa.toKeys(map)[0].get!string == "a" && aa.toValues(map)[0].get!int == 1);
    assert(descriptorOf!Pet.length is null && descriptorOf!Pet.enumValue is null);
}

unittest
{
    // Contract 3: a method's compiled SpEL attributes, looked up by annotation and attribute.
    import flint.engine.aot.any : Any;
    import flint.engine.aot.descriptor : MethodDescriptor;
    import flint.engine.aot.expression : EvaluationContext, ExpressionSpec;

    static Any doubled(EvaluationContext context) @safe
    {
        return Any.of(context.argument(0).get!long * 2);
    }

    MethodDescriptor method = {
        name: "find", expressions: [
            ExpressionSpec("flint.cache.annotation.Cacheable", "key", "#id * 2", &doubled)
        ]
    };
    const key = method.expression("flint.cache.annotation.Cacheable", "key");
    assert(key !is null && key.source == "#id * 2");
    assert(method.expression("flint.cache.annotation.Cacheable", "condition") is null);
    assert(method.expression("flint.cache.annotation.CachePut", "key") is null);
}

unittest
{
    // Descriptor.simpleName: the last component, ignoring template arguments.
    import flint.engine.aot.descriptor : Descriptor, TypeKind;

    foreach (pair; [
            ["a.b.Owner", "Owner"], ["Owner", "Owner"], ["app.t.Opt!(a.B)", "Opt"],
            ["app.t.Opt!(Owner).Inner", "Opt"], ["flint.java.util.List!string", "List"]
        ])
    {
        auto d = new Descriptor(pair[0], TypeKind.class_);
        assert(d.simpleName() == pair[1], pair[0]);
    }
}

unittest
{
    // Breadth first: a @Component at distance 1 beats one at distance 2 reached through an earlier annotation.
    @Special("far") @Component("near") static final class Nearest
    {
    }

    // Declared @Component wins; through @Service at distance 1 it would be "far".
    assert(descriptorOf!Nearest.annotation(typeNameOf!Component).value.get!Component.value == "near");

    @Special("far") @Service("near") static final class NearestMeta
    {
    }

    // @Service declared (distance 0) beats @Special's @Service (distance 1); its @Component (distance 1) comes
    // from it, not from @Special's chain (distance 2).
    const component = descriptorOf!NearestMeta.annotation(typeNameOf!Component);
    assert(component.distance == 1 && component.value.get!Component.value == "near");
}

/// An interface and a base class carrying annotations, for the supertype aggregates (contract 3).
@Component("api")
private interface AnnotatedApi
{
}

@Service("base")
private class AnnotatedBase
{
}

private final class AnnotatedImpl : AnnotatedBase, AnnotatedApi
{
}

unittest
{
    import flint.engine.aot.descriptor : findAnnotation;

    // Aggregates in Spring's TYPE_HIERARCHY order: the class (0), its interfaces (1), then the superclass (2).
    auto impl = descriptorOf!AnnotatedImpl;
    assert(impl.annotation(typeNameOf!Component) is null); // aggregate 0 only
    const component = findAnnotation(impl.annotations, typeNameOf!Component);
    assert(component.aggregateIndex == 1 && component.distance == 0 && component.value.get!Component.value == "api");
    const service = findAnnotation(impl.annotations, typeNameOf!Service);
    assert(service.aggregateIndex == 2 && service.value.get!Service.value == "base");
}

/// `@AliasFor` naming both `attribute` and `value`: Spring's AnnotationConfigurationException.
private struct Misconfigured
{
    @AliasFor(attribute: "a", value: "b")
    string a;
}

unittest
{
    @Misconfigured static final class Bad
    {
    }

    @Mapping(value: "/a", path: "/b") static final class Conflicting
    {
    }

    const bad = descriptorOf!Bad.annotations[0].error;
    assert(bad.length && bad[0 .. 22] == "In @AliasFor declared ");
    const conflict = descriptorOf!Conflicting.annotations[0].error;
    assert(conflict.length && conflict[0 .. 37] == "Different @AliasFor mirror values for", conflict);
    assert(descriptorOf!OwnerService.annotations[0].error is null);
}

unittest
{
    import flint.engine.aot.mapping : ArgumentSpec, HandlerMapping;

    // Contract 3: generated code fills the descriptor fields one by one.
    ArgumentSpec argument;
    argument.descriptor = descriptorOf!OwnerService;
    HandlerMapping mapping;
    mapping.returnDescriptor = descriptorOf!OwnerService;
    assert(argument.descriptor.name == mapping.returnDescriptor.name);
}

unittest
{
    import flint.engine.aot.any : Any;
    import flint.engine.aot.mapping : ExceptionHandlerSpec, HandlerArrayInvoker, HandlerMapping;

    // Contract 4: the array invoker reads converted arguments straight from caller storage.
    static void invoke(Object, scope Any[] arguments, ref Any result) @safe
    {
        result = Any.of(arguments[0].get!long + arguments[1].get!long);
    }

    HandlerMapping mapping;
    assert(mapping.invokeArguments is null);
    mapping.invokeArguments = &invoke;
    Any[2] arguments = [Any.of(40L), Any.of(2L)];
    Any result;
    mapping.invokeArguments(null, arguments[], result);
    assert(result.get!long == 42);
    const ExceptionHandlerSpec spec;
    assert(spec.invokeArguments is null);
}

/// gs-rest-service's `Greeting`: a 24-byte record with a string, the shape of a typical handler result.
private struct InlineGreeting
{
    long id;
    string content;
}

/// Larger than `Any`'s 32 bytes of value storage: still boxed.
private struct LargeRecord
{
    long[5] values;
}

private struct InlineTwin
{
    long id;
    string content;
}

private struct LargeTwin
{
    long[5] values;
}

unittest
{
    import flint.engine.aot.any : Any;

    // An inline struct: no Box, the value and its type name round-trip, and get returns a reference into the Any.
    static assert(Any.sizeof == 56, "Any keeps its size");
    auto any = Any.of(InlineGreeting(1, "Hello, World!"));
    assert(any.holds!InlineGreeting && !any.isNull && any.box!InlineGreeting is null);
    assert(any.get!InlineGreeting == InlineGreeting(1, "Hello, World!"));
    any.get!InlineGreeting.id = 2;
    assert(any.get!InlineGreeting.id == 2);
    // A copy holds its own value; equal values are equal Anys, with equal hashes.
    auto copy = any;
    copy.get!InlineGreeting.id = 3;
    assert(any.get!InlineGreeting.id == 2 && copy.get!InlineGreeting.id == 3);
    assert(Any.of(InlineGreeting(2, "Hello, World!")) == any && any != copy);
    assert(Any.of(InlineGreeting(2, "Hello, World!")).toHash() == any.toHash());
    // Negative: another type does not match; a large struct is boxed and shares its box between copies.
    assert(!any.holds!LargeRecord && !Any.of(LargeRecord.init).holds!InlineGreeting);
    auto large = Any.of(LargeRecord.init);
    assert(large.box!LargeRecord !is null);
    auto shared_ = large;
    shared_.get!LargeRecord.values[0] = 9;
    assert(large.get!LargeRecord.values[0] == 9);
}

unittest
{
    import flint.engine.aot.any : Any;

    // Descriptor accessors read and write an inline struct in place.
    auto descriptor = descriptorOf!InlineGreeting;
    auto any = Any.of(InlineGreeting(1, "a"));
    assert(descriptor.property("content").get(any).get!string == "a");
    descriptor.property("id").set(any, Any.of(5L));
    assert(any.get!InlineGreeting.id == 5);
    auto created = descriptor.create();
    descriptor.property("content").set(created, Any.of("made"));
    assert(created.get!InlineGreeting.content == "made");
}

unittest
{
    import flint.engine.aot.any : Any;

    // structPointer: one type check for an inline or a boxed struct, null for another type or no value.
    auto inline = Any.of(InlineGreeting(1, "a"));
    assert(inline.structPointer!InlineGreeting !is null && inline.structPointer!InlineGreeting.content == "a");
    inline.structPointer!InlineGreeting.id = 9;
    assert(inline.get!InlineGreeting.id == 9);
    const large = Any.of(LargeRecord.init);
    assert(large.structPointer!LargeRecord !is null && large.structPointer!InlineGreeting is null);
    assert(inline.structPointer!LargeRecord is null && Any.init.structPointer!InlineGreeting is null);
}

unittest
{
    import core.memory : GC;
    import flint.engine.aot.any : Any;

    // Wrong type: a struct with InlineGreeting's exact layout, another boxed struct, and scalar or text values.
    static assert(InlineTwin.sizeof == InlineGreeting.sizeof);
    const twin = Any.of(InlineTwin(1, "a"));
    assert(twin.structPointer!InlineTwin !is null && twin.structPointer!InlineGreeting is null);
    const boxed = Any.of(LargeRecord.init);
    assert(boxed.structPointer!LargeTwin is null && Any.of(LargeTwin.init).structPointer!LargeRecord is null);
    assert(Any.of(5L).structPointer!InlineGreeting is null && Any.of("a").structPointer!InlineGreeting is null);

    // Copies: an inline pointer reaches only its own Any; a boxed pointer reaches the box every copy shares.
    auto original = Any.of(InlineGreeting(1, "a"));
    auto copy = original;
    copy.structPointer!InlineGreeting.id = 2;
    original.structPointer!InlineGreeting.content = "b";
    assert(original.get!InlineGreeting == InlineGreeting(1, "b") && copy.get!InlineGreeting == InlineGreeting(2, "a"));
    auto large = Any.of(LargeRecord.init);
    const sharing = large;
    large.structPointer!LargeRecord.values[0] = 7;
    assert(sharing.get!LargeRecord.values[0] == 7);

    // Lifetime: a boxed pointer keeps its box alive after the Any lets go of it.
    auto kept = large.structPointer!LargeRecord;
    large = Any.init;
    GC.collect();
    assert(kept.values[0] == 7);
}

unittest
{
    import flint.engine.aot.any : Any;

    // Negative (DIP1000): a pointer into a local Any cannot outlive it, inline or boxed.
    static assert(!__traits(compiles, () @safe {
            auto local = Any.of(InlineGreeting(1, "a"));
            return local.structPointer!InlineGreeting;
        }));
    static assert(!__traits(compiles, () @safe {
            InlineGreeting* outer;
            {
                auto local = Any.of(InlineGreeting(1, "a"));
                outer = local.structPointer!InlineGreeting;
            }
            return outer;
        }));
    // Positive: the same calls compile while the pointer stays in scope.
    static assert(__traits(compiles, () @safe {
            auto local = Any.of(InlineGreeting(1, "a"));
            return local.structPointer!InlineGreeting.id;
        }));
}
