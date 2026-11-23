// Ported from spring-boot v4.2.0: module/spring-boot-sql/src/main/java/org/springframework/boot/sql/init/dependency/DependsOnDatabaseInitialization.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2). Boot's
// `DatabaseInitializationDependencyConfigurer` and its detectors, which make such beans depend on the database
// initializers, follow with the SQL initialization auto-configuration; until then the annotation is accepted and
// the bean is ordered by its injection points only.

/// `org.springframework.boot.sql.init.dependency`: declaring beans that depend on database initialization.
module flint.boot.sql.init.dependency;

@safe:

/// Marks a bean, or a `@Bean` method's bean, that depends on database initialization having completed.
struct DependsOnDatabaseInitialization
{
}
