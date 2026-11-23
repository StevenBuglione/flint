// Ported from spring-boot v4.2.0: module/spring-boot-transaction/src/main/java/org/springframework/boot/transaction/autoconfigure/TransactionProperties.java
// with TransactionAutoConfiguration.java, TransactionManagerCustomizationAutoConfiguration.java,
// TransactionManagerCustomizer.java, TransactionManagerCustomizers.java and
// ExecutionListenersTransactionManagerCustomizer.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java Beans getters and setters are kept (rulebook R6); `spring.*` keys
// become `flint.*` with `spring.*` accepted as an alias (ADR-030). `TransactionManagerCustomizer<T>` is an
// abstract class template over the type-erased `AnyTransactionManagerCustomizer` (Boot's
// `TransactionManagerCustomizer<?>`), whose `customizeIfApplicable` is LambdaSafe's generic check: D interfaces
// cannot hold the cast that a customizer of another manager type needs. `ObjectProvider`s are arrays. The reactive
// `transactionalOperator` waits for `transaction.reactive` (Phase 2) and the AspectJ mode for AspectJ.
// `EnableTransactionManagementConfiguration`'s JDK and CGLIB variants are one configuration: Flint AOT's proxies are
// always subclasses, so `flint.aop.proxy-target-class` has nothing to choose.

/// `org.springframework.boot.transaction.autoconfigure`: the transaction auto-configuration and properties.
module flint.boot.transaction.autoconfigure;

import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnBean, ConditionalOnClass,
    ConditionalOnMissingBean, ConditionalOnSingleCandidate;
import flint.boot.context.properties : ClassRef, ConfigurationProperties, EnableConfigurationProperties;
import flint.boot.convert : ChronoUnit, DurationUnit;
import core.time : Duration;
import flint.context.annotation : Bean, Configuration, Import;
import flint.core.annotation : classOf;
import flint.engine.aot.name : typeNameOf;
import flint.java.util : Optional;
import flint.transaction : ConfigurableTransactionManager, PlatformTransactionManager,
    TransactionExecutionListener, TransactionManager;
import flint.transaction.annotation : EnableTransactionManagement;
import flint.transaction.support : AbstractPlatformTransactionManager, TransactionTemplate;

@safe:

/// Boot's `TransactionManagerCustomizer<?>`: a customizer of some transaction manager type, as
/// `TransactionManagerCustomizers` holds it.
abstract class AnyTransactionManagerCustomizer
{
    /// Customize `transactionManager` when it is of this customizer's manager type; whether it was.
    abstract bool customizeIfApplicable(TransactionManager transactionManager);
}

/// Callback for customizing a transaction manager of type `T` (Boot's `TransactionManagerCustomizer<T>`).
abstract class TransactionManagerCustomizer(T : TransactionManager) : AnyTransactionManagerCustomizer
{
    /// Customize `transactionManager`.
    abstract void customize(T transactionManager);

    final override bool customizeIfApplicable(TransactionManager transactionManager)
    {
        auto narrowed = cast(T) transactionManager;
        if (narrowed is null)
            return false;
        customize(narrowed);
        return true;
    }
}

/// The customizers to apply to a transaction manager, each only to the manager types it accepts.
final class TransactionManagerCustomizers
{
    private AnyTransactionManagerCustomizer[] customizers;

    private this(AnyTransactionManagerCustomizer[] customizers) pure nothrow
    {
        this.customizers = customizers.dup;
    }

    /// Customize `transactionManager` with every customizer whose manager type it is.
    void customize(TransactionManager transactionManager)
    {
        foreach (customizer; customizers)
            customizer.customizeIfApplicable(transactionManager);
    }

    /// The customizers, in order (Boot's `customizers` field; for tests).
    const(AnyTransactionManagerCustomizer)[] getCustomizers() const pure nothrow @nogc
    {
        return customizers;
    }

    /// Customizers of `customizers` (`null` for none).
    static TransactionManagerCustomizers of(AnyTransactionManagerCustomizer[] customizers) pure nothrow
    {
        return new TransactionManagerCustomizers(customizers);
    }
}

/// Adds the `TransactionExecutionListener` beans to each configurable transaction manager.
final class ExecutionListenersTransactionManagerCustomizer
    : TransactionManagerCustomizer!ConfigurableTransactionManager
{
    private TransactionExecutionListener[] listeners;

    /// A customizer adding `listeners`, in order.
    this(TransactionExecutionListener[] listeners) pure nothrow @nogc
    {
        this.listeners = listeners;
    }

    /// The listeners.
    TransactionExecutionListener[] getListeners() pure nothrow @nogc
    {
        return listeners;
    }

    override void customize(ConfigurableTransactionManager transactionManager)
    {
        foreach (listener; listeners)
            transactionManager.addListener(listener);
    }
}

/// Auto-configuration of the transaction manager customizers: `flint.transaction.*` (TransactionProperties) and the
/// execution listeners.
@beforeTransaction
@ConditionalOnClass(null, ["flint.transaction.PlatformTransactionManager"])
@EnableConfigurationProperties([ClassRef(typeNameOf!TransactionProperties)])
final class TransactionManagerCustomizationAutoConfiguration
{
    /// Every `TransactionManagerCustomizer` bean, in order.
    @Bean
    @ConditionalOnMissingBean([ClassRef(typeNameOf!TransactionManagerCustomizers)])
    TransactionManagerCustomizers platformTransactionManagerCustomizers(AnyTransactionManagerCustomizer[] customizers)
    {
        return TransactionManagerCustomizers.of(customizers);
    }

