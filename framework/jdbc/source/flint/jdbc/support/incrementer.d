/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from spring-framework v7.1.0: spring-jdbc/src/main/java/org/springframework/jdbc/support/incrementer/
// AbstractColumnMaxValueIncrementer.java, AbstractDataFieldMaxValueIncrementer.java,
// AbstractIdentityColumnMaxValueIncrementer.java, AbstractSequenceMaxValueIncrementer.java,
// DataFieldMaxValueIncrementer.java, Db2LuwMaxValueIncrementer.java, Db2MainframeMaxValueIncrementer.java,
// DerbyMaxValueIncrementer.java, H2SequenceMaxValueIncrementer.java, HanaSequenceMaxValueIncrementer.java,
// HsqlMaxValueIncrementer.java, HsqlSequenceMaxValueIncrementer.java, MariaDBSequenceMaxValueIncrementer.java,
// MySQLIdentityColumnMaxValueIncrementer.java, MySQLMaxValueIncrementer.java,
// OracleSequenceMaxValueIncrementer.java, PostgresSequenceMaxValueIncrementer.java,
// SqlServerMaxValueIncrementer.java, SqlServerSequenceMaxValueIncrementer.java, SqliteMaxValueIncrementer.java,
// SybaseAnywhereMaxValueIncrementer.java, SybaseMaxValueIncrementer.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.jdbc.support.incrementer`.
module flint.jdbc.support.incrementer;

import flint.javax.sql : DataSource;
import flint.beans.factory : InitializingBean;
import std.typecons : Nullable;
import flint.java.util : Set;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.AbstractColumnMaxValueIncrementer sha256:a493a15f28304a66e079335837052aa9dad1f68c4c169aaa12211a478294cc0e
/// Abstract base class for `DataFieldMaxValueIncrementer` implementations that use a column in a custom sequence table.
/// Subclasses need to provide the specific handling of that table in their `getNextKey()` implementation.
abstract class AbstractColumnMaxValueIncrementer : AbstractDataFieldMaxValueIncrementer
{
    private Nullable!string columnName;
    private int cacheSize = 1;

    /// Default constructor for bean property style usage.
    this()
    {
    }

    /// Set the name of the column in the sequence table.
    void setColumnName(Nullable!string columnName)
    {
        this.columnName = columnName;
    }

    /// Return the name of the column in the sequence table.
    Nullable!string getColumnName()
    {
        return this.columnName;
    }

    /// Set the number of buffered keys.
    void setCacheSize(int cacheSize)
    {
        this.cacheSize = cacheSize;
    }

    /// Return the number of buffered keys.
    int getCacheSize()
    {
        return this.cacheSize;
    }

    // port:pending org.springframework.jdbc.support.incrementer.AbstractColumnMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractColumnMaxValueIncrementer#afterPropertiesSet(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer sha256:e8b6dfe73bb98d7e04ef073c96ceb87b78d64b879c831aef37d9df3c07a0922f
/// Base implementation of `DataFieldMaxValueIncrementer` that delegates to a single `getNextKey` template method that
/// returns a `long`. Uses longs for String values, padding with zeroes if required.
abstract class AbstractDataFieldMaxValueIncrementer : DataFieldMaxValueIncrementer, InitializingBean
{
    private DataSource dataSource;
    private Nullable!string incrementerName;
    /// The length to which a string result should be prepended with zeroes.
    protected int paddingLength = 0;

    /// Default constructor for bean property style usage.
    this()
    {
    }

    /// Set the data source to retrieve the value from.
    void setDataSource(DataSource dataSource)
    {
        this.dataSource = dataSource;
    }

    /// Return the data source to retrieve the value from.
    DataSource getDataSource()
    {
        return this.dataSource;
    }

    /// Set the name of the sequence/table.
    void setIncrementerName(Nullable!string incrementerName)
    {
        this.incrementerName = incrementerName;
    }

    /// Return the name of the sequence/table.
    Nullable!string getIncrementerName()
    {
        return this.incrementerName;
    }

    /// Set the padding length, i.e. the length to which a string result should be prepended with zeroes.
    void setPaddingLength(int paddingLength)
    {
        this.paddingLength = paddingLength;
    }

    /// Return the padding length for String values.
    int getPaddingLength()
    {
        return this.paddingLength;
    }

