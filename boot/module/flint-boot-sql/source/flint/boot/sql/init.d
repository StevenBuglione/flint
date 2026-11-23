// Ported from spring-boot v4.2.0: module/spring-boot-sql/src/main/java/org/springframework/boot/sql/init/DatabaseInitializationMode.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java Beans getters and setters are kept (rulebook R6); `spring.*` keys
// become `flint.*` with `spring.*` accepted as an alias (ADR-030).

/// `org.springframework.boot.sql.init`: SQL database initialization support.
module flint.boot.sql.init;

@safe:

/// Whether a database should be initialized by scripts.
enum DatabaseInitializationMode
{
    /// Always initialize the database.
    ALWAYS,
    /// Only initialize an embedded database.
    EMBEDDED,
    /// Never initialize the database.
    NEVER
}