    /// The `TransactionExecutionListener` beans, as a customizer.
    @Bean
    ExecutionListenersTransactionManagerCustomizer transactionExecutionListeners(
            TransactionExecutionListener[] listeners)
    {
        return new ExecutionListenersTransactionManagerCustomizer(listeners);
    }
}

/// Auto-configuration of Spring transactions: a `TransactionTemplate` over the single
/// `PlatformTransactionManager`, unless the application defines `TransactionOperations`, and
/// `@EnableTransactionManagement` when there is a transaction manager and the application has not enabled it.
@AutoConfiguration
@ConditionalOnClass(null, ["flint.transaction.PlatformTransactionManager"])
@Import([
    classOf!TransactionTemplateConfiguration, classOf!EnableTransactionManagementConfiguration
])
final class TransactionAutoConfiguration
{
}

/// Boot's `TransactionAutoConfiguration.TransactionTemplateConfiguration` (hoisted, R13).
@liteConfiguration
@ConditionalOnSingleCandidate(ClassRef("flint.transaction.PlatformTransactionManager"))
final class TransactionTemplateConfiguration
{
    /// The transaction template.
    @Bean
    @ConditionalOnMissingBean([ClassRef("flint.transaction.support.TransactionOperations")])
    TransactionTemplate transactionTemplate(PlatformTransactionManager transactionManager)
    {
        return new TransactionTemplate(transactionManager);
    }
}

private enum Configuration liteConfiguration = () {
    Configuration configuration;
    configuration.proxyBeanMethods = false;
    return configuration;
}();

/// Boot's `TransactionAutoConfiguration.EnableTransactionManagementConfiguration` (hoisted, R13): `@Transactional`
/// methods run through flint:tx's `TransactionInterceptor`, unless the application enables transaction management
/// itself.
@liteConfiguration
@ConditionalOnBean([ClassRef("flint.transaction.TransactionManager")])
@ConditionalOnMissingBean(
        [
    ClassRef("flint.transaction.annotation.configuration.AbstractTransactionManagementConfiguration")
])
@EnableTransactionManagement
final class EnableTransactionManagementConfiguration
{
}

// `@AutoConfiguration(before = TransactionAutoConfiguration.class)`, as constants (dfmt 0.15 cannot parse named
// UDA arguments).
private enum AutoConfiguration beforeTransaction = () {
    AutoConfiguration configuration;
    configuration.beforeName = ["flint.boot.transaction.autoconfigure.TransactionAutoConfiguration"];
    return configuration;
}();

// ---- begin: generated by boot/tools/configuration_properties.py from its spec; edit the spec, not this region

/// Settings of the transaction managers. Bound under `flint.transaction` (Boot's `spring.transaction` is accepted as an
/// alias).
@ConfigurationProperties("flint.transaction")
final class TransactionProperties : TransactionManagerCustomizer!AbstractPlatformTransactionManager
{
    @DurationUnit(ChronoUnit.SECONDS)
    private Optional!Duration defaultTimeout;
    private Optional!bool rollbackOnCommitFailure;

    /// Default transaction timeout. If a duration suffix is not specified, seconds will be used.
    @DurationUnit(ChronoUnit.SECONDS)
    Optional!Duration getDefaultTimeout() const pure nothrow @nogc
    {
        return defaultTimeout;
    }

    /// Set `defaultTimeout`.
    void setDefaultTimeout(Optional!Duration defaultTimeout) pure nothrow @nogc
    {
        this.defaultTimeout = defaultTimeout;
    }

    /// Whether to roll back on commit failures.
    Optional!bool getRollbackOnCommitFailure() const pure nothrow @nogc
    {
        return rollbackOnCommitFailure;
    }

    /// Set `rollbackOnCommitFailure`.
    void setRollbackOnCommitFailure(Optional!bool rollbackOnCommitFailure) pure nothrow @nogc
    {
        this.rollbackOnCommitFailure = rollbackOnCommitFailure;
    }

    /// Apply the default timeout (in whole seconds) and rollback-on-commit-failure that are set.
    override void customize(AbstractPlatformTransactionManager transactionManager)
    {
        if (defaultTimeout.isPresent())
            transactionManager.setDefaultTimeout(cast(int) defaultTimeout.get().total!"seconds");
        if (rollbackOnCommitFailure.isPresent())
            transactionManager.setRollbackOnCommitFailure(rollbackOnCommitFailure.get());
    }
}

/// Flint AOT's descriptors of this module's properties types and their container property types, compiled
/// once with the platform instead of in each application's generated module (aot-contract.md section 3).
imported!"flint.engine.aot.descriptor".Descriptor[] flintAotDescriptors()
{
    import flint.engine.aot.descriptor : descriptorOf;

    return [
        descriptorOf!(TransactionProperties)(),
        descriptorOf!(typeof(TransactionProperties.defaultTimeout))(),
        descriptorOf!(typeof(TransactionProperties.rollbackOnCommitFailure))(),
    ];
}

// ---- end: generated region
