// SPDX-License-Identifier: Apache-2.0
module unsatisfied_dependency_exception_test;

import std.typecons : Nullable;

import flint.beans : BeansException, FatalBeanException;
import flint.beans.factory : UnsatisfiedDependencyException;
import flint.java.lang : NullPointerException;

@safe:

unittest
{
    const prefix = "Error creating bean with name 'service' defined in beans.xml: "
        ~ "Unsatisfied dependency expressed through bean property 'dependency'";
    const resource = Nullable!string("beans.xml");
    const name = Nullable!string("service");

    auto message = new UnsatisfiedDependencyException(resource, name, "dependency", Nullable!string("missing"));
    assert(message.msg == prefix ~ ": missing");
    assert(message.getBeanName() == "service");
    assert(message.getResourceDescription() == "beans.xml");

    auto cause = new FatalBeanException("missing");
    auto wrapped = new UnsatisfiedDependencyException(resource, name, "dependency", cause);
    assert(wrapped.msg == message.msg);
    assert(wrapped.getRootCause() is cause);

    auto missingMessage = new UnsatisfiedDependencyException(resource, name, "dependency", Nullable!string.init);
    auto emptyMessage = new UnsatisfiedDependencyException(resource, name, "dependency", Nullable!string(""));
    assert(missingMessage.msg == prefix);
    assert(emptyMessage.msg == prefix);

    auto noResourceOrName = new UnsatisfiedDependencyException(Nullable!string.init,
            Nullable!string.init, "dependency", Nullable!string.init);
    assert(noResourceOrName.msg == "Error creating bean with name 'null': "
            ~ "Unsatisfied dependency expressed through bean property 'dependency'");
    assert(noResourceOrName.getBeanName() is null);
    assert(noResourceOrName.getResourceDescription() is null);

    auto emptyResourceAndName = new UnsatisfiedDependencyException(Nullable!string(""),
            Nullable!string(""), "dependency", Nullable!string.init);
    assert(emptyResourceAndName.msg == "Error creating bean with name '' defined in : "
            ~ "Unsatisfied dependency expressed through bean property 'dependency'");

    try
    {
        new UnsatisfiedDependencyException(resource, name, "dependency", cast(BeansException) null);
        assert(0, "a null cause should fail");
    }
    catch (NullPointerException)
    {
    }

    auto legacy = new UnsatisfiedDependencyException("beans.xml", "service", "dependency", null);
    assert(legacy.msg == prefix);
    auto otherCause = new Exception("legacy");
    auto legacyWrapped = new UnsatisfiedDependencyException("beans.xml", "service", "dependency",
            "detail", otherCause);
    assert(legacyWrapped.msg == prefix ~ ": detail");
    assert(legacyWrapped.getRootCause() is otherCause);
}
