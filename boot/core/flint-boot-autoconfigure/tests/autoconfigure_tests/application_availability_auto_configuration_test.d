// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/availability/ApplicationAvailabilityAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, instead of through an ApplicationContextRunner, and its back-off is read from the
// `@ConditionalOnMissingBean` UDA Flint AOT evaluates; LazyInitializationBeanFactoryPostProcessor is a lazy bean
// definition; `getLastChangeEvent(ReadinessState.class)` is the readiness state the event changed.
module autoconfigure_tests.application_availability_auto_configuration_test;

import flint.boot.autoconfigure.availability : ApplicationAvailabilityAutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.availability : ApplicationAvailability, ApplicationAvailabilityBean;
import std.traits : getUDAs;

@safe:

@("ApplicationAvailabilityAutoConfigurationTests.providerIsPresentWhenNotRegistered") unittest
{
    const ApplicationAvailability availability = new ApplicationAvailabilityAutoConfiguration()
        .applicationAvailability();
    assert(availability !is null);
    static assert(__traits(identifier,
            ApplicationAvailabilityAutoConfiguration.applicationAvailability) == "applicationAvailability");
}

@("ApplicationAvailabilityAutoConfigurationTests.providerIsNotConfiguredWhenCustomOneIsPresent") unittest
{
    enum conditions = getUDAs!(ApplicationAvailabilityAutoConfiguration.applicationAvailability,
                ConditionalOnMissingBean);
    static assert(conditions.length == 1);
    static assert(conditions[0].value[0].name == "flint.boot.availability.ApplicationAvailability");
}

// LIKELY BUG: Spring registers listener beans by name and creates a lazy one when an event is multicast; Flint's
// context skips a lazy GenericApplicationListener bean, so it never receives the AvailabilityChangeEvent (the same
// bean, not lazy, does).
version (FlintLazyListenerBeans)
{
    @("ApplicationAvailabilityAutoConfigurationTests."
            ~ "whenLazyInitializationIsEnabledApplicationAvailabilityBeanShouldStillReceiveAvailabilityChangeEvents")
    unittest
    {
        import flint.boot.availability : AvailabilityChangeEvent, ReadinessState;
        import flint.context.support : GenericApplicationContext;

        auto context = new GenericApplicationContext;
        context.registerBean!ApplicationAvailabilityBean("applicationAvailability",
                () => new ApplicationAvailabilityAutoConfiguration().applicationAvailability(), (definition) {
            definition.setLazyInit(true);
        });
        context.refresh();
        scope (exit)
            context.close();
        AvailabilityChangeEvent!ReadinessState.publish(context, ReadinessState.ACCEPTING_TRAFFIC);
        auto applicationAvailability = cast(ApplicationAvailabilityBean) context.getBean("applicationAvailability");
        assert(applicationAvailability.getReadinessState() == ReadinessState.ACCEPTING_TRAFFIC);
    }
}
