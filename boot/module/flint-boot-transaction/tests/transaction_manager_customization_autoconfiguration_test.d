// Ported from spring-boot v4.2.0: module/spring-boot-transaction/src/test/java/org/springframework/boot/transaction/autoconfigure/TransactionManagerCustomizationAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, with the bound TransactionProperties; the back-off case asserts the condition Flint AOT
// compiles.
module transaction_manager_customization_autoconfiguration_test;

@safe:

// Flint has no TransactionManagerCustomizationAutoConfiguration: TransactionProperties is bound but is not a
// TransactionManagerCustomizer, so no transaction manager is customized from flint.transaction.*.
import flint.boot.transaction.autoconfigure : AnyTransactionManagerCustomizer,
    ExecutionListenersTransactionManagerCustomizer,
    TransactionManagerCustomizationAutoConfiguration, TransactionManagerCustomizers, TransactionProperties;

@("TransactionManagerCustomizationAutoConfigurationTests.autoConfiguresTransactionManagerCustomizers")
unittest
{
    import core.time : Duration, seconds;
    import flint.java.util : Optional;

    auto properties = new TransactionProperties;
    properties.setDefaultTimeout(Optional!Duration.of(seconds(30)));
    auto customizers = new TransactionManagerCustomizationAutoConfiguration().platformTransactionManagerCustomizers(
            [
        cast(AnyTransactionManagerCustomizer) properties,
        new ExecutionListenersTransactionManagerCustomizer(null)
    ]);
    const all = customizers.getCustomizers();
    assert(all.length == 2);
    bool hasProperties, hasListeners;
    foreach (customizer; all)
    {
        hasProperties |= cast(const TransactionProperties) customizer !is null;
        hasListeners |= cast(const ExecutionListenersTransactionManagerCustomizer) customizer !is null;
    }
    assert(hasProperties && hasListeners);
}

@("TransactionManagerCustomizationAutoConfigurationTests.autoConfiguredTransactionManagerCustomizersBacksOff")
unittest
{
    import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
    import flint.engine.aot.name : typeNameOf;
    import std.traits : getUDAs;

    alias bean = TransactionManagerCustomizationAutoConfiguration.platformTransactionManagerCustomizers;
    string[] missing;
    static foreach (condition; getUDAs!(bean, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(missing == [typeNameOf!TransactionManagerCustomizers]);
    assert(TransactionManagerCustomizers.of(null).getCustomizers().length == 0);
}
