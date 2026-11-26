// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans/factory/annotation/BeanFactoryAnnotationUtils.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.beans.factory.annotation_runtime;

import flint.beans.factory : BeanFactory, HierarchicalBeanFactory, ListableBeanFactory,
    NoSuchBeanDefinitionException, NoUniqueBeanDefinitionException;
import flint.beans.factory.annotation : Qualifier;
import flint.beans.factory.support : DefaultListableBeanFactory;
import flint.engine.aot.name : simpleTypeName, typeNameOf;
import flint.util : Assert;

@safe:

/// Look up beans using their generated qualifier metadata (R22).
abstract class BeanFactoryAnnotationUtils
{
    /// Find the unique bean of type `T` matching a qualifier, name or alias (R4).
    static T qualifiedBeanOfType(T)(BeanFactory beanFactory, string qualifier)
    {
        return cast(T) qualifiedBean(beanFactory, typeNameOf!T, qualifier);
    }

    private static Object qualifiedBean(BeanFactory beanFactory, string type, string qualifier)
    {
        Assert.notNull(beanFactory, "BeanFactory must not be null");
        string match;
        auto root = cast(ListableBeanFactory) beanFactory;
        for (auto owner = root; owner !is null; owner = listableParent(owner))
        {
            foreach (name; owner.getBeanNamesForTypeErased(type))
            {
                if (shadowed(root, owner, name) || !matchesQualifier(owner, name, qualifier))
                    continue;
                if (match !is null)
                    throw new NoUniqueBeanDefinitionException(type, [match, name]);
                match = name;
            }
        }
        if (match !is null)
            return beanFactory.getBeanErased(match, type, null);
        if (beanFactory.containsBean(qualifier) && beanFactory.isTypeMatchErased(qualifier, type))
            return beanFactory.getBeanErased(qualifier, type, null);
        const prefix = "No matching " ~ simpleTypeName(type) ~ " bean found for ";
        if (root is null)
            throw new NoSuchBeanDefinitionException(qualifier, prefix ~ "bean name '" ~ qualifier
                    ~ "'! (Note: Qualifier matching not supported because given BeanFactory does not implement "
                    ~ "ConfigurableListableBeanFactory.)");
        throw new NoSuchBeanDefinitionException(qualifier,
                prefix ~ "qualifier '" ~ qualifier ~ "' - neither qualifier match nor bean name match!");
    }

    private static ListableBeanFactory listableParent(ListableBeanFactory factory)
    {
        auto hierarchy = cast(HierarchicalBeanFactory) factory;
        return hierarchy is null ? null : cast(ListableBeanFactory) hierarchy.getParentBeanFactory();
    }

    private static bool shadowed(ListableBeanFactory root, ListableBeanFactory owner, string name)
    {
        for (auto child = root; child !is null && child !is owner; child = listableParent(child))
            if (auto hierarchy = cast(HierarchicalBeanFactory) child)
                if (hierarchy.containsLocalBean(name))
                    return true;
        return false;
    }

    private static bool matchesQualifier(BeanFactory factory, string name, string qualifier)
    {
        if (name == qualifier)
            return true;
        foreach (alias_; factory.getAliases(name))
            if (alias_ == qualifier)
                return true;
        auto listable = cast(DefaultListableBeanFactory) factory;
        if (listable is null || !listable.containsBeanDefinition(name))
            return false;
        foreach (value; listable.getBeanDefinition(name).getQualifiers())
            if (value == qualifier)
                return true;
        auto annotation = listable.findAnnotationOnBean(name, typeNameOf!Qualifier);
        return annotation !is null && annotation.value.get!Qualifier().value == qualifier;
    }
}
