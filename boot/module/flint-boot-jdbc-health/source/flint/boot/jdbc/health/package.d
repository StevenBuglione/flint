// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/main/java/org/springframework/boot/jdbc/health/DataSourceHealthIndicator.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: flint:boot-jdbc-health holds what spring-boot-jdbc compiles against its optional
// spring-boot-health dependency (deviation D-JDBC-2, docs/spring/phase1/boot.md); the `ConnectionCallback`s are
// delegates of `JdbcTemplate.execute`; the single column's value is an `Any` (`Object` in Java).

/// `org.springframework.boot.jdbc.health`: the health indicator for a `DataSource`.
module flint.boot.jdbc.health;

import flint.beans.factory : InitializingBean;
import flint.boot.health.contributor : AbstractHealthIndicator, Health, Status;
import flint.engine.aot.any : Any;
import flint.java.sql : Connection, ResultSet;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcTemplate, RowMapper;

@safe:

/++
`HealthIndicator` that tests the status of a `DataSource` and optionally runs a test query: the database product
name, then the query's single value, or `Connection.isValid(0)` when there is no query.
+/
class DataSourceHealthIndicator : AbstractHealthIndicator, InitializingBean
{
    private DataSource dataSource;
    private string query;
    private JdbcTemplate jdbcTemplate;

    /// Create a new `DataSourceHealthIndicator` instance (its data source is set later).
    this()
    {
        this(null, null);
    }

    /// Create a new `DataSourceHealthIndicator` using the specified `DataSource`.
    this(DataSource dataSource)
    {
        this(dataSource, null);
    }

    /// Create a new `DataSourceHealthIndicator` using the specified `DataSource` and validation query.
    this(DataSource dataSource, string query)
    {
        super("DataSource health check failed");
        this.dataSource = dataSource;
        this.query = query;
        this.jdbcTemplate = dataSource !is null ? new JdbcTemplate(dataSource) : null;
    }

    /// Fails unless the data source is set.
    override void afterPropertiesSet()
    {
        import flint.util : Assert;

        Assert.state(dataSource !is null, "DataSource for DataSourceHealthIndicator must be specified");
    }

    protected override void doHealthCheck(Health.Builder builder)
    {
        if (dataSource is null)
            builder.up().withDetail("database", Any.of("unknown"));
        else
            doDataSourceHealthCheck(builder);
    }

    private void doDataSourceHealthCheck(Health.Builder builder)
    {
        import flint.dao.support : DataAccessUtils;
        import flint.util : Assert, StringUtils;

        Assert.state(jdbcTemplate !is null, "'jdbcTemplate' must not be null");
        builder.up().withDetail("database", Any.of(getProduct()));
        const validationQuery = query;
        if (StringUtils.hasText(validationQuery))
        {
            builder.withDetail("validationQuery", Any.of(validationQuery));
            auto results = jdbcTemplate.query(validationQuery, new SingleColumnRowMapper);
            builder.withDetail("result", DataAccessUtils.requiredSingleResult(results));
        }
        else
        {
            builder.withDetail("validationQuery", Any.of("isValid()"));
            builder.status(isConnectionValid() ? Status.UP : Status.DOWN);
        }
    }

    private string getProduct()
    {
        string product;
        jdbcTemplate.execute((Connection connection) {
            product = connection.getMetaData().getDatabaseProductName();
        });
        return product;
    }

    private bool isConnectionValid()
    {
        bool valid;
        jdbcTemplate.execute((Connection connection) { valid = connection.isValid(0); });
        return valid;
    }

    /// Set the `DataSource` to use.
    void setDataSource(DataSource dataSource)
    {
        this.dataSource = dataSource;
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    /// Set a specific validation query to use to validate a connection. If none is set, a validation based on
    /// `Connection.isValid(int)` is used.
    void setQuery(string query) pure nothrow @nogc
    {
        this.query = query;
    }

    /// Return the validation query or `null`.
    string getQuery() const pure nothrow @nogc
    {
        return query;
    }
}

private:

/// `RowMapper` that expects and returns results from a single column.
final class SingleColumnRowMapper : RowMapper!Any
{
    Any mapRow(ResultSet rs, int rowNum)
    {
        import flint.jdbc : IncorrectResultSetColumnCountException;
        import flint.jdbc.support : JdbcUtils;
        import flint.util : Assert;

        auto metaData = rs.getMetaData();
        const columns = metaData.getColumnCount();
        if (columns != 1)
            throw new IncorrectResultSetColumnCountException(1, columns);
        auto result = JdbcUtils.getResultSetValue(rs, 1);
        Assert.state(!result.isNull(), "'result' must not be null");
        return result;
    }
}
