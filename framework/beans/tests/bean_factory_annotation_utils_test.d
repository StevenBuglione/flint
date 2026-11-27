// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/context/annotation/configuration/BeanMethodQualificationTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.beans.bean_factory_annotation_utils_test;

import flint.beans.factory : BeanFactory, NoSuchBeanDefinitionException, NoUniqueBeanDefinitionException;
import flint.beans.factory.annotation : Qualifier;
import flint.beans.factory.annotation_runtime : BeanFactoryAnnotationUtils;
import flint.beans.factory.support : DefaultListableBeanFactory, RootBeanDefinition;
import flint.engine.aot.any : Any;
import flint.engine.aot.bean : BeanDefinition;
import flint.engine.aot.descriptor : MergedAnnotation;
import flint.engine.aot.name : typeNameOf;
import std.exception : collectException;

@safe:

private final class TestBean
{
    string name;

    this(string name)
    {
        this.name = name;
    }
}

private RootBeanDefinition register(DefaultListableBeanFactory factory, string name, string[] qualifiers = null)
{
    BeanDefinition record;
    record.name = name;
    record.type = typeNameOf!TestBean;
    record.types = [record.type];
    record.qualifiers = qualifiers;
    auto definition = new RootBeanDefinition(record);
    definition.setInstanceSupplier(() => new TestBean(name));
    definition.setLazyInit(true);
    factory.registerBeanDefinition(name, definition);
    return definition;
}

@("customWithLazyResolution looks up the qualified bean without instantiating other candidates")
unittest
{
    auto factory = new DefaultListableBeanFactory();
    register(factory, "testBean1", ["interesting"]);
    register(factory, "testBean2", ["boring"]);
    assert(!factory.containsSingleton("testBean1") && !factory.containsSingleton("testBean2"));

    auto boring = BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "boring");
    assert(boring.name == "testBean2");
    assert(!factory.containsSingleton("testBean1"));
    assert(boring is BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "boring"));
}

@("qualifiers can come from merged class metadata as well as the generated bean record")
unittest
{
    auto factory = new DefaultListableBeanFactory();
    auto definition = register(factory, "metadataBean");
    auto annotations = [MergedAnnotation(typeNameOf!Qualifier, Any.of(Qualifier("route")), 1)];
    definition.setAttribute("flint.annotations", Any.of(annotations));
    auto bean = BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "route");
    assert(bean.name == "metadataBean");
}

@("an unmatched definition qualifier falls through to the class metadata")
unittest
{
    auto factory = new DefaultListableBeanFactory();
    auto definition = register(factory, "metadataBean", ["factoryRoute"]);
    auto annotations = [MergedAnnotation(typeNameOf!Qualifier, Any.of(Qualifier("classRoute")))];
    definition.setAttribute("flint.annotations", Any.of(annotations));
    auto selected = BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "factoryRoute");
    assert(selected.name == "metadataBean");
    assert(BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "classRoute") is selected);
}

@("bean names and aliases qualify typed candidates and a wrong type is absent")
unittest
{
    auto factory = new DefaultListableBeanFactory();
    auto existing = new TestBean("direct");
    factory.registerSingleton("direct", existing);
    factory.registerAlias("direct", "alias");
    factory.registerSingleton("wrong", new Object());

    assert(BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "direct") is existing);
    assert(BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "alias") is existing);
    auto missing = collectException!NoSuchBeanDefinitionException(
            BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "wrong"));
    assert(missing !is null && missing.getBeanName() == "wrong" && missing.getNumberOfBeansFound() == 0);
    enum expected = "No bean named 'wrong' available: No matching TestBean bean found for qualifier 'wrong' "
        ~ "- neither qualifier match nor bean name match!";
    assert(missing.getMessage() == expected);
}

private final class NameOnlyBeanFactory : BeanFactory
{
    private BeanFactory factory;

    this(BeanFactory factory)
    {
        this.factory = factory;
    }

    override Object getBeanErased(string name, string requiredType, Any[] args)
    {
        return factory.getBeanErased(name, requiredType, args);
    }

    override bool containsBean(string name)
    {
        return factory.containsBean(name);
    }

    override bool isSingleton(string name)
    {
        return factory.isSingleton(name);
    }

    override bool isPrototype(string name)
    {
        return factory.isPrototype(name);
    }

    override bool isTypeMatchErased(string name, string typeName)
    {
        return factory.isTypeMatchErased(name, typeName);
    }

    override string getTypeName(string name)
    {
        return factory.getTypeName(name);
    }

    override string[] getAliases(string name)
    {
        return factory.getAliases(name);
    }
}

@("non-listable factories use the typed name fallback and its own error text")
unittest
{
    auto backing = new DefaultListableBeanFactory();
    auto existing = new TestBean("direct");
    backing.registerSingleton("direct", existing);
    backing.registerAlias("direct", "alias");
    backing.registerSingleton("wrong", new Object());
    auto factory = new NameOnlyBeanFactory(backing);

    assert(BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "alias") is existing);
    auto missing = collectException!NoSuchBeanDefinitionException(
            BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "wrong"));
    assert(missing !is null && missing.getBeanName() == "wrong");
    enum expected = "No bean named 'wrong' available: No matching TestBean bean found for bean name 'wrong'! "
        ~ "(Note: Qualifier matching not supported because given BeanFactory does not implement "
        ~ "ConfigurableListableBeanFactory.)";
    assert(missing.getMessage() == expected);
}

@("qualified lookup requires a unique bean even if the first match is primary")
unittest
{
    auto factory = new DefaultListableBeanFactory();
    register(factory, "first", ["shared"]).setPrimary(true);
    register(factory, "second", ["shared"]);

    auto duplicate = collectException!NoUniqueBeanDefinitionException(
            BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(factory, "shared"));
    assert(duplicate !is null && duplicate.getNumberOfBeansFound() == 2);
    assert(!factory.containsSingleton("first") && !factory.containsSingleton("second"));
}

@("ancestor qualifiers resolve until a local bean shadows their names")
unittest
{
    auto parent = new DefaultListableBeanFactory();
    register(parent, "parentBean", ["inherited"]);
    auto child = new DefaultListableBeanFactory(parent);
    assert(BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(child, "inherited").name == "parentBean");

    child.registerSingleton("parentBean", new Object());
    auto missing = collectException!NoSuchBeanDefinitionException(
            BeanFactoryAnnotationUtils.qualifiedBeanOfType!TestBean(child, "inherited"));
    assert(missing !is null && missing.getNumberOfBeansFound() == 0);
}

// Flint addition: Java's annotation default for @Qualifier's value is "", which is not null under `is`.
@("Qualifier's default value is the empty string, not null")
unittest
{
    assert(Qualifier.init.value !is null && Qualifier.init.value.length == 0);
}
