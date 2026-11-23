// Ported from spring-boot v4.2.0: module/spring-boot-transaction/src/test/java/org/springframework/boot/transaction/autoconfigure/ExecutionListenersTransactionManagerCustomizerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Mockito's mocks and `then(...).should()` are a recording stub manager.
module execution_listeners_transaction_manager_customizer_test;

@safe:

// Flint has no ExecutionListenersTransactionManagerCustomizer (nor TransactionManagerCustomizers).
version (FlintTransactionManagerCustomizers)
{
    import flint.boot.transaction.autoconfigure : ExecutionListenersTransactionManagerCustomizer;
    import flint.java.util : ArrayList, Collection;
    import flint.transaction : ConfigurableTransactionManager, TransactionExecutionListener;

    private final class RecordingTransactionManager : ConfigurableTransactionManager
    {
        TransactionExecutionListener[] added;
        private Collection!TransactionExecutionListener listeners;

        this()
        {
            listeners = new ArrayList!TransactionExecutionListener;
        }

        void setTransactionExecutionListeners(Collection!TransactionExecutionListener listeners)
        {
            this.listeners = listeners;
        }

        Collection!TransactionExecutionListener getTransactionExecutionListeners()
        {
            return listeners;
        }

        void addListener(TransactionExecutionListener listener)
        {
            added ~= listener;
        }
    }

    private final class StubListener : TransactionExecutionListener
    {
    }

    @("ExecutionListenersTransactionManagerCustomizerTests."
            ~ "whenTransactionManagerIsCustomizedThenExecutionListenersAreAddedToIt")
    unittest
    {
        TransactionExecutionListener listener1 = new StubListener;
        TransactionExecutionListener listener2 = new StubListener;
        auto transactionManager = new RecordingTransactionManager;
        new ExecutionListenersTransactionManagerCustomizer([listener1, listener2]).customize(transactionManager);
        assert(transactionManager.added == [listener1, listener2]);
    }
}
