/++
spring-guides/gs-relational-data-access `complete/` (commit 39ee641, the reference pinned in benchmarks/spring/apps.json):
`RelationalDataAccessApplication.java` and `Customer.java`, ported to Flint Boot.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax only (one module per Java package, R1; record → struct, R11;
annotations, R2; `main` through `mixin FlintMain`, D-1), and one SQL type: the embedded database is SQLite, as for
the Go comparator (benchmarks/spring/apps.json), where H2's `id SERIAL` is `id INTEGER PRIMARY KEY`.
+/
module com.example.relationaldataaccess;

import flint.boot : CommandLineRunner, FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;
import flint.java.sql : ResultSet;
import flint.jdbc.core : JdbcTemplate;
import flint.slf4j : Logger, LoggerFactory;

@safe:

/// `public record Customer(long id, String firstName, String lastName)`.
struct Customer
{
    long id; ///
    string firstName; ///
    string lastName; ///

    /// The guide's `toString`.
    string toString() const
    {
        import std.format : format;

        return format("Customer[id=%d, firstName='%s', lastName='%s']", id, firstName, lastName);
    }
}

/// `@SpringBootApplication public class RelationalDataAccessApplication implements CommandLineRunner`; its `main`,
/// which runs `SpringApplication.run(RelationalDataAccessApplication.class, args)`, is the mixin's.
@FlintBootApplication class RelationalDataAccessApplication : CommandLineRunner
{
    private JdbcTemplate jdbcTemplate;

    ///
    this(JdbcTemplate jdbcTemplate)
    {
        this.jdbcTemplate = jdbcTemplate;
    }

    ///
    void run(string[])
    {
        import std.algorithm.iteration : map, splitter;
        import std.array : array;

        Logger log = LoggerFactory.getLogger!RelationalDataAccessApplication();

        log.info("Creating tables");

        jdbcTemplate.execute("DROP TABLE IF EXISTS customers");
        jdbcTemplate.execute(
                "CREATE TABLE customers(" ~ "id INTEGER PRIMARY KEY, first_name VARCHAR(255), "
                ~ "last_name VARCHAR(255))");

        // Split up the array of whole names into an array of first/last names
        string[][] splitUpNames = ["John Woo", "Jeff Dean", "Josh Bloch", "Josh Long"].map!(
                name => name.splitter(" ").array).array;

        // Print out each tuple of the list
        foreach (name; splitUpNames)
            log.info("Inserting customer record for {} {}", name[0], name[1]);

        // Use JdbcTemplate's batchUpdate operation to bulk load data
        jdbcTemplate.batchUpdate("INSERT INTO customers(first_name, last_name) VALUES (?,?)", splitUpNames);

        log.info("Querying for customer records where first_name = 'Josh':");
        jdbcTemplate.query("SELECT id, first_name, last_name FROM customers WHERE first_name = ?",
                (ResultSet rs, int) => Customer(rs.getLong("id"), rs.getString("first_name"),
                    rs.getString("last_name")), "Josh").forEach((Customer customer) {
            log.info(customer.toString());
        });
    }
}

mixin FlintMain!RelationalDataAccessApplication;
