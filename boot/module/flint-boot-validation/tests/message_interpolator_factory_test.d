// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/validation/MessageInterpolatorFactoryTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the factory lives in this module (flint.boot.validation); its `MessageSource`
// constructor and Boot's MessageSourceMessageInterpolator wait behind FlintMessageSourceMessageInterpolator.
module message_interpolator_factory_test;

import flint.boot.validation : MessageInterpolatorFactory;
import flint.hibernate.validator.messageinterpolation : ResourceBundleMessageInterpolator;

@safe:

// Hibernate Validator registers itself as the provider when it is linked.
private alias provider = imported!"flint.hibernate.validator".HibernateValidator;

@("MessageInterpolatorFactoryTests.getObjectShouldReturnResourceBundleMessageInterpolator") unittest
{
    const interpolator = new MessageInterpolatorFactory().getObject();
    assert(cast(const ResourceBundleMessageInterpolator) interpolator !is null);
}

// `new MessageInterpolatorFactory(messageSource)` and MessageSourceMessageInterpolator.
version (FlintMessageSourceMessageInterpolator)
{
    @("MessageInterpolatorFactoryTests."
            ~ "getObjectShouldReturnMessageSourceMessageInterpolatorDelegateWithResourceBundleMessageInterpolator")
    unittest
    {
        import flint.boot.validation : MessageSourceMessageInterpolator;
        import flint.context.support : StaticMessageSource;

        auto messageSource = new StaticMessageSource;
        auto interpolator = cast(MessageSourceMessageInterpolator) new MessageInterpolatorFactory(messageSource)
            .getObject();
        assert(interpolator !is null && interpolator.getMessageSource() is messageSource);
        assert(cast(ResourceBundleMessageInterpolator) interpolator.getMessageInterpolator() !is null);
    }
}
