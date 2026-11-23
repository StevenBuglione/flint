// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/availability/ApplicationAvailabilityAutoConfiguration.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2).

/// `org.springframework.boot.autoconfigure.availability`: the application availability auto-configuration.
module flint.boot.autoconfigure.availability;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.availability : ApplicationAvailabilityBean;
import flint.boot.context.properties : ClassRef;
import flint.context.annotation : Bean;

@safe:

/// Auto-configuration of `ApplicationAvailability`: an `ApplicationAvailabilityBean` tracking the context's
/// availability events, unless the application defines one.
@AutoConfiguration
final class ApplicationAvailabilityAutoConfiguration
{
    /// The application's availability.
    @Bean
    @ConditionalOnMissingBean([ClassRef("flint.boot.availability.ApplicationAvailability")])
    ApplicationAvailabilityBean applicationAvailability()
    {
        return new ApplicationAvailabilityBean;
    }
}
