// Ported from spring-boot v4.2.0: module/spring-boot-transaction/src/test/java/org/springframework/boot/transaction/autoconfigure/TransactionAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the bean-presence cases assert the conditions Flint AOT compiles (the template's
// configuration needs a single PlatformTransactionManager candidate, the template backs off for a user's
// TransactionOperations), and the template bean is called directly, as Flint AOT's generated definitions call it.
// The reactive TransactionalOperator cases wait for `transaction.reactive` (Phase 2). The proxy cases assert the
// conditions of EnableTransactionManagementConfiguration; JDK and CGLIB proxies are one kind in Flint AOT.
module transaction_auto_configuration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnSingleCandidate;
import flint.boot.transaction.autoconfigure : TransactionAutoConfiguration, TransactionTemplateConfiguration;
import flint.context.annotation : Import;
import flint.engine.aot.name : typeNameOf;
import flint.transaction : PlatformTransactionManager, TransactionDefinition, TransactionStatus;
import flint.transaction.support : TransactionOperations;
import std.traits : getUDAs;

@safe:

private final class StubTransactionManager : PlatformTransactionManager
{
    TransactionStatus getTransaction(TransactionDefinition)
    {
        return null;
    }

    void commit(TransactionStatus)
    {
    }

    void rollback(TransactionStatus)
    {
    }
}

@("TransactionAutoConfigurationTests.whenThereIsNoPlatformTransactionManagerNoTransactionTemplateIsAutoConfigured")
unittest
{
    // The template's configuration is imported by TransactionAutoConfiguration and needs a single candidate.
    bool imported;
    static foreach (annotation; getUDAs!(TransactionAutoConfiguration, Import))
        foreach (type; annotation.value)
            imported |= type.name == typeNameOf!TransactionTemplateConfiguration;
    assert(imported);
    string candidate;
    static foreach (condition; getUDAs!(TransactionTemplateConfiguration, ConditionalOnSingleCandidate))
        candidate = condition.value.name;
    assert(candidate == typeNameOf!PlatformTransactionManager);
}

@("TransactionAutoConfigurationTests.whenThereIsASinglePlatformTransactionManagerATransactionTemplateIsAutoConfigured")
unittest
{
    auto transactionManager = new StubTransactionManager;
    auto template_ = new TransactionTemplateConfiguration().transactionTemplate(transactionManager);
    assert(template_.getTransactionManager() is transactionManager);
}

@("TransactionAutoConfigurationTests.whenAUserProvidesATransactionTemplateTheAutoConfiguredTemplateBacksOff")
unittest
{
    string[] missing;
    static foreach (condition; getUDAs!(TransactionTemplateConfiguration.transactionTemplate, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(missing == [typeNameOf!TransactionOperations]);
}

@("TransactionAutoConfigurationTests.transactionManagementIsEnabledWhenThereIsATransactionManager")
unittest
{
    import flint.boot.autoconfigure.condition : ConditionalOnBean;
    import flint.boot.transaction.autoconfigure : EnableTransactionManagementConfiguration;
    import flint.transaction : TransactionManager;
    import flint.transaction.annotation : EnableTransactionManagement;
    import flint.transaction.annotation.configuration : AbstractTransactionManagementConfiguration;
    import std.traits : hasUDA;

    bool imported;
    static foreach (annotation; getUDAs!(TransactionAutoConfiguration, Import))
        foreach (type; annotation.value)
            imported |= type.name == typeNameOf!EnableTransactionManagementConfiguration;
    assert(imported);
    static assert(hasUDA!(EnableTransactionManagementConfiguration, EnableTransactionManagement));
    string[] present, missing;
    static foreach (condition; getUDAs!(EnableTransactionManagementConfiguration, ConditionalOnBean))
        foreach (type; condition.value)
            present ~= type.name;
    static foreach (condition; getUDAs!(EnableTransactionManagementConfiguration, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(present == [typeNameOf!TransactionManager]);
    // A user's @EnableTransactionManagement (ProxyTransactionManagementConfiguration) backs it off.
    assert(missing == [typeNameOf!AbstractTransactionManagementConfiguration]);
}
