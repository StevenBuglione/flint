// Ported from spring-boot v4.2.0: module/spring-boot-validation/src/main/java/org/springframework/boot/validation/autoconfigure/ValidationAutoConfiguration.java
// with ValidationConfigurationCustomizer.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `@ConditionalOnResource(META-INF/services/...ValidationProvider)` is
// `@ConditionalOnClass` on Hibernate Validator's provider, which registers itself in Flint's closed world;
// `methodValidationPostProcessor`, `PrimaryDefaultValidatorPostProcessor` and `ValidatorAdapter` join when flint:context
// has `MethodValidationPostProcessor` and Spring MVC takes a validator.

/// `org.springframework.boot.validation.autoconfigure`: the validation auto-configuration.
module flint.boot.validation.autoconfigure;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean;
import flint.boot.context.properties : ClassRef;
import flint.boot.validation : MessageInterpolatorFactory;
import flint.context.annotation : Bean;
import flint.jakarta.validation : Configuration;
import flint.java.util.function_ : Consumer;
import flint.validation.beanvalidation : LocalValidatorFactoryBean;

@safe:

/// Customises the Jakarta Validation `Configuration` of the auto-configured validator.
interface ValidationConfigurationCustomizer
{
    /// Customise `configuration`.
    void customize(Configuration configuration);
}

/// Auto-configuration of the default `Validator`: a `LocalValidatorFactoryBean` with Boot's message interpolator,
/// customised by every `ValidationConfigurationCustomizer`, unless the application defines a `Validator`.
@AutoConfiguration @ConditionalOnClass(null, [
    "flint.jakarta.validation.Validator", "flint.hibernate.validator.HibernateValidator"
])
final class ValidationAutoConfiguration
{
    /// The default validator.
    @Bean @ConditionalOnMissingBean([ClassRef("flint.validation.Validator")])
    LocalValidatorFactoryBean defaultValidator(ValidationConfigurationCustomizer[] customizers)
    {
        auto factoryBean = new LocalValidatorFactoryBean;
        if (customizers.length)
            factoryBean.setConfigurationInitializer(new Customizers(customizers));
        factoryBean.setMessageInterpolator(new MessageInterpolatorFactory().getObject());
        return factoryBean;
    }
}

// Applies the customizers in order (Boot's lambda over `customizers.orderedStream()`).
private final class Customizers : Consumer!Configuration
{
    private ValidationConfigurationCustomizer[] customizers;

    this(ValidationConfigurationCustomizer[] customizers) pure nothrow
    {
        this.customizers = customizers.dup;
    }

    void accept(Configuration configuration)
    {
        foreach (customizer; customizers)
            customizer.customize(configuration);
    }
}
