// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/validation/MessageInterpolatorFactory.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the factory lives with the validation module rather than in core, which keeps no
// Jakarta Validation types in Flint; the `MessageSource` constructor and Boot's `MessageSourceMessageInterpolator`
// join when flint:context has `MessageSource`; the Hibernate `ParameterMessageInterpolator` fallback is the
// provider's own default interpolator in Flint, so there is no class to look up by name.

/// `org.springframework.boot.validation`: Boot's validation support.
module flint.boot.validation;

import flint.jakarta.validation : MessageInterpolator, Validation;

@safe:

/// Creates the `MessageInterpolator` Boot configures validators with: the provider's default.
class MessageInterpolatorFactory
{
    /// The interpolator. Throws `ValidationException` when no provider is registered.
    MessageInterpolator getObject()
    {
        return Validation.byDefaultProvider().getDefaultMessageInterpolator();
    }
}
