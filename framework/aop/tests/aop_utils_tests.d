module aop_utils_tests;

import flint.aop.support : AopUtils;
import flint.engine.aot.descriptor : MethodDescriptor, ParameterDescriptor;
import flint.engine.aot.name : typeNameOf;

@safe:

@("AopUtils identifies equals only with the Object parameter") unittest
{
    auto method = MethodDescriptor("equals", "bool");
    assert(!AopUtils.isEqualsMethod(null));
    assert(!AopUtils.isEqualsMethod(&method));

    method.parameters = [ParameterDescriptor("other", typeNameOf!string)];
    assert(!AopUtils.isEqualsMethod(&method));

    method.parameters[0].type = typeNameOf!Object;
    assert(AopUtils.isEqualsMethod(&method));

    method.parameters ~= ParameterDescriptor("extra", typeNameOf!Object);
    assert(!AopUtils.isEqualsMethod(&method));
}

@("AopUtils identifies no-argument Object methods by name and arity") unittest
{
    auto method = MethodDescriptor("hashCode", "int");
    assert(AopUtils.isHashCodeMethod(&method));
    assert(!AopUtils.isToStringMethod(&method));
    assert(!AopUtils.isFinalizeMethod(&method));

    method.name = "toString";
    assert(AopUtils.isToStringMethod(&method));
    assert(!AopUtils.isHashCodeMethod(&method));

    method.name = "finalize";
    assert(AopUtils.isFinalizeMethod(&method));

    method.parameters = [ParameterDescriptor("extra", "int")];
    assert(!AopUtils.isFinalizeMethod(&method));
    method.name = "hashCode";
    assert(!AopUtils.isHashCodeMethod(&method));
    method.name = "toString";
    assert(!AopUtils.isToStringMethod(&method));

    assert(!AopUtils.isHashCodeMethod(null));
    assert(!AopUtils.isToStringMethod(null));
    assert(!AopUtils.isFinalizeMethod(null));
}