    /// Determine the next key to use, as a long.
    protected abstract long getNextKey();

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#afterPropertiesSet(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#nextIntValue(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#nextLongValue(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#nextStringValue(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractDataFieldMaxValueIncrementer#obtainDataSource(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.AbstractIdentityColumnMaxValueIncrementer sha256:15f99dcd06c7a529760dbd7e823866261bde94e309169d0292624efc8fa3c6b7
/// Abstract base class for `DataFieldMaxValueIncrementer` implementations which are based on identity columns in a
/// sequence-like table.
abstract class AbstractIdentityColumnMaxValueIncrementer : AbstractColumnMaxValueIncrementer
{
    private bool deleteSpecificValues = false;
    private long[] valueCache;
    private int nextValueIndex = -1;

    /// Default constructor for bean property style usage.
    this()
    {
    }

    /// Specify whether to delete the entire range below the current maximum key value (`false` - the default), or the
    /// specifically generated values (`true`). The former mode will use a where range clause whereas the latter will
    /// use an in clause starting with the lowest value minus 1, just preserving the maximum value.
    void setDeleteSpecificValues(bool deleteSpecificValues)
    {
        this.deleteSpecificValues = deleteSpecificValues;
    }

    /// Return whether to delete the entire range below the current maximum key value (`false` - the default), or the
    /// specifically generated values (`true`).
    bool isDeleteSpecificValues()
    {
        return this.deleteSpecificValues;
    }

    /// Statement to use to increment the "sequence" value.
    protected abstract string getIncrementStatement();

    /// Statement to use to obtain the current identity value.
    protected abstract string getIdentityStatement();

    // port:pending org.springframework.jdbc.support.incrementer.AbstractIdentityColumnMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractIdentityColumnMaxValueIncrementer#getDeleteStatement(long): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractIdentityColumnMaxValueIncrementer#getNextKey(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.AbstractSequenceMaxValueIncrementer sha256:3312dade00535a3db41220de77dcd542b4e2d5d3bf898673857513c19df03f02
/// Abstract base class for `DataFieldMaxValueIncrementer` implementations that use a database sequence. Subclasses need
/// to provide the database-specific SQL to use.
abstract class AbstractSequenceMaxValueIncrementer : AbstractDataFieldMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    /// Return the database-specific query to use for retrieving a sequence value. The provided SQL is supposed to
    /// result in a single row with a single column that allows for extracting a `long` value.
    protected abstract string getSequenceQuery();

    // port:pending org.springframework.jdbc.support.incrementer.AbstractSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.AbstractSequenceMaxValueIncrementer#getNextKey(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.DataFieldMaxValueIncrementer sha256:8c8534aa3aa26dde95870fe0991f23aa004be70b5c0d85ec396a43dde22c7ac0
/// Interface that defines contract of incrementing any data store field's maximum value. Works much like a sequence
/// number generator. Typical implementations may use standard SQL, native RDBMS sequences or Stored Procedures to do
/// the job.
interface DataFieldMaxValueIncrementer
{
    /// Increment the data store field's max value as int.
    int nextIntValue();

    /// Increment the data store field's max value as long.
    long nextLongValue();

