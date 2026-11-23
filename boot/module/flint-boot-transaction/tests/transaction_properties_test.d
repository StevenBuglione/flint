/// Flint tests: `flint.transaction.*` defaults.
module transaction_properties_test;

import flint.boot.transaction.autoconfigure : TransactionProperties;

@safe:

unittest
{
    auto properties = new TransactionProperties;
    assert(properties.getDefaultTimeout().isEmpty());
    assert(properties.getRollbackOnCommitFailure().isEmpty());
}

unittest
{
    import core.time : seconds;
    import flint.boot.context.properties.bind : Binder;
    import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;

    auto source = new MapConfigurationPropertySource("test", [
        ["spring.transaction.default-timeout", "30"],
        ["flint.transaction.rollback-on-commit-failure", "true"]
    ]);
    import core.time : Duration;
    import flint.engine.aot.descriptor : descriptorOf;
    import flint.java.util : Optional;

    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    binder.getDescriptors().add(descriptorOf!(Optional!Duration)());
    binder.getDescriptors().add(descriptorOf!(Optional!bool)());
    auto properties = binder.bind!TransactionProperties("flint.transaction").get();
    assert(properties.getDefaultTimeout().get() == seconds(30));
    assert(properties.getRollbackOnCommitFailure().get());
}
