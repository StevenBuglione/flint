/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module jpa_generated_insert;

import core.memory : GC;
import flint.arena : Error, Result, Status;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping;
import flint.engine.jpa.identity : EntityIdentity, IdentitySlot;
import flint.engine.jpa.loaded_state : ManagedSnapshotSlot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.parameter_binding : InsertPlan, ParameterBinding, executeIdentityInsert,
    executeManagedInsert, planIdentityInsert, planInsert, readGeneratedIntegerKey;
import flint.engine.jpa.snapshot : AttributeSnapshot;
import flint.engine.jpa.update : InsertAction, InsertInputs, MutationActions, MutationPhase,
    MutationPlans, flushManagedMutations;
import flint.jakarta.persistence : GenerationType;
import flint.java.sql : Connection, PreparedStatement, ResultSet, Types;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcTemplate;
import std.typecons : BlackHole;

@safe:

private final class GeneratedOwner
{
    long id;
    string name;
    uint reads;
    InsertContext retireOnRead;
}

private alias AttrResult = Result!AttributeValue;

private AttrResult readId(Object entity) nothrow @nogc
{
    return AttrResult(AttributeValue(AttributeKind.integer, (cast(GeneratedOwner) entity).id));
}

private AttrResult readName(Object entity) nothrow @nogc
{
    auto owner = cast(GeneratedOwner) entity;
    ++owner.reads;
    if (auto context = owner.retireOnRead)
    {
        owner.retireOnRead = null;
        context.managed.clear();
    }
    return AttrResult(AttributeValue(kind: AttributeKind.text, text: owner.name));
}

private void writeId(Object entity, const ref AttributeValue value)
{
    (cast(GeneratedOwner) entity).id = value.integer;
}

private void writeName(Object entity, const ref AttributeValue value)
{
    (cast(GeneratedOwner) entity).name = value.text;
}

private enum ownerType = "jpa_generated_insert.GeneratedOwner";
private immutable EntityMapping mapping = EntityMapping("GeneratedOwner", ownerType, "jpa_identity_probe",
        [
            AttributeMapping(ordinal: 0, name: "id", column: "Owner Key", kind: AttributeKind.integer,
            read: &readId, write: &writeId, updatable: false, sqlType: Types.BIGINT),
            AttributeMapping(ordinal: 1, name: "name", column: "name", kind: AttributeKind.text,
            read: &readName, write: &writeName, sqlType: Types.VARCHAR)
], construct: () => new GeneratedOwner, isExactType: (scope const TypeInfo_Class candidate) => candidate is typeid(
            GeneratedOwner), idOrdinals: [0], generatesId: true, generationStrategy: GenerationType.IDENTITY);

private enum insertSql = "insert into jpa_identity_probe (name) values (?)";
private immutable ParameterBinding[] bindings = [ParameterBinding(1, 1)];

private void verifyKeyCursor(Connection connection)
{
    {
        auto statement = connection.prepareStatement(insertSql, ["Owner Key"]);
        scope (exit)
            statement.close();
        statement.setString(1, "Raw key");
        assert(statement.executeUpdate() == 1);
        auto keys = statement.getGeneratedKeys();
        scope (exit)
            keys.close();
        const key = readGeneratedIntegerKey(keys);
        assert(key.ok && key.value == 9_000_000_001);
    }
    {
        auto statement = connection.prepareStatement(insertSql, ["name"]);
        scope (exit)
            statement.close();
        statement.setString(1, "42");
        assert(statement.executeUpdate() == 1);
        auto keys = statement.getGeneratedKeys();
        scope (exit)
            keys.close();
        assert(readGeneratedIntegerKey(keys).error.code == Status.invalidArgument);
    }
    {
        auto statement = connection.prepareStatement(insertSql ~ ", ('Another')", ["Owner Key"]);
        scope (exit)
            statement.close();
        statement.setString(1, "Multiple");
        assert(statement.executeUpdate() == 2);
        auto keys = statement.getGeneratedKeys();
        scope (exit)
            keys.close();
        assert(readGeneratedIntegerKey(keys).error.code == Status.ioError);
    }
}

private long countRows(Connection connection)
{
    auto statement = connection.prepareStatement("select count(*) from jpa_identity_probe");
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());
    return rows.getLong(1);
}

