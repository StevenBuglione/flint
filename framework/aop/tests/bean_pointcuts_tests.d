/*
 * Ported from spring-projects/spring-framework v7.1.0, spring-aop/src/test/java/org/springframework/aop/support/PointcutsTests.java
 * Copyright 2002-present the original author or authors.
 * Licensed under the Apache License, Version 2.0.
 * Modified by the Flint authors.
 */
module bean_pointcuts_tests;

import flint.aop : ClassFilter, Pointcut;
import flint.aop.support : ComposablePointcut, NameMatchMethodPointcut, Pointcuts, RootClassFilter;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, ParameterDescriptor, TypeKind;
import flint.engine.aot.objects : objectToString;

@safe:

private struct BeanMethods
{
    const(MethodDescriptor)* setAge;
    const(MethodDescriptor)* getAge;
    const(MethodDescriptor)* getName;
    const(MethodDescriptor)* other;

    static BeanMethods describe()
    {
        auto setter = new MethodDescriptor("setAge", "void");
        setter.parameters = [ParameterDescriptor("age", "int")];
        return BeanMethods(setter, new MethodDescriptor("getAge", "int"),
                new MethodDescriptor("getName", "string"), new MethodDescriptor("absquatulate", "void"));
    }
}

private Descriptor bean(string name, string[] supertypes = null)
{
    auto type = new Descriptor(name, TypeKind.class_);
    type.supertypes = supertypes;
    return type;
}

private Pointcut named(string name)
{
    return new NameMatchMethodPointcut().addMethodName(name);
}

@("PointcutsTests.matches") unittest
{
    auto methods = BeanMethods.describe();
    auto target = bean("TestBean");

    assert(Pointcuts.matches(Pointcuts.SETTERS, methods.setAge, target, [Any.of(6)]));
    assert(!Pointcuts.matches(Pointcuts.SETTERS, methods.getAge, target));
    assert(!Pointcuts.matches(Pointcuts.SETTERS, methods.other, target));
    assert(!Pointcuts.matches(Pointcuts.GETTERS, methods.setAge, target));
    assert(Pointcuts.matches(Pointcuts.GETTERS, methods.getAge, target));
    assert(!Pointcuts.matches(Pointcuts.GETTERS, methods.other, target));
}

@("PointcutsTests.unionOfSettersAndGetters") unittest
{
    auto methods = BeanMethods.describe();
    auto either = Pointcuts.union_(Pointcuts.GETTERS, Pointcuts.SETTERS);
    auto target = bean("TestBean");
    assert(Pointcuts.matches(either, methods.setAge, target, [Any.of(6)]));
    assert(Pointcuts.matches(either, methods.getAge, target));
    assert(!Pointcuts.matches(either, methods.other, target));
}

@("PointcutsTests.unionOfSpecificGetters") unittest
{
    auto methods = BeanMethods.describe();
    auto target = bean("TestBean");
    auto age = named("getAge");
    auto either = Pointcuts.union_(age, named("getName"));
    assert(!Pointcuts.matches(either, methods.setAge, target));
    assert(Pointcuts.matches(either, methods.getAge, target));
    assert(!Pointcuts.matches(age, methods.getName, target));
    assert(Pointcuts.matches(either, methods.getName, target));
    assert(!Pointcuts.matches(either, methods.other, target));

    either = Pointcuts.union_(either, Pointcuts.SETTERS);
    assert(Pointcuts.matches(either, methods.setAge, target, [Any.of(6)]));
    assert(Pointcuts.matches(either, methods.getAge, target));
    assert(!Pointcuts.matches(age, methods.getName, target));
    assert(Pointcuts.matches(either, methods.getName, target));
    assert(!Pointcuts.matches(either, methods.other, target));
}

@("PointcutsTests.unionOfAllSettersAndSubclassSetters") unittest
{
    auto methods = BeanMethods.describe();
    auto parent = bean("TestBean");
    auto child = bean("MyTestBean", [parent.name]);
    Pointcut childSetters = new ComposablePointcut(new RootClassFilter(child), Pointcuts.SETTERS.getMethodMatcher());

    assert(!Pointcuts.matches(childSetters, methods.setAge, parent));
    assert(Pointcuts.matches(childSetters, methods.setAge, child));
    assert(!Pointcuts.matches(childSetters, methods.getAge, child));

    auto either = Pointcuts.union_(childSetters, Pointcuts.GETTERS);
    assert(Pointcuts.matches(either, methods.getAge, parent));
    assert(Pointcuts.matches(either, methods.getAge, child));
    assert(Pointcuts.matches(either, methods.setAge, child));
    assert(!Pointcuts.matches(either, methods.setAge, parent));
}