    /// Increment the data store field's max value as String.
    string nextStringValue();
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.Db2LuwMaxValueIncrementer sha256:cb229585cca9bc2d2362c83c2ce45d3f39c201472db6c1ebc9a4e69357ea62d8
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given sequence on DB2 LUW (for Linux, Unix and
/// Windows). Thanks to Mark MacMahon for the suggestion!
class Db2LuwMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.Db2LuwMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.Db2LuwMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.Db2MainframeMaxValueIncrementer sha256:524c02ff98d651b32a44a9958c3795b728c0a83a25fdee33641f4d05bcb8e908
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given sequence on DB2 for the mainframe (z/OS,
/// DB2/390, DB2/400). Thanks to Jens Eickmeyer for the suggestion!
class Db2MainframeMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.Db2MainframeMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.Db2MainframeMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer sha256:f44bf43d47745a57871c4e2db68f5d056ebd261b9bfc3a7dd7a01b06a7356f54
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given Derby table with the equivalent of an
/// auto-increment column. Note: If you use this class, your Derby key column should NOT be defined as an IDENTITY
/// column, as the sequence table does the job. The sequence is kept in a table. There should be one sequence table per
/// table that needs an auto-generated key. Derby requires an additional column to be used for the insert since it is
/// impossible to insert a null into the identity column and have the value generated. This is solved by providing the
/// name of a dummy column that also must be created in the sequence table. Example: <pre class="code">create table tab
/// (id int not null primary key, text varchar(100)); create table tab_sequence (value int generated always as identity,
/// dummy char(1)); insert into tab_sequence (dummy) values(null); If "cacheSize" is set, the intermediate values are
/// served without querying the database. If the server or your application is stopped or crashes or a transaction is
/// rolled back, the unused values will never be served. The maximum hole size in numbering is consequently the value of
/// cacheSize. HINT: Since Derby supports the JDBC `getGeneratedKeys` method, it is recommended to use IDENTITY columns
/// directly in the tables and then utilize a `org.springframework.jdbc.support.KeyHolder` when calling the
/// `update(PreparedStatementCreator psc, KeyHolder generatedKeyHolder)` method of the
/// `org.springframework.jdbc.core.JdbcTemplate`. Thanks to Endre Stolsvik for the suggestion!
deprecated("since 7.1") class DerbyMaxValueIncrementer : AbstractIdentityColumnMaxValueIncrementer
{
    /// The default for dummy name.
    private enum string DEFAULT_DUMMY_NAME = "dummy";
    private string dummyName;

    @disable this();

    /// Set the name of the dummy column.
    void setDummyName(string dummyName)
    {
        this.dummyName = dummyName;
    }

    /// Return the name of the dummy column.
    string getDummyName()
    {
        return this.dummyName;
    }

    // port:pending org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer#<init>(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer#<init>(DataSource,String,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer#getIdentityStatement(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.DerbyMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.H2SequenceMaxValueIncrementer sha256:e38f7e1da226d830538986aaf149887aa7c5d9cc5fba039e5b47bbeb4ca51dec
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given H2 sequence.
class H2SequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.H2SequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.H2SequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.HanaSequenceMaxValueIncrementer sha256:8694ff05e8b4eea1ae48cd0b1bc8e7cd612e3f3fa9b2637f966273a10265543f
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given SAP HANA sequence.
class HanaSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.HanaSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.HanaSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.HsqlMaxValueIncrementer sha256:bb165c743a1f1a4310ddfb4e8210c265dd1303717e9cd2189e1185b3331cb0fe
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given HSQL table with the equivalent of an
/// auto-increment column. Note: If you use this class, your HSQL key column should NOT be auto-increment, as the
/// sequence table does the job. The sequence is kept in a table. There should be one sequence table per table that
/// needs an auto-generated key. Example: <pre class="code">create table tab (id int not null primary key, text
/// varchar(100)); create table tab_sequence (value identity); insert into tab_sequence values(0); If "cacheSize" is
/// set, the intermediate values are served without querying the database. If the server or your application is stopped
/// or crashes or a transaction is rolled back, the unused values will never be served. The maximum hole size in
/// numbering is consequently the value of cacheSize. NOTE: HSQL now supports sequences and you should consider using
/// them instead: `HsqlSequenceMaxValueIncrementer`
class HsqlMaxValueIncrementer : AbstractIdentityColumnMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.HsqlMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.HsqlMaxValueIncrementer#getIdentityStatement(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.HsqlMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.HsqlSequenceMaxValueIncrementer sha256:fc14acf73151abccaf0c5ff86504c00eb435b67f6b8968d9a619cef4f34b9e13
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given HSQL sequence. Thanks to Guillaume Bilodeau
/// for the suggestion! NOTE: This is an alternative to using a regular table to support generating unique keys that was
/// necessary in previous versions of HSQL.
class HsqlSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.HsqlSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.HsqlSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.MariaDBSequenceMaxValueIncrementer sha256:2324fa4b253b1f10a785183da1a596b1773301cfd365ad088626292a813d686c
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given MariaDB sequence.
class MariaDBSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.MariaDBSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.MariaDBSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.MySQLIdentityColumnMaxValueIncrementer sha256:338f244240b1403068c971df181db2549fb707288474e37f231ffe8007419bf1
/// `DataFieldMaxValueIncrementer` that increments the maximum counter value of an auto-increment column of a given
/// MySQL table. The sequence is kept in a table. The storage engine used by the sequence table must be InnoDB in MySQL
/// 8.0 or later since the current maximum auto-increment counter is required to be persisted across restarts of the
/// database server. Example: <pre class="code"> create table tab_sequence (`id` bigint unsigned primary key
/// auto_increment); If `cacheSize` is set, the intermediate values are served without querying the database. If the
/// server or your application is stopped or crashes or a transaction is rolled back, the unused values will never be
/// served. The maximum hole size in numbering is consequently the value of `cacheSize`.
class MySQLIdentityColumnMaxValueIncrementer : AbstractIdentityColumnMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.MySQLIdentityColumnMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.MySQLIdentityColumnMaxValueIncrementer#getIdentityStatement(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.MySQLIdentityColumnMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.MySQLMaxValueIncrementer sha256:10535d39a15e0992cb29131c1687f2c3c0765d1d6f98446335ce8abe4306f761
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given MySQL table with the equivalent of an
/// auto-increment column. Note: If you use this class, your MySQL key column should NOT be auto-increment, as the
/// sequence table does the job. The sequence is kept in a table; there should be one sequence table per table that
/// needs an auto-generated key. The storage engine used by the sequence table can be MYISAM or INNODB since the
/// sequences are allocated using a separate connection without being affected by any other transactions that might be
/// in progress. Example: <pre class="code"> create table tab (id int unsigned not null primary key, text varchar(100));
/// create table tab_sequence (value int not null); insert into tab_sequence values(0); If `cacheSize` is set, the
/// intermediate values are served without querying the database. If the server or your application is stopped or
/// crashes or a transaction is rolled back, the unused values will never be served. The maximum hole size in numbering
/// is consequently the value of `cacheSize`. It is possible to avoid acquiring a new connection for the incrementer by
/// setting the "useNewConnection" property to false. In this case you MUST use a non-transactional storage engine like
/// MYISAM when defining the incrementer table. Note that `MySQLMaxValueIncrementer` is compatible with <a
/// href="https://dev.mysql.com/doc/refman/8.0/en/mysql-tips.html#safe-updates">MySQL safe updates mode</a>.
class MySQLMaxValueIncrementer : AbstractColumnMaxValueIncrementer
{
    /// The SQL string for retrieving the new sequence value.
    private enum string VALUE_SQL = "select last_insert_id()";
    private long nextId = 0;
    private long maxId = 0;
    private bool useNewConnection = true;

    /// Default constructor for bean property style usage.
    this()
    {
    }

    /// Set whether to use a new connection for the incrementer. `true` is necessary to support transactional storage
    /// engines, using an isolated separate transaction for the increment operation. `false` is sufficient if the
    /// storage engine of the sequence table is non-transactional (like MYISAM), avoiding the effort of acquiring an
    /// extra `Connection` for the increment operation. Default is `true`.
    void setUseNewConnection(bool useNewConnection)
    {
        this.useNewConnection = useNewConnection;
    }

    // port:pending org.springframework.jdbc.support.incrementer.MySQLMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.MySQLMaxValueIncrementer#getNextKey(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.OracleSequenceMaxValueIncrementer sha256:8f14be6145e1d24d33942cba6d637f9b89d5909f2ba259aef82038f0a77157e7
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given Oracle sequence.
class OracleSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.OracleSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.OracleSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.PostgresSequenceMaxValueIncrementer sha256:317315c47d9bce530d16fd357ae33f291579bf526357e0309bd52f9395abef84
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given PostgreSQL sequence. Thanks to Tomislav
/// Urban for the suggestion!
class PostgresSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.PostgresSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.PostgresSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.SqlServerMaxValueIncrementer sha256:0fa2b9efcc015bc05a69ee8879a7984899098529c4bef3d06e9d64c16bdb378b
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given SQL Server table with the equivalent of
/// an auto-increment column. Note: If you use this class, your table key column should NOT be defined as an IDENTITY
/// column, as the sequence table does the job. This class is intended to be used with Microsoft SQL Server. The
/// sequence is kept in a table. There should be one sequence table per table that needs an auto-generated key. Example:
/// <pre class="code">create table tab (id int not null primary key, text varchar(100)) create table tab_sequence (id
/// bigint identity) insert into tab_sequence default values If "cacheSize" is set, the intermediate values are served
/// without querying the database. If the server or your application is stopped or crashes or a transaction is rolled
/// back, the unused values will never be served. The maximum hole size in numbering is consequently the value of
/// cacheSize. HINT: Since Microsoft SQL Server supports the JDBC `getGeneratedKeys` method, it is recommended to use
/// IDENTITY columns directly in the tables and then use a `org.springframework.jdbc.core.simple.SimpleJdbcInsert` or a
/// `org.springframework.jdbc.support.KeyHolder` when calling the `update(PreparedStatementCreator psc, KeyHolder
/// generatedKeyHolder)` method of the `org.springframework.jdbc.core.JdbcTemplate`. Thanks to Preben Nilsson for the
/// suggestion!
class SqlServerMaxValueIncrementer : AbstractIdentityColumnMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.SqlServerMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SqlServerMaxValueIncrementer#getIdentityStatement(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SqlServerMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.SqlServerSequenceMaxValueIncrementer sha256:f938a050f0c52e01bd29d4df0de0296355db5b040b9d503131b863e9d65b7a86
/// `DataFieldMaxValueIncrementer` that retrieves the next value of a given SQL Server sequence.
class SqlServerSequenceMaxValueIncrementer : AbstractSequenceMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.SqlServerSequenceMaxValueIncrementer#<init>(DataSource,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SqlServerSequenceMaxValueIncrementer#getSequenceQuery(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.SqliteMaxValueIncrementer sha256:79f135379e24ed7aaaf3dda462aadbceb0904c854abd14020e1b84a509911696
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given table with the equivalent of an
/// auto-increment column, using an SQLite `select max(rowid)` query.
class SqliteMaxValueIncrementer : AbstractColumnMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.SqliteMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SqliteMaxValueIncrementer#getNextKey(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.SybaseAnywhereMaxValueIncrementer sha256:6991be4f79c6c62fb871b99d4261642b37f1abb8ddda2675dfd96c1032b6cdfc
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given Sybase table with the equivalent of an
/// auto-increment column. Note: If you use this class, your table key column should NOT be defined as an IDENTITY
/// column, as the sequence table does the job. This class is intended to be used with Sybase Anywhere. The sequence is
/// kept in a table. There should be one sequence table per table that needs an auto-generated key. Example: <pre
/// class="code">create table tab (id int not null primary key, text varchar(100)) create table tab_sequence (id bigint
/// identity) insert into tab_sequence values(DEFAULT) If "cacheSize" is set, the intermediate values are served without
/// querying the database. If the server or your application is stopped or crashes or a transaction is rolled back, the
/// unused values will never be served. The maximum hole size in numbering is consequently the value of cacheSize. HINT:
/// Since Sybase Anywhere supports the JDBC `getGeneratedKeys` method, it is recommended to use IDENTITY columns
/// directly in the tables and then use a `org.springframework.jdbc.core.simple.SimpleJdbcInsert` or use a
/// `org.springframework.jdbc.support.KeyHolder` when calling the `update(PreparedStatementCreator psc, KeyHolder
/// generatedKeyHolder)` method of the `org.springframework.jdbc.core.JdbcTemplate`. Thanks to Tarald Saxi Stormark for
/// the suggestion!
class SybaseAnywhereMaxValueIncrementer : SybaseMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.SybaseAnywhereMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SybaseAnywhereMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.jdbc.support.incrementer.SybaseMaxValueIncrementer sha256:c1bf364bd0350ca843abf71834c805fae0156a4a44bea26a5738eba80099fb7f
/// `DataFieldMaxValueIncrementer` that increments the maximum value of a given Sybase table with the equivalent of an
/// auto-increment column. Note: If you use this class, your table key column should NOT be defined as an IDENTITY
/// column, as the sequence table does the job. This class is intended to be used with Sybase Adaptive Server. The
/// sequence is kept in a table. There should be one sequence table per table that needs an auto-generated key. Example:
/// <pre class="code">create table tab (id int not null primary key, text varchar(100)) create table tab_sequence (id
/// bigint identity) insert into tab_sequence values() If "cacheSize" is set, the intermediate values are served without
/// querying the database. If the server or your application is stopped or crashes or a transaction is rolled back, the
/// unused values will never be served. The maximum hole size in numbering is consequently the value of cacheSize. HINT:
/// Since Sybase Adaptive Server supports the JDBC `getGeneratedKeys` method, it is recommended to use IDENTITY columns
/// directly in the tables and then use a `org.springframework.jdbc.core.simple.SimpleJdbcInsert` or use a
/// `org.springframework.jdbc.support.KeyHolder` when calling the `update(PreparedStatementCreator psc, KeyHolder
/// generatedKeyHolder)` method of the `org.springframework.jdbc.core.JdbcTemplate`. Thanks to Yinwei Liu for the
/// suggestion!
class SybaseMaxValueIncrementer : AbstractIdentityColumnMaxValueIncrementer
{
    /// Default constructor for bean property style usage.
    this()
    {
    }

    // port:pending org.springframework.jdbc.support.incrementer.SybaseMaxValueIncrementer#<init>(DataSource,String,String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SybaseMaxValueIncrementer#getIdentityStatement(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.jdbc.support.incrementer.SybaseMaxValueIncrementer#getIncrementStatement(): the body is not written yet (--strip-pending)
}
// port:end
