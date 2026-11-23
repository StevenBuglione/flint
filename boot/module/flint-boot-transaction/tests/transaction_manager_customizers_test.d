// Ported from spring-boot v4.2.0: module/spring-boot-transaction/src/test/java/org/springframework/boot/transaction/autoconfigure/TransactionManagerCustomizersTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Mockito mocks are stub transaction managers; JTA is not ported, so the narrower
// manager type is a PlatformTransactionManager subclass of the stub; `TransactionManagerCustomizer<T>` is a template
// interface over the manager type.
module transaction_manager_customizers_test;

@safe:

// Flint has no TransactionManagerCustomizers (nor TransactionManagerCustomizer): flint.transaction.* is bound but not
// applied to transaction managers.
version (FlintTransactionManagerCustomizers)
{
    import flint.boot.transaction.autoconfigure : TransactionManagerCustomizer, TransactionManagerCustomizers;
    import flint.transaction : PlatformTransactionManager, TransactionDefinition,
        TransactionManager, TransactionStatus;

    private class StubTransactionManager : PlatformTransactionManager
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

    // Boot's JtaTransactionManager in this test: a narrower manager type.
    private final class NarrowTransactionManager : StubTransactionManager
    {
    }

    private class TestCustomizer(T) : TransactionManagerCustomizer!T
    {
        private int count;

        void customize(T)
        {
            count++;
        }

        int getCount() const
        {
            return count;
        }
    }

    // Boot's TestJtaCustomizer.
    private final class TestNarrowCustomizer : TestCustomizer!NarrowTransactionManager
    {
    }

    @("TransactionManagerCustomizersTests.customizeWithNullCustomizersShouldDoNothing")
    unittest
    {
        TransactionManagerCustomizers.of(null).customize(cast(TransactionManager) new StubTransactionManager);
    }

    @("TransactionManagerCustomizersTests.customizeShouldCheckGeneric")
    unittest
    {
        auto general = new TestCustomizer!PlatformTransactionManager;
        auto narrow = new TestNarrowCustomizer;
        auto customizers = TransactionManagerCustomizers.of([
            cast(Object) general, cast(Object) narrow
        ]);
        customizers.customize(cast(TransactionManager) new StubTransactionManager);
        customizers.customize(cast(TransactionManager) new NarrowTransactionManager);
        assert(general.getCount() == 2);
        assert(narrow.getCount() == 1);
    }
}
