/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.converter_test;

import flint.jakarta.persistence : AttributeConverter, Converter;

@safe:

@("converter metadata distinguishes an explicit converter from an automatically applied one")
unittest
{
    @Converter()
    static class ExplicitConverter : AttributeConverter!(bool, int)
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

    @Converter(true)
    static class AutomaticConverter : ExplicitConverter
    {
    }

    enum explicitConverter = __traits(getAttributes, ExplicitConverter)[0];
    enum automaticConverter = __traits(getAttributes, AutomaticConverter)[0];
    assert(!explicitConverter.autoApply && automaticConverter.autoApply);
}
