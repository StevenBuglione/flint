module flint.bean_definition_exception_test;

import flint.beans.factory : BeanDefinitionStoreException;
import flint.beans.factory.support : BeanDefinitionOverrideException, DefaultListableBeanFactory, RootBeanDefinition;
import flint.engine.aot.bean : AotBeanDefinition = BeanDefinition;
import flint.java.lang : IllegalArgumentException;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

@("store exceptions preserve resource-only messages and nullable descriptions")
unittest
{
    auto plain = new BeanDefinitionStoreException("Invalid definition", null);
    assert(plain.getMessage() == "Invalid definition" && plain.getCause() is null);
    assert(plain.getBeanName() is null && plain.getResourceDescription().isNull);

    auto resourceOnly = new BeanDefinitionStoreException(Nullable!string("beans.xml"), "Resource is invalid");
    assert(resourceOnly.getMessage() == "Resource is invalid" && resourceOnly.getBeanName() is null);
    assert(resourceOnly.getResourceDescription().get() == "beans.xml");

    auto cause = new IllegalArgumentException("Invalid key");
    auto empty = new BeanDefinitionStoreException(Nullable!string(""), "Cannot read", cause);
    assert(!empty.getResourceDescription().isNull && empty.getResourceDescription().get() == "");
    assert(empty.getMessage() == "Cannot read" && empty.getCause() is cause);
}

@("named store exceptions format absent and empty details differently")
unittest
{
    auto absent = new BeanDefinitionStoreException(null, "bean", null);
    assert(absent.getBeanName() == "bean" && absent.getResourceDescription().isNull);
    assert(absent.getMessage() == "Invalid bean definition with name 'bean' defined in null");

    auto empty = new BeanDefinitionStoreException(Nullable!string(""), "bean", Nullable!string(""));
    assert(!empty.getResourceDescription().isNull && empty.getResourceDescription().get() == "");
    assert(empty.getMessage() == "Invalid bean definition with name 'bean' defined in : ");

    auto named = new BeanDefinitionStoreException("beans.xml", "bean", "Invalid name");
    assert(named.getResourceDescription().get() == "beans.xml");
    assert(named.getMessage() == "Invalid bean definition with name 'bean' defined in beans.xml: Invalid name");
}

private RootBeanDefinition definition(string source = null)
{
    AotBeanDefinition record;
    record.type = "string";
    record.source = source;
    return new RootBeanDefinition(record);
}

@("a rejected bean registration retains the incoming resource and both definitions")
unittest
{
    auto factory = new DefaultListableBeanFactory;
    factory.setAllowBeanDefinitionOverriding(false);
    auto existing = definition("original.xml");
    auto incoming = definition("incoming.xml");
    factory.registerBeanDefinition("bean", existing);

    auto error = collectException!BeanDefinitionOverrideException(factory.registerBeanDefinition("bean", incoming));
    assert(error !is null && error.getResourceDescription().get() == "incoming.xml");
    assert(error.getBeanName() == "bean" && error.getBeanDefinition() is incoming);
    assert(error.getExistingDefinition() is existing);
}

@("bean override exceptions accept explicit details and use Java's null rendering")
unittest
{
    auto incoming = definition();
    auto existing = definition("other.xml");
    BeanDefinitionStoreException error = new BeanDefinitionOverrideException(null, incoming, existing, "Rejected");
    assert(error.getBeanName() == "null" && error.getResourceDescription().get() == "null");
    assert(error.getMessage() == "Invalid bean definition with name 'null' defined in null: Rejected");
}