@("PointcutsTests.intersectionOfSpecificGettersAndSubclassGetters") unittest
{
    auto methods = BeanMethods.describe();
    auto parent = bean("TestBean");
    auto child = bean("MyTestBean", [parent.name]);
    auto grandchild = bean("MyTestBeanSubclass", [child.name, parent.name]);
    auto age = named("getAge");
    auto getters = Pointcuts.GETTERS.getMethodMatcher();
    Pointcut childGetters = new ComposablePointcut(new RootClassFilter(child), getters);

    assert(Pointcuts.matches(age, methods.getAge, parent));
    assert(Pointcuts.matches(age, methods.getAge, child));
    assert(!Pointcuts.matches(childGetters, methods.getName, parent));
    assert(!Pointcuts.matches(childGetters, methods.getAge, parent));
    assert(Pointcuts.matches(childGetters, methods.getName, child));
    assert(Pointcuts.matches(childGetters, methods.getAge, child));

    auto both = Pointcuts.intersection(age, childGetters);
    assert(!Pointcuts.matches(both, methods.getName, parent));
    assert(!Pointcuts.matches(both, methods.getAge, parent));
    assert(!Pointcuts.matches(both, methods.getName, child));
    assert(Pointcuts.matches(both, methods.getAge, child));
    assert(!Pointcuts.matches(both, methods.getName, grandchild));
    assert(Pointcuts.matches(both, methods.getAge, grandchild));

    Pointcut grandchildGetters = new ComposablePointcut(new RootClassFilter(grandchild), getters);
    both = Pointcuts.intersection(both, grandchildGetters);
    assert(!Pointcuts.matches(both, methods.getName, parent));
    assert(!Pointcuts.matches(both, methods.getAge, parent));
    assert(!Pointcuts.matches(both, methods.getName, child));
    assert(!Pointcuts.matches(both, methods.getAge, child));
    assert(!Pointcuts.matches(both, methods.getName, grandchild));
    assert(Pointcuts.matches(both, methods.getAge, grandchild));

    Pointcut parentMethods = new ComposablePointcut((const Descriptor type) => type is parent);
    auto either = Pointcuts.union_(both, parentMethods);
    assert(Pointcuts.matches(either, methods.getName, parent));
    assert(Pointcuts.matches(either, methods.getAge, parent));
    assert(!Pointcuts.matches(either, methods.getName, child));
    assert(!Pointcuts.matches(either, methods.getAge, child));
    assert(!Pointcuts.matches(either, methods.getName, grandchild));
    assert(Pointcuts.matches(either, methods.getAge, grandchild));
    assert(Pointcuts.matches(either, methods.other, parent));
    assert(!Pointcuts.matches(either, methods.other, child));
}

@("PointcutsTests.simpleIntersection") unittest
{
    auto methods = BeanMethods.describe();
    auto target = bean("TestBean");
    auto both = Pointcuts.intersection(Pointcuts.GETTERS, Pointcuts.SETTERS);
    assert(!Pointcuts.matches(both, methods.setAge, target));
    assert(!Pointcuts.matches(both, methods.getAge, target));
    assert(!Pointcuts.matches(both, methods.other, target));
}

@("Bean accessor points are shared and require Spring's name, arity and return type") unittest
{
    auto target = bean("TestBean");
    auto getters = Pointcuts.GETTERS;
    auto setters = Pointcuts.SETTERS;
    assert(getters is Pointcuts.GETTERS && setters is Pointcuts.SETTERS);
    assert(getters.getClassFilter() is ClassFilter.TRUE && setters.getClassFilter() is ClassFilter.TRUE);
    assert(!getters.getMethodMatcher().isRuntime() && !setters.getMethodMatcher().isRuntime());
    assert(objectToString(cast(Object) getters) == "Pointcuts.GETTERS");
    assert(objectToString(cast(Object) setters) == "Pointcuts.SETTERS");

    auto wrongGetter = new MethodDescriptor("getAge", "void");
    assert(!Pointcuts.matches(getters, wrongGetter, target));
    wrongGetter.returnType = "int";
    wrongGetter.parameters = [ParameterDescriptor("key", "string")];
    assert(!Pointcuts.matches(getters, wrongGetter, target));
    assert(!Pointcuts.matches(getters, new MethodDescriptor("isReady", "bool"), target));
    auto wrongSetter = new MethodDescriptor("setAge", "void");
    assert(!Pointcuts.matches(setters, wrongSetter, target));
    wrongSetter.parameters = [
        ParameterDescriptor("age", "int"), ParameterDescriptor("unit", "string")
    ];
    assert(!Pointcuts.matches(setters, wrongSetter, target));
    wrongSetter.parameters = wrongSetter.parameters[0 .. 1];
    wrongSetter.returnType = "int";
    assert(!Pointcuts.matches(setters, wrongSetter, target));
}
