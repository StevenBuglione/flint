// Ported from spring-boot v4.2.0: module/spring-boot-validation/src/test/java/org/springframework/boot/validation/autoconfigure/ValidationAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, instead of through an ApplicationContextRunner; the method-validation, primary-validator and
// user-validator cases join with MethodValidationPostProcessor and the context runner.
module validation_autoconfiguration_test;

import flint.boot.validation.autoconfigure : ValidationAutoConfiguration, ValidationConfigurationCustomizer;
import flint.jakarta.validation : Configuration;

@safe:

// Hibernate Validator registers itself as the provider when it is linked.
private alias provider = imported!"flint.hibernate.validator".HibernateValidator;

private final class RecordingCustomizer : ValidationConfigurationCustomizer
{
    int calls;

    void customize(Configuration configuration)
    {
        assert(configuration !is null);
        calls++;
    }
}

@("validationAutoConfigurationShouldConfigureDefaultValidator") unittest
{
    auto validator = new ValidationAutoConfiguration().defaultValidator(null);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    assert(validator.getValidator() !is null);
    assert(validator.getMessageInterpolator() !is null);
}

@("validationConfigurationCustomizersAreApplied") unittest
{
    auto first = new RecordingCustomizer;
    auto second = new RecordingCustomizer;
    auto validator = new ValidationAutoConfiguration().defaultValidator([first, second]);
    validator.afterPropertiesSet();
    scope (exit)
        validator.destroy();
    assert(first.calls == 1 && second.calls == 1);
}