/// Links named JDBC keys and staged managed publication on the pinned PostgreSQL peer.
void verifyGeneratedInserts(DataSource dataSource, JdbcTemplate jdbc)
{
    jdbc.execute("create table jpa_identity_probe (\"Owner Key\" bigint generated always as identity "
            ~ "(start with 9000000001) primary key, name text not null)");
    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    connection.setAutoCommit(false);
    scope (exit)
        connection.rollback();
    verifyKeyCursor(connection);
    connection.rollback();
    assert(countRows(connection) == 0);

    const planned = planIdentityInsert(&mapping, insertSql, bindings);
    const multiple = planIdentityInsert(&mapping, insertSql ~ ", ('Another')", bindings);
    assert(planned.ok && multiple.ok);
    static immutable ParameterBinding[] withId = [ParameterBinding(1, 1), ParameterBinding(0, 2)];
    assert(planIdentityInsert(&mapping, insertSql, withId).error.code == Status.invalidArgument);
    IdentitySlot[1] identities;
    Object[1] roots;
    auto fields = new AttributeSnapshot[2];
    auto bytes = new ubyte[16];
    ManagedSnapshotSlot[1] snapshots = [ManagedSnapshotSlot(fields, bytes)];
    Error error;
    scope managed = ManagedEntities(identities[], roots[], error, snapshots[]);
    assert(error.code == Status.ok);

    auto owner = new GeneratedOwner;
    owner.name = "Generated";
    auto values = new AttributeValue[2];
    string[] columns = ["Owner Key"];
    const rejected = executeIdentityInsert(multiple.value, connection, managed, 0, owner, values, columns);
    assert(rejected.error.code == Status.ioError && owner.id == 0);
    assert(countRows(connection) == 2);
    connection.rollback();

    owner.name = "Snapshot payload exceeds the reserved bytes";
    const exhausted = executeIdentityInsert(planned.value, connection, managed, 0, owner, values, columns);
    assert(exhausted.error.code == Status.outOfMemory && exhausted.error.offset == 1);
    assert(owner.id == 0 && countRows(connection) == 1);
    connection.rollback();
    assert(countRows(connection) == 0);

    owner.name = "Generated";
    const reads = owner.reads;
    const inserted = executeIdentityInsert(planned.value, connection, managed, 0, owner, values, columns);
    assert(inserted.ok && inserted.value > int.max && owner.id == inserted.value);
    const key = EntityIdentity(0, inserted.value);
    assert(managed.find(key).value is owner && owner.reads == reads + 1);
    assert(countRows(connection) == 1);
    uint[1] ordinals;
    const dirty = managed.dirty(key, ordinals[]);
    assert(dirty.ok && dirty.value == 0);
    const blocked = executeIdentityInsert(planned.value, connection, managed, 0, new GeneratedOwner, values, columns);
    assert(blocked.error.code == Status.resourceExhausted);
    assert(countRows(connection) == 1);
    connection.rollback();
    managed.clear();
    assert(managed.find(key).error.code == Status.notFound && countRows(connection) == 0);

    auto scheduled = new GeneratedOwner;
    scheduled.name = "Scheduled";
    auto keyColumn = new string[1];
    const schedule = MutationActions(null, null, [InsertAction(0, 0, EntityIdentity(0, 0))]);
    const layouts = MutationPlans(null, null, [planned.value]);
    const missingRoot = flushManagedMutations(connection, managed, layouts, schedule, ordinals[],
            values, InsertInputs(null, keyColumn));
    assert(missingRoot.error.code == Status.invalidArgument && missingRoot.value.failedPhase == MutationPhase.inserts);
    assert(missingRoot.value.failedAction == 0 && countRows(connection) == 0);
    const missingColumn = flushManagedMutations(connection, managed, layouts, schedule, ordinals[],
            values, InsertInputs([scheduled]));
    assert(missingColumn.error.code == Status.invalidArgument && countRows(connection) == 0);
    const result = flushManagedMutations(connection, managed, layouts, schedule, ordinals[],
            values, InsertInputs([scheduled], keyColumn));
    assert(result.ok && result.value.inserted == 1 && keyColumn[0] is null);
    const scheduledKey = EntityIdentity(0, scheduled.id);
    assert(managed.find(scheduledKey).value is scheduled && countRows(connection) == 1);
    const repeated = flushManagedMutations(connection, managed, layouts, schedule, ordinals[],
            values, InsertInputs([scheduled], keyColumn));
    assert(repeated.error.code == Status.conflict && repeated.value.inserted == 0 && countRows(connection) == 1);
    connection.rollback();
    managed.clear();
    assert(managed.find(scheduledKey).error.code == Status.notFound);
    verifyRetiredInserts(connection, planned.value);
}

private final class InsertContext
{
    private IdentitySlot[1] slots;
    private Object[1] roots;
    private ManagedSnapshotSlot[1] snapshots;
    ManagedEntities managed;
    uint closedStatements;

    this()
    {
        snapshots = [ManagedSnapshotSlot(new AttributeSnapshot[2], new ubyte[16])];
        Error error;
        managed = ManagedEntities(slots[], roots[], error, snapshots[]);
        assert(error.code == Status.ok);
    }
}

