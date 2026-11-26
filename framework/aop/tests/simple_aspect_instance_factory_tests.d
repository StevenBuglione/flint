module simple_aspect_instance_factory_tests;

import std.exception : assertThrown, collectException;

import flint.aop.aspectj : AspectInstanceFactory, SimpleAspectInstanceFactory;
import flint.aop.framework : AopConfigException;
import flint.core : Ordered;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, TypeKind, descriptorOf;
import flint.java.lang : IllegalArgumentException;

@safe:

private final class AspectFixture : Ordered
{
    int getOrder()
    {
        return 1;
    }
}

private final class ConfiguredAspectFactory : SimpleAspectInstanceFactory
{
    this(const Descriptor aspectClass)
    {
        super(aspectClass);
    }

    protected override int getOrderForAspectClass(const Descriptor aspectClass)
    {
        assert(aspectClass is getAspectClass());
        return 8;
    }
}

private Any failConstruction()
{
    throw new IllegalArgumentException("aspect constructor failed");
}

@("Simple aspect factories construct fresh instances and use the class order hook") unittest
{
    auto aspectType = descriptorOf!AspectFixture();
    auto simple = new SimpleAspectInstanceFactory(aspectType);
    AspectInstanceFactory factory = simple;
    const first = factory.getAspectInstance().get!AspectFixture();
    const second = factory.getAspectInstance().get!AspectFixture();

    assert(simple.getAspectClass() is aspectType);
    assert(first !is second);
    assert(factory.getOrder() == Ordered.LOWEST_PRECEDENCE);

    factory = new ConfiguredAspectFactory(aspectType);
    assert(factory.getOrder() == 8);
}

@("Simple aspect factories report missing constructors and preserve invocation causes") unittest
{
    assertThrown!IllegalArgumentException(new SimpleAspectInstanceFactory(null));

    auto aspectType = new Descriptor("fixtures.FailingAspect", TypeKind.class_);
    auto factory = new SimpleAspectInstanceFactory(aspectType);
    auto missing = collectException!AopConfigException(factory.getAspectInstance());
    assert(missing !is null);
    assert(missing.getMessage() == "No default constructor on aspect class: fixtures.FailingAspect");

    aspectType.create = &failConstruction;
    assert(factory.getOrder() == Ordered.LOWEST_PRECEDENCE);
    auto failed = collectException!AopConfigException(factory.getAspectInstance());
    assert(failed !is null);
    assert(failed.getMessage() == "Failed to invoke aspect constructor: fixtures.FailingAspect");
    auto cause = cast(IllegalArgumentException) failed.getCause();
    assert(cause !is null && cause.getMessage() == "aspect constructor failed");
}
