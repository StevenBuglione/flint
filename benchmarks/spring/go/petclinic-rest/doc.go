// Command petclinic-rest is the Go comparator for spring-petclinic-rest with its JDBC repository layer on
// PostgreSQL (profiles postgres,jdbc), as ADR-030 section 8 requires: the same REST API, the same SQL work per
// request and the same responses, so the black-box suite in benchmarks/spring/suites scores it like the Java
// reference.
//
// It is written the way a Go developer would write the service: net/http with Go 1.22 method and wildcard
// patterns, encoding/json, and database/sql over the pgx driver. What is reproduced from Spring is what a client
// can observe: the controllers' status codes and bodies, the application's ProblemDetail advice (including the
// exception class names it reports as titles), Bean Validation messages for the openapi.yml constraints, the
// @CrossOrigin CORS headers, the Spring Security response headers, the actuator endpoints and Tomcat's 404 page
// outside the context path.
//
// Configuration is the reference's: SERVER_PORT, POSTGRES_URL (JDBC form), POSTGRES_USER and POSTGRES_PASS. At
// start-up the embedded schema.sql and data.sql run against the database, as spring.sql.init.mode=always does.
//
// NOTICE: schema.sql and data.sql are copied unchanged from spring-petclinic-rest
// (https://github.com/spring-petclinic/spring-petclinic-rest, commit 220f4ba8e92cec9ad1faa03324723a3e9da63d95,
// src/main/resources/db/postgres), Copyright the original author or authors, licensed under the Apache License,
// Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). The SQL statements in store.go mirror that project's
// repository/jdbc classes under the same licence.
package main
