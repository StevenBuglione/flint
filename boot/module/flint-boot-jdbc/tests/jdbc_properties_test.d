/// Flint tests: `flint.datasource.*` and `flint.jdbc.*` carry Boot's defaults and bind with Boot's keys.
module jdbc_properties_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jdbc.autoconfigure : DataSourceProperties, EmbeddedDatabaseConnection, JdbcProperties;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

unittest
{
    auto properties = new DataSourceProperties;
    assert(properties.isGenerateUniqueName());
    assert(properties.getUrl() is null && properties.getName() is null);
    assert(properties.getEmbeddedDatabaseConnection() == EmbeddedDatabaseConnection.NONE);
    auto template_ = new JdbcProperties().getTemplate();
    assert(template_.isIgnoreWarnings() && template_.getFetchSize() == -1 && template_.getMaxRows() == -1);
    assert(template_.getQueryTimeout().isEmpty());
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.datasource.url", "jdbc:sqlite::memory:"], ["flint.datasource.username", "sa"],
        ["flint.datasource.generate-unique-name", "false"],
        ["flint.datasource.embedded-database-connection", "sqlite"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    binder.getDescriptors().add(descriptorOf!EmbeddedDatabaseConnection());
    auto properties = binder.bind!DataSourceProperties("flint.datasource").get();
    assert(properties.getUrl() == "jdbc:sqlite::memory:");
    assert(properties.getUsername() == "sa");
    assert(!properties.isGenerateUniqueName());
    assert(properties.getEmbeddedDatabaseConnection() == EmbeddedDatabaseConnection.SQLITE);
}