private enum RetireAt
{
    capture,
    bind,
    close,
}

private final class RetiringStatement : BlackHole!PreparedStatement
{
    private PreparedStatement statement;
    private InsertContext context;
    private RetireAt phase;

    this(PreparedStatement statement, InsertContext context, RetireAt phase)
    {
        this.statement = statement;
        this.context = context;
        this.phase = phase;
    }

    override void setLong(int slot, long value)
    {
        statement.setLong(slot, value);
    }

    override void setString(int slot, string value)
    {
        statement.setString(slot, value);
        if (phase == RetireAt.bind)
            context.managed.clear();
    }

    override int executeUpdate()
    {
        return statement.executeUpdate();
    }

    override ResultSet getGeneratedKeys()
    {
        return statement.getGeneratedKeys();
    }

    override void close()
    {
        statement.close();
        ++context.closedStatements;
        if (phase == RetireAt.close)
            context.managed.clear();
    }
}

private final class RetiringConnection : BlackHole!Connection
{
    private Connection connection;
    private InsertContext context;
    private RetireAt phase;

    this(Connection connection, InsertContext context, RetireAt phase)
    {
        this.connection = connection;
        this.context = context;
        this.phase = phase;
    }

    override bool getAutoCommit()
    {
        return connection.getAutoCommit();
    }

    override PreparedStatement prepareStatement(string sql)
    {
        return new RetiringStatement(connection.prepareStatement(sql), context, phase);
    }

    override PreparedStatement prepareStatement(string sql, string[] columns)
    {
        return new RetiringStatement(connection.prepareStatement(sql, columns), context, phase);
    }
}

private immutable EntityMapping assignedMapping = () {
    EntityMapping result = mapping;
    result.generatesId = false;
    result.generationStrategy = GenerationType.AUTO;
    return result;
}();

private void verifyRetiredInserts(Connection connection, const ref InsertPlan generatedPlan)
{
    enum assignedSql = "insert into jpa_identity_probe (\"Owner Key\", name) overriding system value values (?, ?)";
    static immutable ParameterBinding[] assignedBindings = [
        ParameterBinding(0, 1), ParameterBinding(1, 2)
    ];
    const assigned = planInsert(&assignedMapping, assignedSql, assignedBindings);
    assert(assigned.ok);
    foreach (phase; [RetireAt.capture, RetireAt.bind, RetireAt.close])
    {
        verifyRetiredInsert(connection, generatedPlan, true, phase);
        verifyRetiredInsert(connection, assigned.value, false, phase);
    }
}

private void verifyRetiredInsert(Connection connection, const ref InsertPlan plan, bool generated, RetireAt phase)
{
    auto context = new InsertContext;
    scope (exit)
        context.managed.clear();
    auto owner = new GeneratedOwner;
    owner.name = "Retired";
    const identifier = generated ? 0L : 7L;
    owner.id = identifier;
    auto writing = connection;
    if (phase == RetireAt.capture)
        owner.retireOnRead = context;
    else
        writing = new RetiringConnection(connection, context, phase);
    auto values = new AttributeValue[2];
    string[] columns = ["Owner Key"];

    const allocated = GC.stats().allocatedInCurrentThread;
    const rejected = runInsert(plan, writing, context, owner, values, columns, generated);
    assert(rejected.code == Status.conflict && owner.id == identifier);
    if (phase == RetireAt.capture)
        assert(GC.stats().allocatedInCurrentThread == allocated, "capture retirement must stop before JDBC");
    else
        assert(context.closedStatements == 1);
    assert(context.managed.find(EntityIdentity(0, identifier)).error.code == Status.notFound);
    foreach (ref value; values)
        assert(value.kind == AttributeKind.nullValue);
    if (phase == RetireAt.close)
    {
        assert(countRows(connection) == 1);
        connection.rollback();
    }
    assert(countRows(connection) == 0, "retired reservation still inserted a row");

    owner.name = "Retry";
    assert(runInsert(plan, connection, context, owner, values, columns, generated).code == Status.ok);
    assert(context.managed.find(EntityIdentity(0, owner.id)).value is owner);
    assert(countRows(connection) == 1);
    connection.rollback();
}

private Error runInsert(const ref InsertPlan plan, Connection connection, InsertContext context,
        GeneratedOwner owner, AttributeValue[] values, string[] columns, bool generated)
{
    if (generated)
        return executeIdentityInsert(plan, connection, context.managed, 0, owner, values, columns).error;
    return executeManagedInsert(plan, connection, context.managed, EntityIdentity(0, owner.id), owner, values);
}
