// Ported from spring-boot v4.2.0: module/spring-boot-validation/src/main/java/org/springframework/boot/validation/autoconfigure/ValidationAutoConfiguration.java
// with ValidationConfigurationCustomizer.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `@ConditionalOnResource(META-INF/services/...ValidationProvider)` is
// `@ConditionalOnClass` on Hibernate Validator's provider, which registers itself in Flint's closed world;
// `defaultValidator` hands Hibernate Validator the context's Flint AOT descriptors (Hibernate's reflection);
// `methodValidationPostProcessor` has no exclude filters (`MethodValidationExcludeFilter` follows with its uses)
// and no `flint.aop.proxy-target-class` (Flint AOT generates the proxies); `PrimaryDefaultValidatorPostProcessor` and
// `ValidatorAdapter` join when Spring MVC takes a validator.

/// `org.springframework.boot.validation.autoconfigure`: the validation auto-configuration.
module flint.boot.validation.autoconfigure;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean;
import flint.boot.context.properties : ClassRef;
import flint.boot.validation : MessageInterpolatorFactory;
import flint.context : ApplicationContext;
import flint.context.annotation : Bean;
import flint.engine.aot.descriptor : DescriptorTable;
import flint.hibernate.validator : HibernateValidatorConfiguration;
import flint.jakarta.validation : Configuration, JakartaValidator = Validator;
import flint.java.util.function_ : Consumer;
import flint.validation.beanvalidation : LocalValidatorFactoryBean, MethodValidationPostProcessor;

@safe:

/// Customises the Jakarta Validation `Configuration` of the auto-configured validator.
interface ValidationConfigurationCustomizer
{
    /// Customise `configuration`.
    void customize(Configuration configuration);
}

/// Auto-configuration of the default `Validator`: a `LocalValidatorFactoryBean` with Boot's message interpolator,
/// over the context's Flint AOT descriptors and customised by every `ValidationConfigurationCustomizer`, unless the
/// application defines a `Validator`.
@AutoConfiguration
@ConditionalOnClass(null, [
    "flint.jakarta.validation.Validator", "flint.hibernate.validator.HibernateValidator"
])
final class ValidationAutoConfiguration
{
    /// The default validator.
    @Bean
    @ConditionalOnMissingBean([ClassRef("flint.jakarta.validation.Validator")])
    LocalValidatorFactoryBean defaultValidator(ValidationConfigurationCustomizer[] customizers,
            ApplicationContext context = null)
    {
        import flint.context.support : GenericApplicationContext;

        auto factoryBean = new LocalValidatorFactoryBean;
        auto generic = cast(GenericApplicationContext) context;
        auto descriptors = generic is null ? null : generic.getDescriptorTable();
        if (customizers.length || descriptors !is null)
            factoryBean.setConfigurationInitializer(new Customizers(descriptors, customizers));
        factoryBean.setMessageInterpolator(new MessageInterpolatorFactory().getObject());
        return factoryBean;
    }

    /// Method validation of `@Validated` beans, with the context's Jakarta `Validator` (the default validator unless
    /// the application defines one), asked for when the post-processor is initialised.
    @Bean
    @ConditionalOnMissingBean
    MethodValidationPostProcessor methodValidationPostProcessor(ApplicationContext context)
    {
        auto processor = new MethodValidationPostProcessor;
        auto environment = context.getEnvironment();
        processor.setAdaptConstraintViolations(
                environment.getProperty!bool("flint.validation.method.adapt-constraint-violations",
                environment.getProperty!bool("spring.validation.method.adapt-constraint-violations", false)));
        processor.setValidatorProvider(() => contextValidator(context));
        return processor;
    }

    // ObjectProvider<Validator>.getIfUnique, falling back to the default provider's validator as Spring does.
    private static JakartaValidator contextValidator(ApplicationContext context)
    {
        import flint.engine.aot.name : typeNameOf;
        import flint.jakarta.validation : Validation;

        auto names = context.getBeanNamesForTypeErased(typeNameOf!JakartaValidator, true, false);
        if (names.length == 1)
            return cast(JakartaValidator) context.getBean(names[0]);
        return Validation.buildDefaultValidatorFactory().getValidator();
    }
}

// Hands Hibernate Validator the descriptors, then applies the customizers in order (Boot's lambda over
// `customizers.orderedStream()`).
private final class Customizers : Consumer!Configuration
{
    private DescriptorTable descriptors;
    private ValidationConfigurationCustomizer[] customizers;

    this(DescriptorTable descriptors, ValidationConfigurationCustomizer[] customizers) pure nothrow
    {
        this.descriptors = descriptors;
        this.customizers = customizers.dup;
    }

    void accept(Configuration configuration)
    {
        if (auto hibernate = cast(HibernateValidatorConfiguration) configuration)
            if (descriptors !is null)
                hibernate.descriptors(descriptors);
        foreach (customizer; customizers)
            customizer.customize(configuration);
    }
}
