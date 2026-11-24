// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/health/DataSourceHealthContributorAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean method is called directly over a context holding the
// data source beans, as Flint AOT's generated definitions call it, instead of through an ApplicationContextRunner;
// the conditions are checked on the class's UDAs, which Flint AOT evaluates. Not ported: the routing data source
// cases (Flint has no AbstractRoutingDataSource) and runWithValidationQueryPropertyShouldUseCustomQuery (no pool
// metadata providers), both listed in boot.md under D-JDBC-2.
module datasource_health_contributor_autoconfiguration_upstream_test;

import flint.boot.health.contributor : CompositeHealthContributor, HealthContributor;
import flint.boot.jdbc.autoconfigure.health : DataSourceHealthContributorAutoConfiguration,
    DataSourceHealthIndicatorProperties;
import flint.boot.jdbc.health : DataSourceHealthIndicator;
import flint.context.support : GenericApplicationContext;
import flint.javax.sql : DataSource;
import std.typecons : BlackHole;

@safe:

private HealthContributor dbHealthContributor(string[] dataSourceNames)
{
    auto context = new GenericApplicationContext;
    foreach (name; dataSourceNames)
        context.getBeanFactory().registerSingleton(name, new BlackHole!DataSource);
    context.refresh();
    return new DataSourceHealthContributorAutoConfiguration().dbHealthContributor(context,
            new DataSourceHealthIndicatorProperties);
}

@("runShouldCreateIndicator") unittest
{
    auto contributor = dbHealthContributor(["dataSource"]);
    assert(cast(DataSourceHealthIndicator) contributor !is null);
    assert((cast(DataSourceHealthIndicator) contributor).getQuery() is null, "isValid(), as Hikari's default");
}

@("runWhenMultipleDataSourceBeansShouldCreateCompositeIndicator") unittest
{
    auto contributor = dbHealthContributor(["dataSource", "standardDataSource", "nonDefaultDataSource"]);
    auto composite = cast(CompositeHealthContributor) contributor;
    assert(composite !is null);
    string[] names;
    foreach (child; composite.getContributors())
    {
        names ~= child.name;
        assert(cast(DataSourceHealthIndicator) child.contributor !is null);
    }
    import std.algorithm.sorting : sort;

    sort(names);
    assert(names == ["dataSource", "nonDefaultDataSource", "standardDataSource"]);
    assert(cast(DataSourceHealthIndicator) composite.getContributor("standardDataSource") !is null);
    assert(composite.getContributor("missing") is null);
}

@("Flint: no DataSource bean fails, as Boot's Assert.notEmpty (the auto-configuration is @ConditionalOnBean)")
unittest
{
    import flint.java.lang : IllegalArgumentException;

    bool thrown;
    try
        dbHealthContributor(null);
    catch (IllegalArgumentException ex)
        thrown = ex.msg == "'beans' must not be empty";
    assert(thrown);
}

@("runWhenDisabledShouldNotCreateIndicator: the class is conditional on management.health.db.enabled") unittest
{
    import flint.boot.autoconfigure.condition : ConditionalOnBean, ConditionalOnBooleanProperty,
        ConditionalOnMissingBean;
    import std.traits : getUDAs;

    alias Configuration = DataSourceHealthContributorAutoConfiguration;
    enum enabled = getUDAs!(Configuration, ConditionalOnBooleanProperty)[0];
    static assert(enabled.name == ["management.health.db.enabled"] && enabled.matchIfMissing);
    enum onBean = getUDAs!(Configuration, ConditionalOnBean)[0];
    static assert(onBean.value.length == 1 && onBean.value[0].name == "flint.javax.sql.DataSource");
    enum missing = getUDAs!(Configuration.dbHealthContributor, ConditionalOnMissingBean)[0];
    static assert(missing.name == ["dbHealthIndicator", "dbHealthContributor"]);
}

@("Flint: management.health.db.ignore-routing-data-sources binds, false by default") unittest
{
    auto properties = new DataSourceHealthIndicatorProperties;
    assert(!properties.isIgnoreRoutingDataSources());
    properties.setIgnoreRoutingDataSources(true);
    assert(properties.isIgnoreRoutingDataSources());
}
