// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/auditing/Auditor.java
// Copyright 2020-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.auditing.auditor;

import flint.engine.aot.objects : statelessInstance;
import flint.java.lang : JavaObject, valueOf;
import flint.java.util : Objects, Optional;
import std.typecons : Nullable;

@safe:

private abstract class AuditorValue
{
    abstract bool isPresent() nothrow @nogc;
    protected abstract Object referenceValue();
}

package(flint.data) abstract class Auditor(T) : AuditorValue
{
    static Auditor of(T source)
    {
        return Objects.isNull(source) ? none() : new PresentAuditor!T(source);
    }

    static Auditor of(U)(U source) if (is(U == Auditor))
    {
        return source is null ? none() : source;
    }

    static Auditor ofOptional(Optional!T source)
    {
        return source.isPresent() ? of(source.get()) : none();
    }

    static Auditor ofOptional(Optional!Auditor source)
    {
        return source.isPresent() ? of(source.get()) : none();
    }

    // A fieldless value can be shared for every use of the same type (R17).
    static Auditor none() nothrow @nogc
    {
        return statelessInstance!(MissingAuditor!T)();
    }

    protected abstract Optional!T optionalValue();

    static if (is(T == class) || is(T == interface))
    {
        T getValue()
        {
            return optionalValue().orElse(null);
        }
    }
    else
    {
        Nullable!T getValue()
        {
            auto value = optionalValue();
            return value.isPresent() ? Nullable!T(value.get()) : Nullable!T.init;
        }
    }

    bool equals(Object other)
    {
        if (this is other)
            return true;
        if (auto typed = cast(Auditor) other)
            return optionalValue() == typed.optionalValue();
        auto value = cast(AuditorValue) other;
        if (value is null)
            return false;
        const present = isPresent();
        const otherPresent = value.isPresent();
        if (!present || !otherPresent)
            return present == otherPresent;
        auto reference = referenceValue();
        return reference !is null && Objects.equals(reference, value.referenceValue());
    }

    protected override Object referenceValue()
    {
        static if (is(T == class) || is(T == interface))
            return cast(Object) getValue();
        else
            return null;
    }

    int hashCode()
    {
        auto value = optionalValue();
        return value.isPresent() ? Objects.hashCode(value.get()) : 0;
    }

    override string toString()
    {
        auto value = optionalValue();
        return value.isPresent() ? valueOf(value.get()) : "Auditor.none()";
    }

    mixin JavaObject;
}

private final class PresentAuditor(T) : Auditor!T
{
    private T value;

    this(T value)
    {
        this.value = value;
    }

    override bool isPresent() nothrow @nogc
    {
        return true;
    }

    protected override Optional!T optionalValue()
    {
        return Optional!T.of(value);
    }
}

private final class MissingAuditor(T) : Auditor!T
{
    override bool isPresent() nothrow @nogc
    {
        return false;
    }

    protected override Optional!T optionalValue()
    {
        return Optional!T.empty();
    }
}
