# Phase 1 data access: `flint:jdbc` and `flint:tx`

This note designs the Phase 1 port of spring-jdbc and spring-tx from Spring Framework v7.1.0 (ADR-030, rulebook v2). The implementation lands in `flint-framework` at `flint-jdbc/` and `flint-tx/` after the repository cutover. Until then, this note lives in `flint`.

**Done means:** the data layer of [gs-relational-data-access](https://github.com/spring-guides/gs-relational-data-access) runs on Flint, using `JdbcTemplate` and `@Transactional`.

## Scope

Upstream size: spring-jdbc has 231 public types in about 39,000 lines and 882 tests. spring-tx has about 22,000 lines and 379 tests. Phase 1 ports the subset an ordinary Boot application touches. Everything else is classified in `api/mapping.json`.

| D module (DUB package) | Upstream package | Phase 1 content |
| --- | --- | --- |
| `flint.dao` (`flint:tx`) | `org.springframework.dao` | The whole `DataAccessException` hierarchy (27 types) |
| `flint.dao.support` (`flint:tx`) | `org.springframework.dao.support` | `DataAccessUtils`, `PersistenceExceptionTranslator` |
| `flint.transaction` (`flint:tx`) | `org.springframework.transaction` | `PlatformTransactionManager`, `TransactionDefinition`, `TransactionStatus`, `TransactionException` and its subclasses |
| `flint.transaction.support` (`flint:tx`) | `….transaction.support` | `TransactionTemplate`, `AbstractPlatformTransactionManager`, `DefaultTransactionDefinition`, `DefaultTransactionStatus`, `TransactionSynchronizationManager`, `TransactionSynchronization`, `ResourceHolderSupport` |
| `flint.transaction.annotation` (`flint:tx`) | `….transaction.annotation` | `@Transactional`, `Propagation`, `Isolation`, `@EnableTransactionManagement` |
| `flint.transaction.interceptor` (`flint:tx`) | `….transaction.interceptor` | `TransactionAttribute`, `RuleBasedTransactionAttribute`, `RollbackRuleAttribute`, `TransactionAspectSupport`, `TransactionInterceptor` |
| `flint.jdbc` (`flint:jdbc`) | `org.springframework.jdbc` | `BadSqlGrammarException`, `UncategorizedSQLException`, `CannotGetJdbcConnectionException`, … |
| `flint.jdbc.core` (`flint:jdbc`) | `….jdbc.core` | `JdbcTemplate`, `JdbcOperations`, `RowMapper`, `ResultSetExtractor`, `RowCallbackHandler`, `PreparedStatementSetter`, `BatchPreparedStatementSetter`, `ColumnMapRowMapper`, `SingleColumnRowMapper`, `BeanPropertyRowMapper`, `DataClassRowMapper`, `ArgumentPreparedStatementSetter`, `SqlParameterValue`, `StatementCallback`, `ConnectionCallback` |
| `flint.jdbc.core.namedparam` (`flint:jdbc`) | `….core.namedparam` | `NamedParameterJdbcTemplate`, `MapSqlParameterSource`, `BeanPropertySqlParameterSource`, `NamedParameterUtils` |
| `flint.jdbc.core.simple` (`flint:jdbc`) | `….core.simple` | `JdbcClient`, `SimpleJdbcInsert` |
| `flint.jdbc.support` (`flint:jdbc`) | `….jdbc.support` | `KeyHolder`, `GeneratedKeyHolder`, `JdbcUtils`, `SQLExceptionTranslator`, `SQLExceptionSubclassTranslator`, `SQLStateSQLExceptionTranslator`, `SQLErrorCodeSQLExceptionTranslator` (with the PostgreSQL and SQLite codes inlined as data) |
| `flint.jdbc.datasource` (`flint:jdbc`) | `….jdbc.datasource` | `DataSourceUtils`, `DriverManagerDataSource`, `SimpleDriverDataSource`, `ConnectionHolder`, `DataSourceTransactionManager`, `JdbcTransactionManager`, `TransactionAwareDataSourceProxy` |
| `flint.java.sql`, `flint.javax.sql` (`flint:java`) | `java.sql`, `javax.sql` | The JDBC interfaces Spring's signatures expose: `Connection`, `PreparedStatement`, `Statement`, `ResultSet`, `ResultSetMetaData`, `DatabaseMetaData`, `SQLException` and its JDBC 4 subclasses, `Types`, `Savepoint`, `DriverManager`, and `DataSource` |
| `flint.hikari` (`flint:hikari`) | `com.zaxxer.hikari` | `HikariDataSource` and `HikariConfig`, with Hikari's property names, over the engine's pool |

`api/mapping.json` classifies the rest:
- **`deferred` (Phase 2):** `jdbc.object`, `jdbc.datasource.embedded` (it becomes SQLite in-memory), `jdbc.datasource.init`, `jdbc.datasource.lookup` (except JNDI), `jdbc.support.incrementer`, `jdbc.support.lob`, `jdbc.support.rowset`, `jdbc.core.metadata` (except what `SimpleJdbcInsert` uses), `transaction.event`, and `transaction.reactive`.
- **`deferred` (Phase 3):** `jdbc.config` and `transaction.config`, the XML namespaces, as for `beans.factory.xml`.
- **`excluded`:**
  - `jvm-platform`: JNDI lookups, `jca.**`, `transaction.jta.**` (JTA needs an XA transaction manager, which Flint does not have), and `jdbc.support.xml` (`SQLXML`);
  - `runtime-reflection`: `dao.annotation.PersistenceExceptionTranslationPostProcessor`'s runtime proxying, which Flint AOT replaces with generated translation.

## Layers

```text
application        JdbcTemplate, JdbcClient, @Transactional
flint:jdbc, :tx    Spring's code, ported: templates, translators, transaction managers
flint:java         flint.java.sql / flint.javax.sql interfaces (JDBC 4.3 subset)
flint:engine-sql   the Flint JDBC driver: java.sql interfaces over Pool, Connection and Row
                   the SQL engine: nothrow @nogc, arena-backed, libpq and SQLite shims
```

Spring's JDBC code is written against the JDBC interfaces. Porting those interfaces as `flint.java.sql`, and putting a Flint JDBC driver beneath them, keeps `JdbcTemplate`, the translators and `DataSourceTransactionManager` close to line-for-line ports. It also lets the upstream tests' Mockito mocks of `Connection`, `PreparedStatement` and `ResultSet` become hand-written fakes of the same interfaces.

The driver lives in the engine (`flint.engine.sql.jdbc`), because it is not Spring code. It accepts `jdbc:postgresql://…` and `jdbc:sqlite:…` URLs, so `flint.datasource.url` reads as it does in Boot.

### The user boundary

- **The engine** (`flint.engine.sql`) stays `nothrow @nogc`. It returns `Result` and borrows row bytes from the statement's request arena (AGENTS.md, ADR-030 section 4).
- **The driver is the boundary.** `PreparedStatement.executeQuery` runs the statement, and the engine's row consumer copies each cell into GC memory: `string` for text, `ubyte[]` for bytes, scalars inline. The resulting `ResultSet` is a materialized cursor, so `next()`, `getString("first_name")` and `getLong(1)` behave as in JDBC. No arena memory reaches user code. A streaming cursor for `queryForStream` is Phase 2.
- **Errors.** An engine `Error` becomes a `SQLException`, carrying `SQLState` and the vendor code. It is thrown as its JDBC 4 subclass (`SQLIntegrityConstraintViolationException`, `SQLSyntaxErrorException`, `SQLTransientConnectionException`, …), so Spring's default `SQLExceptionSubclassTranslator` maps `23505` to `DuplicateKeyException`, as it does on the JVM.
  - **Engine change needed:** today the PostgreSQL shim reads `PG_DIAG_SQLSTATE`, folds it into a `Status` (`23xxx` and `40xxx` both become `conflict`) and drops it, and the SQLite shim keeps no extended result code. The shim must keep the SQLSTATE (SQLite's extended codes mapped to SQLSTATE by a table), the vendor code and the message on the lease, readable through a `@nogc` accessor.

### Blocking and fibers

- **Network I/O suspends the fiber.** libpq runs non-blocking, and its socket is waited on through the reactor's native watches, so a query suspends only its fiber.
- **SQLite needs no offload pool.** The engine already gives each SQLite connection a worker thread with an eventfd wake, so `sqlite3_step` never blocks a loop.
- **`Reactor.offload` covers blocking C calls that have no event source,** such as libpq connection startup, if it is moved off its detached thread. Phase 1 adds none.
- **Startup.** Off a reactor (a `CommandLineRunner` at startup, as in the guide) the engine waits on its own descriptor, so the same `JdbcTemplate` works before the web server starts.

### Transactions on fibers

`TransactionSynchronizationManager` keeps Spring's static API: `bindResource`, `getResource`, `unbindResource`, `initSynchronization`, `registerSynchronization`, `isActualTransactionActive`, and the rest. Its state is one `shared FiberLocal!TransactionState`, where `TransactionState` is a `final class` holding:
- the resource map;
- the synchronization list;
- the current transaction name, read-only flag, isolation level and actual-active flag.

The class is created on the first bind and dropped by `clear()`. A request's transaction therefore follows its task fiber and never another task sharing the worker thread. Off a fiber (startup, offload threads) it is per thread, which is Java's behaviour.

`DataSourceTransactionManager` binds a `ConnectionHolder` for the leased connection. `doBegin` issues `BEGIN`, with the isolation level and read-only mode:
- **PostgreSQL:** `SET TRANSACTION ISOLATION LEVEL …` and `READ ONLY`.
- **SQLite:** `BEGIN DEFERRED`, or `BEGIN IMMEDIATE` for serializable. Read-only uses `PRAGMA query_only`.

The engine's lease-transaction accounting (`claimTransaction` and `endTransaction`) marks the lease dirty, so a connection released mid-transaction is retired rather than reused.

All seven propagation behaviours are ported:
- `REQUIRES_NEW` and `NOT_SUPPORTED` suspend by unbinding the holder;
- `NESTED` uses `SAVEPOINT`.

### `@Transactional` and Flint AOT

`@Transactional` is a UDA struct with Spring's attributes and defaults (R2):
- `value` and `transactionManager`, `label`, `propagation`, `isolation`, `timeout` and `timeoutString`, `readOnly`;
- `rollbackFor` and `noRollbackFor`, with their `ClassName` variants.

`Class<? extends Throwable>[]` attributes are `TypeInfo_Class[]` written as `rollbackFor: [typeid(IOException)]`. This works as a UDA on DMD and LDC, and the rule matches with `isBaseOf`, which is the same assignability test as Spring's `RollbackRuleAttribute`. It needs a rulebook entry under R2 for `Class`-valued annotation attributes, because R4's template parameters cannot be array elements.

Flint AOT (the flint-aot session) applies it, as Spring's CGLIB proxy does, by generating a subclass of each bean class with a `@Transactional` method or class:

```d
final class OrderService__FlintTx : OrderService
{
    override Order place(Cart cart)
    {
        return transactionInterceptor.invokeWithinTransaction!Order(placeAttribute, () => super.place(cart));
    }
}
```

`placeAttribute` is a `RuleBasedTransactionAttribute` built at compile time from the merged UDAs (method over class, with `@AliasFor`). `invokeWithinTransaction` is Spring's `TransactionAspectSupport` logic, unchanged: it resolves the manager by qualifier, begins or joins, commits, and on a throwable rolls back by rule or commits. As with CGLIB, the class and method must not be `final`, and a call from inside the same object is not intercepted.

### Row mapping through descriptors

`BeanPropertyRowMapper!T`, `DataClassRowMapper!T`, `BeanPropertySqlParameterSource` and `JdbcClient.query(Class)` need per-type metadata (R4):
- property names with their underscore forms;
- setters, for beans;
- constructor parameter names, for records and data classes;
- typed conversion from a column value.

They read `T`'s `flint.engine.aot.Descriptor` instead of reflecting. Each is a one-line template over an erased engine that takes the descriptor, so one copy of the mapping code serves every `T`. Column values pass through `flint.engine.aot.Any`, and the conversions follow Spring's `JdbcUtils.getResultSetValue`, then the `ConversionService` where framework-core provides it.

## What this needs from other sessions

| From | Needs |
| --- | --- |
| flint-aot | `Descriptor` with properties, setters, constructor parameters and annotations; `Any` with the `long`, `double`, `bool`, `string`, `ubyte[]` and `null` conversions; transactional proxy-subclass generation calling `invokeWithinTransaction!R` |
| framework-core | `flint.core.NestedRuntimeException`, `flint.java.lang.RuntimeException`, `flint.java.util` façades (`List`, `Map`, `Optional`), `ConversionService`; who owns `flint:java` (this note adds `flint.java.sql` and `flint.javax.sql` there unless told otherwise); bean registration of `@Bean JdbcTemplate`, `DataSource` and `PlatformTransactionManager` for the sample |
| engine rename | `flint.sql` → `flint.engine.sql` (DUB `flint:engine-sql`), plus the SQLSTATE accessor above |

## Upstream tests

The upstream tests are ported class by class, with Mockito mocks replaced by fakes of `flint.java.sql`. They are counted against the upstream totals in `docs/spring/phase1/data-access-tests.md`:

| Upstream test class (upstream `@Test` count) | Package |
| --- | --- |
| `JdbcTemplateTests` (56), `JdbcTemplateQueryTests` (28), `RowMapperTests` (5), `SingleColumnRowMapperTests` (3), `BeanPropertyRowMapperTests` (15), `DataClassRowMapperTests` (7) | `jdbc.core` |
| `NamedParameterJdbcTemplateTests` (23), `NamedParameterUtilsTests` (26), `MapSqlParameterSourceTests` (6), `BeanPropertySqlParameterSourceTests` (10) | `jdbc.core.namedparam` |
| `JdbcClientIndexedParameterTests` (18), `JdbcClientNamedParameterTests` (21), `SimpleJdbcInsertTests` (12) | `jdbc.core.simple` |
| `KeyHolderTests` (8), `SQLExceptionSubclassTranslatorTests` (3), `SQLStateSQLExceptionTranslatorTests` (21), `SQLErrorCodeSQLExceptionTranslatorTests` (8) | `jdbc.support` |
| `DataSourceTransactionManagerTests` (56), `DataSourceUtilsTests` (2), `DriverManagerDataSourceTests` (4) | `jdbc.datasource` |
| `TransactionSupportTests` (25, which covers `TransactionTemplate`) | `transaction.support` |
| `RuleBasedTransactionAttributeTests` (9), `RollbackRuleAttributeTests` (14), `TransactionAttributeSourceTests` (5), `TransactionInterceptorTests` (12), `AbstractTransactionAspectTests` (19) | `transaction.interceptor` |
| `AnnotationTransactionAttributeSourceTests` (22), `AnnotationTransactionInterceptorTests` (26), `EnableTransactionManagementTests` (18) | `transaction.annotation` |
| `DataAccessUtilsTests` (12) | `dao.support` |

That is 494 of the 1,261 upstream tests (spring-jdbc 882, spring-tx 379). The remainder belongs to the deferred and excluded packages.

Each Flint test names its upstream test method. Live suites run the same templates against SQLite and the pinned PostgreSQL peer on both compilers.

## The sample

The guide uses H2. Flint runs it on SQLite in-memory (`jdbc:sqlite::memory:`) and on PostgreSQL. Its two H2-only statements change:
- `DROP TABLE customers IF EXISTS` becomes `DROP TABLE IF EXISTS customers`;
- `id SERIAL` becomes `id INTEGER PRIMARY KEY` on SQLite.

The Java code otherwise maps one to one:
- `batchUpdate(sql, List<Object[]>)`;
- `query(sql, (rs, rowNum) -> new Customer(...), "Josh")` as a D delegate (R9).

A `@Transactional` service around the inserts proves commit, and a test proves rollback on a runtime exception.

## Order of work

Each step lands, tested on DMD and LDC, before the next starts:
1. Engine: the SQLSTATE accessor; the Flint JDBC driver and the `flint.java.sql` subset.
2. `flint.dao` and the SQL exception translators.
3. `flint.transaction` core, `TransactionSynchronizationManager` on `FiberLocal`, `TransactionTemplate` and `DataSourceTransactionManager`.
4. `JdbcTemplate`, the row mappers and extractors, `KeyHolder`.
5. `NamedParameterJdbcTemplate`, `JdbcClient` and `SimpleJdbcInsert`.
6. `@Transactional`, with flint-aot's proxies.
7. `HikariDataSource`, and Boot's `flint.datasource.*` binding (with the Boot session).
8. The gs-relational-data-access data layer, the `api/mapping.json` classification and the test counts.
