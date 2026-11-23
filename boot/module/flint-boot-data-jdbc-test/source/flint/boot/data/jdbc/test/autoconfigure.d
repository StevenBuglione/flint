// Ported from spring-boot v4.2.0: module/spring-boot-data-jdbc-test/src/main/java/org/springframework/boot/data/jdbc/test/autoconfigure/DataJdbcTest.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2); `Class<?>` attributes are `ClassRef`s.

/// `org.springframework.boot.data.jdbc.test.autoconfigure`: the Data JDBC test slice.
///
/// Annotation module: a leaf of UDA structs. `@DataJdbcTest` limits the context to Data JDBC components
/// (repositories, `JdbcTemplate`, the `DataSource`, SQL initialization) and runs each test in a transaction that
/// rolls back. The `@Transactional` and `@AutoConfigureTestDatabase` meta-annotations join when flint-data-jdbc
/// and the transaction module publish them.
module flint.boot.data.jdbc.test.autoconfigure;

import flint.boot.autoconfigure : ImportAutoConfiguration;
import flint.boot.context.properties : ClassRef;

@safe:

/// A test of the Data JDBC layer only.
@ImportAutoConfiguration
struct DataJdbcTest
{
    /// Properties in `key=value` form.
    string[] properties;
    /// Whether the default Data JDBC component filters apply.
    bool useDefaultFilters = true;
    /// Auto-configurations to leave out; an alias of `ImportAutoConfiguration.exclude`.
    ClassRef[] excludeAutoConfiguration;
}
