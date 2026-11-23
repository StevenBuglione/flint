// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/context/properties/bind/validation/BindValidationException.java
// with ValidationErrors.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ValidationBindHandler` is not ported yet; `EnvironmentConfigurationPropertiesBinder`
// validates a `@Validated` configuration properties bean once it is bound, as the handler's `onFinish` does for the
// root, and throws the same exceptions. A field error's origin is looked up among the bound properties by name.

/// `org.springframework.boot.context.properties.bind.validation`: validation of bound configuration properties.
module flint.boot.context.properties.bind.validation;

import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName;
import flint.java.lang : RuntimeException;
import flint.validation : FieldError, ObjectError;

@safe:

/// The validation errors of one bound object: its name, the properties bound under it, and the errors.
final class ValidationErrors
{
    private ConfigurationPropertyName name;
    private ConfigurationProperty[] boundProperties;
    private ObjectError[] errors;

    /// The errors of the object bound under `name` from `boundProperties`.
    this(ConfigurationPropertyName name, ConfigurationProperty[] boundProperties, ObjectError[] errors) pure nothrow
    {
        this.name = name;
        this.boundProperties = boundProperties;
        this.errors = errors;
    }

    /// The name of the bound object.
    ConfigurationPropertyName getName() pure nothrow @nogc
    {
        return name;
    }

    /// The properties bound under the name.
    ConfigurationProperty[] getBoundProperties() pure nothrow @nogc
    {
        return boundProperties;
    }

    /// Whether there are errors.
    bool hasErrors() const pure nothrow @nogc
    {
        return errors.length > 0;
    }

    /// The errors.
    ObjectError[] getAllErrors() pure nothrow @nogc
    {
        return errors;
    }

    /// The bound property a field error rejected (`name.field`, compared as configuration property names), or
    /// `null`: Boot's origin of an `OriginTrackedFieldError`.
    ConfigurationProperty propertyOf(FieldError error)
    {
        auto field = ConfigurationPropertyName.adapt(error.getField(), '.');
        if (field.isEmpty())
            return null;
        auto wanted = name.append(field);
        foreach (property; boundProperties)
        {
            if (property.getName().equals(wanted))
                return property;
        }
        return null;
    }
}

/// Thrown when a bound object fails validation; the cause of the `BindException`.
class BindValidationException : RuntimeException
{
    private ValidationErrors validationErrors;

    /// An exception for `validationErrors`.
    this(ValidationErrors validationErrors)
    {
        super(message(validationErrors));
        this.validationErrors = validationErrors;
    }

    /// The validation errors.
    ValidationErrors getValidationErrors() pure nothrow @nogc
    {
        return validationErrors;
    }

    private static string message(ValidationErrors errors)
    {
        string result = "Binding validation errors";
        if (errors !is null)
        {
            result ~= " on " ~ errors.getName().toString();
            foreach (error; errors.getAllErrors())
                result ~= "\n   - " ~ error.toString();
        }
        return result;
    }
}
