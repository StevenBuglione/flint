/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.listener_converter_metadata_test;

import flint.jakarta.persistence : AttributeConverter, Convert, Converter, Converts, EntityListeners, PostLoad;
import flint.java.classref : ClassRef, classOf;

@safe:

@("entity listener declarations preserve the order of lifecycle callbacks")
unittest
{
    static class AuditListener
    {
        @PostLoad
        void loaded(Object)
        {
        }
    }

    static class ValidationListener
    {
        @PostLoad
        void loaded(Object)
        {
        }
    }

    @EntityListeners([classOf!ValidationListener, classOf!AuditListener])
    static class Owner
    {
    }

    enum listeners = __traits(getAttributes, Owner)[0].value;
    assert(listeners.length == 2);
    assert(listeners[0] == classOf!ValidationListener);
    assert(listeners[1] == classOf!AuditListener);
}

@("converter overrides preserve dotted paths, selection and opt-out")
unittest
{
    @Converter(true)
    static class FlagConverter : AttributeConverter!(bool, int)
    {
        int convertToDatabaseColumn(bool attribute)
        {
            return attribute ? 1 : 0;
        }

        bool convertToEntityAttribute(int column)
        {
            return column != 0;
        }
    }

    @Converts([
        Convert(classOf!FlagConverter, "address.primary"),
        Convert(ClassRef.init, "address.secondary", true)
    ])
    static class Owner
    {
        @Convert()
        bool active;
    }

    enum defaultConversion = __traits(getAttributes, Owner.active)[0];
    assert(defaultConversion.converter.name is null);
    assert(defaultConversion.attributeName == "" && !defaultConversion.disableConversion);

    enum overrides = __traits(getAttributes, Owner)[0].value;
    assert(overrides.length == 2);
    assert(overrides[0].converter == classOf!FlagConverter && overrides[0].attributeName == "address.primary");
    assert(!overrides[0].disableConversion);
    assert(overrides[1].converter.name is null && overrides[1].attributeName == "address.secondary");
    assert(overrides[1].disableConversion);
}
