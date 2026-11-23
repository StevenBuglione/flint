// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourceTransactionManagerAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases datasource_autoconfiguration_test.d does not hold. The auto-configuration's
// bean is called directly, as Flint AOT's generated definitions call it, and the bean-presence cases assert the
// conditions Flint AOT compiles (`hasSingleCandidate` is true for one candidate or one primary candidate); Boot's
// MultiDataSource configurations are plain data sources here.
module datasource_transaction_manager_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnSingleCandidate;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties,
    DataSourceTransactionManagerAutoConfiguration;
import flint.engine.aot.name : typeNameOf;
import flint.engine.jdbc : FlintDataSource;
import flint.javax.sql : DataSource;
import flint.jdbc.support : JdbcTransactionManager;
import flint.transaction : TransactionManager;
import std.traits : getUDAs, hasUDA;

@safe:

// The type `@ConditionalOnSingleCandidate` on `symbol` names.
private string singleCandidate(alias symbol)()
{
    string name;
    static foreach (condition; getUDAs!(symbol, ConditionalOnSingleCandidate))
        name = condition.value.name;
    return name;
}

// The bean types `@ConditionalOnMissingBean` on `symbol` yields to.
private string[] missingBeans(alias symbol)()
{
    string[] names;
    static foreach (condition; getUDAs!(symbol, ConditionalOnMissingBean))
        foreach (type; condition.value)
            names ~= type.name;
    return names;
}

private alias transactionManagerBean = DataSourceTransactionManagerAutoConfiguration.transactionManager;

private FlintDataSource embedded()
{
    return new DataSourceAutoConfiguration().dataSource(new DataSourceProperties);
}

@("DataSourceTransactionManagerAutoConfigurationTests.transactionManagerWithoutDataSourceIsNotConfigured")
unittest
{
    assert(singleCandidate!transactionManagerBean() == typeNameOf!DataSource);
}

@("DataSourceTransactionManagerAutoConfigurationTests.transactionManagerWithExistingTransactionManagerIsNotOverridden")
unittest
{
    assert(missingBeans!transactionManagerBean() == [typeNameOf!TransactionManager]);
}

@("DataSourceTransactionManagerAutoConfigurationTests.transactionManagerWithPersistenceExceptionTranslationEnabled")
unittest
{
    const manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(embedded());
    assert(typeid(manager) is typeid(JdbcTransactionManager));
}

@("DataSourceTransactionManagerAutoConfigurationTests.transactionManagerWithPersistenceExceptionTranslationDefault")
unittest
{
    const manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(embedded());
    assert(typeid(manager) is typeid(JdbcTransactionManager));
}

@("DataSourceTransactionManagerAutoConfigurationTests.transactionWithMultipleDataSourcesIsNotConfigured")
unittest
{
    // Two DataSource beans, neither primary: hasSingleCandidate("flint.javax.sql.DataSource") is false.
    assert(singleCandidate!transactionManagerBean() == typeNameOf!DataSource);
}

@("DataSourceTransactionManagerAutoConfigurationTests."
        ~ "transactionWithMultipleDataSourcesAndPrimaryCandidateIsConfigured")
unittest
{
    // The primary test1DataSource is the single candidate the bean is called with.
    assert(singleCandidate!transactionManagerBean() == typeNameOf!DataSource);
    auto test1DataSource = new FlintDataSource("jdbc:sqlite:file:test1?mode=memory&cache=shared");
    auto manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(test1DataSource);
    assert(manager.getDataSource() is test1DataSource);
}

@("DataSourceTransactionManagerAutoConfigurationTests.shouldNotUseDataSourcePropertiesIfDataSourceIsNotOnTheClasspath")
unittest
{
    import flint.boot.autoconfigure.condition : ConditionalOnClass;
    import flint.boot.context.properties : EnableConfigurationProperties;

    // Only DataSourceAutoConfiguration enables DataSourceProperties, and it requires the DataSource class.
    static assert(!hasUDA!(DataSourceTransactionManagerAutoConfiguration, EnableConfigurationProperties));
    bool requiresDataSource;
    static foreach (condition; getUDAs!(DataSourceAutoConfiguration, ConditionalOnClass))
        foreach (name; condition.name)
            requiresDataSource |= name == typeNameOf!DataSource;
    assert(requiresDataSource);
}

// LIKELY BUG: flint.transaction.* is bound (TransactionProperties) but never applied to the transaction manager:
// Flint has no TransactionManagerCustomizers, and TransactionProperties is not a TransactionManagerCustomizer.
version (FlintTransactionManagerCustomizers)
{
    @("DataSourceTransactionManagerAutoConfigurationTests.transactionManagerWithCustomizationIsConfigured")
    unittest
    {
        import core.time : Duration;
        import flint.boot.context.properties.bind : Binder;
        import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
        import flint.boot.transaction.autoconfigure : TransactionManagerCustomizer,
            TransactionManagerCustomizers, TransactionProperties;
        import flint.engine.aot.descriptor : descriptorOf;
        import flint.java.util : Optional;

        auto binder = new Binder([
            cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test",
                    [
                        ["spring.transaction.default-timeout", "1m"],
                        ["spring.transaction.rollback-on-commit-failure", "true"]
            ])
        ]);
        binder.getDescriptors().add(descriptorOf!(Optional!Duration)());
        binder.getDescriptors().add(descriptorOf!(Optional!bool)());
        auto transactionProperties = binder.bindOrCreate!TransactionProperties("flint.transaction");
        auto customizers = TransactionManagerCustomizers.of([
            cast(TransactionManagerCustomizer) transactionProperties
        ]);
        auto transactionManager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(embedded(),
                customizers);
        assert(transactionManager.getDefaultTimeout() == 60);
        assert(transactionManager.isRollbackOnCommitFailure());
    }
}

// Flint always creates a JdbcTransactionManager: spring.persistence.exceptiontranslation.enabled is not read.
version (FlintPersistenceExceptionTranslationProperty)
{
    @("DataSourceTransactionManagerAutoConfigurationTests."
            ~ "transactionManagerWithPersistenceExceptionTranslationDisabled")
    unittest
    {
        import flint.core.env : MapPropertySource, StandardEnvironment;
        import flint.engine.aot.any : Any;
        import flint.java.util : HashMap, Map;
        import flint.jdbc.datasource : DataSourceTransactionManager;

        auto environment = new StandardEnvironment;
        Map!(string, Any) source = new HashMap!(string, Any);
        source.put("spring.persistence.exceptiontranslation.enabled", Any.of("false"));
        environment.getPropertySources().addFirst(new MapPropertySource("test", source));
        const manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(environment, embedded());
        assert(typeid(manager) is typeid(DataSourceTransactionManager));
    }
}
