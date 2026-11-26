/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module jpa_version_update;

import core.memory : GC;
import flint.arena : Error, Result, Status;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping, ResultBinding;
import flint.engine.jpa.delete_row : DeletePlan, executeManagedDelete, planDelete;
import flint.engine.jpa.identity : EntityIdentity, IdentitySlot;
import flint.engine.jpa.loaded_state : LoadedSnapshotPlan, ManagedSnapshotSlot, planLoadedSnapshot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.parameter_binding : InsertPlan, ParameterBinding, executeManagedInsert, planInsert;
import flint.engine.jpa.result_binding : ManagedRowMaterializationPlan, materializeManagedRow, planManagedResult;
import flint.engine.jpa.snapshot : AttributeSnapshot;
import flint.engine.jpa.update : DeleteAction, InsertAction, InsertInputs, MutationActions,
    MutationPhase, MutationPlans, UpdateAction,
    VersionBindings, executeManagedUpdate, executeVersionedUpdate, UpdatePlan,
    flushManagedMutations, flushManagedUpdate, flushManagedUpdates, planUpdate;
import flint.java.sql : Connection, PreparedStatement, SQLException, Types;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcTemplate;
import flint.jdbc.datasource : ConnectionHolder, DataSourceTransactionManager, DataSourceUtils;
import flint.transaction : TransactionDefinition, TransactionStatus, UnexpectedRollbackException;
import flint.transaction.support : TransactionSynchronization, TransactionSynchronizationManager, TransactionTemplate;
import std.typecons : BlackHole;

@safe:

private final class VersionedOwner
{
    long id;
    string name;
    long revision;
    bool rejectRevision;
    uint nameReads;
    RebindContext identifierRebind;
    RebindContext updateRebind;
    uint rebindOnNameRead;
}

private alias AttrResult = Result!AttributeValue;

private AttrResult readId(Object entity) nothrow @nogc
{
    auto owner = cast(VersionedOwner) entity;
    auto rebound = owner.identifierRebind;
    if (rebound !is null)
    {
        owner.identifierRebind = null;
        rebound.reattach();
    }
    return AttrResult(AttributeValue(AttributeKind.integer, owner.id));
}

private AttrResult readName(Object entity) nothrow @nogc
{
    auto owner = cast(VersionedOwner) entity;
    const name = owner.name;
    ++owner.nameReads;
    if (owner.updateRebind !is null && owner.nameReads == owner.rebindOnNameRead)
    {
        auto context = owner.updateRebind;
        owner.updateRebind = null;
        context.reattach();
    }
    return AttrResult(AttributeValue(kind: AttributeKind.text, text: name));
}

private AttrResult readVersion(Object entity) nothrow @nogc
{
    return AttrResult(AttributeValue(AttributeKind.integer, (cast(VersionedOwner) entity).revision));
}

private enum ownerType = "jpa_version_update.VersionedOwner";
private immutable EntityMapping mapping = EntityMapping(entityName: "VersionedOwner", typeName: ownerType,
    table: "jpa_version_probe", attributes: [
            AttributeMapping(ordinal: 0, name: "id", column: "id", kind: AttributeKind.integer,
            read: &readId, write: (Object entity, const ref AttributeValue value) {
                (cast(VersionedOwner) entity).id = value.integer;
            }, updatable: false, sqlType: Types.BIGINT),
            AttributeMapping(ordinal: 1, name: "name", column: "name", kind: AttributeKind.text,
            read: &readName, write: (Object entity, const ref AttributeValue value) {
                (cast(VersionedOwner) entity).name = value.text;
            }, sqlType: Types.VARCHAR),
            AttributeMapping(2, "revision", "version", AttributeKind.integer, &readVersion,
            sqlType: Types.BIGINT, write: (Object entity, const ref AttributeValue value) {
                auto owner = cast(VersionedOwner) entity;
                if (owner.rejectRevision)
                    throw new Exception("fixture rejects version write");
                owner.revision = value.integer;
            })
], construct: () => new VersionedOwner, isExactType: (scope const TypeInfo_Class candidate) => candidate is typeid(
            VersionedOwner), idOrdinals: [0], versionOrdinal: 2);

private enum backendPid = "select pg_backend_pid()::bigint";
private enum selectRows = "select version, name, id from jpa_version_probe order by id";
private enum ownerKey = EntityIdentity(0, 1);
private enum limitKey = EntityIdentity(0, 2);
private enum thirdKey = EntityIdentity(0, 3);
private enum updateRow = "update jpa_version_probe set version = ?, name = ? where version = ? and id = ?";
private immutable ResultBinding[] projection = [
    ResultBinding(2, 1), ResultBinding(1, 2), ResultBinding(0, 3)
];
private immutable ParameterBinding[] parameters = [ParameterBinding(1, 2)];

private void assertStored(Connection connection, string name, long revision, long identifier = 1)
{
    auto statement = connection.prepareStatement("select name, version from jpa_version_probe where id = ?");
    scope (exit)
        statement.close();
    statement.setLong(1, identifier);
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());
    assert(rows.getString(1) == name && rows.getLong(2) == revision);
}

private void loadRows(const ref ManagedRowMaterializationPlan plan, Connection connection,
        scope ref ManagedEntities managed, size_t count = 1)
{
    auto statement = connection.prepareStatement(selectRows);
    scope (exit)
        statement.close();
    auto result = statement.executeQuery();
    scope (exit)
        result.close();
    foreach (_; 0 .. count)
    {
        assert(result.next());
        const row = materializeManagedRow(plan, result, managed);
        assert(row.ok);
    }
}

/// Exercises real optimistic predicates, rollback and version exhaustion on PostgreSQL.
void verifyVersionedUpdate(DataSource dataSource, JdbcTemplate jdbc)
{
    jdbc.execute("create table jpa_version_probe (id bigint primary key, name text not null, version bigint not null)");
    jdbc.execute("insert into jpa_version_probe values (1, 'Original', 7), (2, 'Limit', 9223372036854775807)");
    const rows = planManagedResult(&mapping, projection, 0);
    const plan = planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 3));
    assert(rows.ok && plan.ok);
    assert(planUpdate(&mapping, updateRow, parameters, 4).error.code == Status.unsupported);
    assert(planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 1)).error.code == Status.invalidArgument);
    assert(planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 2)).error.code == Status.invalidArgument);

    IdentitySlot[2] identities;
    Object[2] roots;
    auto fields = new AttributeSnapshot[12];
    auto bytes = new ubyte[64];
    ManagedSnapshotSlot[2] snapshots = [
        ManagedSnapshotSlot(fields[0 .. 3], bytes[0 .. 16], fields[6 .. 9], bytes[32 .. 48]),
        ManagedSnapshotSlot(fields[3 .. 6], bytes[16 .. 32], fields[9 .. 12], bytes[48 .. 64])
    ];
    Error error;
    scope managed = ManagedEntities(identities[], roots[], error, snapshots[]);
    assert(error.code == Status.ok);

    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    connection.setAutoCommit(false);
    scope (exit)
        connection.rollback();

    loadRows(rows.value, connection, managed, 2);

    auto owner = cast(VersionedOwner) managed.find(ownerKey).value;
    auto limit = cast(VersionedOwner) managed.find(limitKey).value;
    uint[1] ordinals;
    owner.revision = 100;
    const clean = executeVersionedUpdate(plan.value, connection, managed, ownerKey, ordinals[]);
    assert(clean.ok && !clean.value.updated);
    owner.name = "Edited";
    const dirty = managed.dirty(ownerKey, ordinals[]);
    assert(dirty.ok && dirty.value == 1 && ordinals[0] == 1);
    assert(executeManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[])
            .error.code == Status.invalidArgument);
    const written = executeVersionedUpdate(plan.value, connection, managed, ownerKey, ordinals[]);
    assert(written.ok && written.value.updated && written.value.nextVersion == 8);
    assert(owner.revision == 100);
    assertStored(connection, "Edited", 8);
    connection.rollback();
    assertStored(connection, "Original", 7);

    // This uses another pool lease and commits before the older loaded snapshot writes.
    jdbc.execute("update jpa_version_probe set name = 'Winner', version = 8 where id = 1");
    const stale = executeVersionedUpdate(plan.value, connection, managed, ownerKey, ordinals[]);
    assert(stale.error.code == Status.conflict);
    assertStored(connection, "Winner", 8);
    assert(owner.revision == 100 && managed.dirty(ownerKey, ordinals[]).value == 1);

    limit.name = "Overflow";
    const overflow = executeVersionedUpdate(plan.value, connection, managed, limitKey, ordinals[]);
    assert(overflow.error.code == Status.resourceExhausted && overflow.error.offset == 2);

    assert(managed.detach(ownerKey).ok);
    loadRows(rows.value, connection, managed);
    owner = cast(VersionedOwner) managed.find(ownerKey).value;
    auto values = new AttributeValue[3];
    owner.name = "Too long for the alternate bank";
    assert(flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values[0 .. 2])
            .error.code == Status.resourceExhausted);
    const allocated = GC.stats().allocatedInCurrentThread;
    const exhausted = flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values);
    assert(exhausted.error.code == Status.outOfMemory && exhausted.error.offset == 1);
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assertStored(connection, "Winner", 8);
    assert(owner.revision == 8);

    const noRow = planUpdate(&mapping, updateRow ~ " and false", parameters, 4, VersionBindings(1, 3));
    assert(noRow.ok);
    owner.name = "Second";
    assert(flushManagedUpdate(noRow.value, connection, managed, ownerKey, ordinals[], values)
            .error.code == Status.conflict);
    const pending = managed.dirty(ownerKey, ordinals[]);
    assert(pending.ok && pending.value == 1 && ordinals[0] == 1);
    assert(owner.revision == 8);

    const reads = owner.nameReads;
    const published = flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values);
    assert(published.ok && published.value.updated && published.value.nextVersion == 9);
    assert(owner.revision == 9 && owner.nameReads == reads + 2);
    assertStored(connection, "Second", 9);
    const unchanged = flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values);
    assert(unchanged.ok && !unchanged.value.updated);

    owner.name = "Third";
    const reused = flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values);
    assert(reused.ok && reused.value.updated && owner.revision == 10);
    assertStored(connection, "Third", 10);
    foreach (ref value; values)
        assert(value.kind == AttributeKind.nullValue);

    connection.rollback();
    assert(managed.detach(ownerKey).ok);
    assert(managed.dirty(ownerKey, ordinals[]).error.code == Status.notFound);
    assertStored(connection, "Winner", 8);

    loadRows(rows.value, connection, managed);
    owner = cast(VersionedOwner) managed.find(ownerKey).value;
    owner.name = "Writer error";
    owner.rejectRevision = true;
    try
    {
        flushManagedUpdate(plan.value, connection, managed, ownerKey, ordinals[], values);
        assert(false, "version writer failure must propagate");
    }
    catch (Exception failure)
    {
        assert(failure.msg == "fixture rejects version write");
    }
    assert(owner.revision == 8);
    assert(managed.find(ownerKey).error.code == Status.notFound);
    connection.rollback();
    assertStored(connection, "Winner", 8);
    verifyUpdateRebinds(connection, plan.value, rows.value);
}

private void verifyUpdateRebinds(Connection connection, const ref UpdatePlan update,
        const ref ManagedRowMaterializationPlan readPlan)
{
    verifyUpdateCaptureRebind(connection, update, readPlan);
    verifyNestedUpdate(connection, update, readPlan, true);
    verifyNestedUpdate(connection, update, readPlan, false);
    foreach (phase; [RebindPhase.binding, RebindPhase.close])
    {
        verifyUpdateStatementRebind(connection, update, readPlan, phase, true);
        verifyUpdateStatementRebind(connection, update, readPlan, phase, false);
    }
    foreach (phase; [RebindPhase.dirty, RebindPhase.identifier, RebindPhase.autoCommit])
    {
        verifyUpdatePreflightRebind(connection, update, readPlan, phase, true);
        verifyUpdatePreflightRebind(connection, update, readPlan, phase, false);
    }
}

/// Runs real managed updates under Spring's bound JDBC transaction and completion callbacks.
void verifyTransactionalUpdates(DataSource dataSource, JdbcTemplate jdbc, DataSourceTransactionManager manager)
{
    auto transaction = new TransactionTemplate(manager);
    auto key = new Object;
    verifyManagedCommit(dataSource, jdbc, transaction, key);
    verifyManagedRollback(dataSource, transaction, key, true);
    verifyManagedRollback(dataSource, transaction, key, false);
    verifyManagedRequiresNew(dataSource, jdbc, manager, key);
    verifyManagedSuppression(dataSource, jdbc, manager, key);
    jdbc.execute("insert into jpa_version_probe values (3, 'Third row', 1)");
    verifyManagedBatch(dataSource, transaction, key, true);
    verifyManagedBatch(dataSource, transaction, key, false);
    verifyMixedRollback(dataSource, transaction, key, true);
    verifyMixedRollback(dataSource, transaction, key, false);
    verifyMixedCommit(dataSource, transaction, key);
    verifyScheduledInsertRollback(dataSource, transaction, key, true);
    verifyScheduledInsertRollback(dataSource, transaction, key, false);
}

private void verifyManagedCommit(DataSource dataSource, JdbcTemplate jdbc, TransactionTemplate transaction, Object key)
{
    ManagedUpdateContext context;
    transaction.executeWithoutResult((TransactionStatus status) {
        assert(status.isNewTransaction());
        context = new ManagedUpdateContext(dataSource, key, [UpdateAction(0, ownerKey)]);
        assert(context.pid == jdbc.queryForObject!long(backendPid));
        auto owner = context.owner();
        owner.name = "AUTO";
        context.flush();
        assertStored(dataSource, "AUTO", 9);
        assert(owner.revision == 9 && context.writes == 1);
        context.flush();
        assert(context.writes == 1);
        owner.name = "Commit hook";
    });
    assert(context.writes == 2 && context.completion == TransactionSynchronization.STATUS_COMMITTED);
    assertReleased(context, dataSource, key);
    assertStored(dataSource, "Commit hook", 10);
}

private void verifyManagedRollback(DataSource dataSource, TransactionTemplate transaction, Object key, bool explicit)
{
    ManagedUpdateContext context;
    bool failed;
    try
    {
        transaction.executeWithoutResult((TransactionStatus status) {
            context = new ManagedUpdateContext(dataSource, key);
            auto owner = context.owner();
            owner.name = "Before error";
            context.flush();
            assertStored(dataSource, "Before error", 11);
            if (explicit)
            {
                owner.name = "Longer than the reserved snapshot bank";
                try
                {
                    context.flush();
                    assert(false, "snapshot staging must fail");
                }
                catch (ManagedFlushFailure failure)
                {
                    assert(failure.status == Status.outOfMemory);
                }
                assert(status.isRollbackOnly());
            }
            else
            {
                owner.name = "Commit error";
                owner.rejectRevision = true;
            }
        });
    }
    catch (UnexpectedRollbackException failure)
    {
        assert(explicit);
        failed = true;
    }
    catch (Exception failure)
    {
        assert(!explicit && failure.msg == "fixture rejects version write");
        failed = true;
    }
    assert(failed && context.writes == 1);
    assert(context.completion == TransactionSynchronization.STATUS_ROLLED_BACK);
    assertReleased(context, dataSource, key);
    assertStored(dataSource, "Commit hook", 10);
}

private void verifyManagedRequiresNew(DataSource dataSource, JdbcTemplate jdbc,
        DataSourceTransactionManager manager, Object key)
{
    auto outer = new TransactionTemplate(manager);
    auto inner = new TransactionTemplate(manager);
    inner.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    ManagedUpdateContext outerContext;
    ManagedUpdateContext innerContext;
    outer.executeWithoutResult((TransactionStatus status) {
        assert(status.isNewTransaction());
        outerContext = new ManagedUpdateContext(dataSource, key);
        auto owner = outerContext.owner();
        owner.name = "Outer";
        inner.executeWithoutResult((TransactionStatus nested) {
            assert(!TransactionSynchronizationManager.hasResource(key));
            innerContext = new ManagedUpdateContext(dataSource, key);
            assert(innerContext.pid != outerContext.pid && innerContext.pid == jdbc.queryForObject!long(backendPid));
            innerContext.owner().name = "Inner";
            innerContext.flush();
            assertStored(dataSource, "Inner", 11);
            nested.setRollbackOnly();
        });

        assert(innerContext.completion == TransactionSynchronization.STATUS_ROLLED_BACK && innerContext.detached());
        assert(TransactionSynchronizationManager.getResource(key) is outerContext);
        assert(jdbc.queryForObject!long(backendPid) == outerContext.pid);
        assert(owner.revision == 10 && owner.name == "Outer");
        assertStored(dataSource, "Commit hook", 10);
    });
    assert(outerContext.writes == 1 && outerContext.completion == TransactionSynchronization.STATUS_COMMITTED);
    assertReleased(outerContext, dataSource, key);
    assertStored(dataSource, "Outer", 11);
}

private void verifyManagedSuppression(DataSource dataSource, JdbcTemplate jdbc,
        DataSourceTransactionManager manager, Object key)
{
    auto readOnly = new TransactionTemplate(manager);
    readOnly.setReadOnly(true);
    auto supports = new TransactionTemplate(manager);
    supports.setPropagationBehavior(TransactionDefinition.PROPAGATION_SUPPORTS);

    foreach (transaction; [readOnly, supports])
    {
        ManagedUpdateContext context;
        transaction.executeWithoutResult((TransactionStatus status) {
            const physical = transaction is readOnly;
            assert(status.isNewTransaction() == physical);
            assert(TransactionSynchronizationManager.isActualTransactionActive() == physical);
            context = new ManagedUpdateContext(dataSource, key);
            assert(context.pid == jdbc.queryForObject!long(backendPid));
            context.owner().name = "Suppressed";
        });
        assert(context.writes == 0 && context.completion == TransactionSynchronization.STATUS_COMMITTED);
        if (transaction is supports)
            assert(context.retiredBeforeConnectionRelease);
        assertReleased(context, dataSource, key);
        assertStored(dataSource, "Outer", 11);
    }
}

private void verifyManagedBatch(DataSource dataSource, TransactionTemplate transaction, Object key, bool malformed)
{
    ManagedUpdateContext context;
    bool rejected;
    try
    {
        transaction.executeWithoutResult((TransactionStatus status) {
            auto actions = [
                UpdateAction(0, thirdKey), UpdateAction(malformed ? 1 : 0, limitKey),
                UpdateAction(0, ownerKey)
            ];
            context = new ManagedUpdateContext(dataSource, key, actions);
            context.owner(thirdKey).name = "Earlier write";
            context.owner(limitKey).name = "At limit";
            context.owner().name = "Pending";
            try
            {
                context.flush();
                assert(false, "the second batch action must fail");
            }
            catch (ManagedFlushFailure failure)
            {
                assert(failure.action == 1);
                assert(failure.status == (malformed ? Status.invalidArgument : Status.resourceExhausted));
                if (!malformed)
                    assert(failure.attribute == 2);
            }
            assert(status.isRollbackOnly());
            assert(context.writes == (malformed ? 0 : 1));
            assertStored(dataSource, malformed ? "Third row" : "Earlier write", malformed ? 1 : 2, 3);
            assertStored(dataSource, "Limit", long.max, 2);
            assertStored(dataSource, "Outer", 11);
            assert(context.owner().revision == 11 && context.owner().name == "Pending");
        });
    }
    catch (UnexpectedRollbackException)
        rejected = true;
    assert(rejected && context.completion == TransactionSynchronization.STATUS_ROLLED_BACK);
    assertReleased(context, dataSource, key);
    assert(context.detached(limitKey) && context.detached(thirdKey));
    assertStored(dataSource, "Third row", 1, 3);
    assertStored(dataSource, "Outer", 11);
}

private void verifyMixedRollback(DataSource dataSource, TransactionTemplate transaction, Object key, bool malformed)
{
    ManagedUpdateContext context;
    bool rejected;
    try
    {
        transaction.executeWithoutResult((TransactionStatus status) {
            auto changes = [UpdateAction(0, thirdKey)];
            auto removes = [
                DeleteAction(0, thirdKey), DeleteAction(malformed ? 2 : 1, limitKey),
                DeleteAction(0, ownerKey)
            ];
            context = new ManagedUpdateContext(dataSource, key, changes, removes);
            context.owner(thirdKey).name = "Then delete";
            try
            {
                context.flush();
                assert(false, "the second deletion must fail");
            }
            catch (ManagedFlushFailure failure)
            {
                assert(failure.phase == MutationPhase.deletes && failure.action == 1);
                assert(failure.status == (malformed ? Status.invalidArgument : Status.conflict));
            }
            assert(status.isRollbackOnly());
            assert(context.writes == (malformed ? 0 : 1) && context.removed == (malformed ? 0 : 1));
            assert(context.detached(thirdKey) == !malformed);
            if (malformed)
                assertStored(dataSource, "Third row", 1, 3);
            else
                assertAbsent(dataSource, 3);
            assertStored(dataSource, "Limit", long.max, 2);
            assertStored(dataSource, "Outer", 11);
            assert(!context.detached(limitKey) && !context.detached());
        });
    }
    catch (UnexpectedRollbackException)
        rejected = true;
    assert(rejected && context.completion == TransactionSynchronization.STATUS_ROLLED_BACK);
    assertReleased(context, dataSource, key);
    assert(context.detached(limitKey) && context.detached(thirdKey));
    assertStored(dataSource, "Third row", 1, 3);
}

private void verifyMixedCommit(DataSource dataSource, TransactionTemplate transaction, Object key)
{
    ManagedUpdateContext context;
    transaction.executeWithoutResult((TransactionStatus status) {
        assert(status.isNewTransaction());
        context = new ManagedUpdateContext(dataSource, key, [UpdateAction(0, thirdKey)], [
            DeleteAction(0, thirdKey)
        ]);
        context.owner(thirdKey).name = "Delete on commit";
    });
    assert(context.writes == 1 && context.removed == 1);
    assert(context.completion == TransactionSynchronization.STATUS_COMMITTED && context.detached(thirdKey));
    assertReleased(context, dataSource, key);
    assertAbsent(dataSource, 3);
}

private void verifyScheduledInsertRollback(DataSource dataSource, TransactionTemplate transaction,
        Object key, bool malformed)
{
    enum insertSql = "insert into jpa_version_probe (name, version, id) values (?, ?, ?)";
    enum deleteSql = "delete from jpa_version_probe where id = ? and version = ? and false";
    static immutable ParameterBinding[] insertBindings = [
        ParameterBinding(1, 1), ParameterBinding(2, 2), ParameterBinding(0, 3)
    ];
    const insert = planInsert(&mapping, insertSql, insertBindings);
    const write = planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 3));
    const remove = planDelete(&mapping, deleteSql, 1, 2);
    assert(insert.ok && write.ok && remove.ok);
    const plans = MutationPlans([write.value], [remove.value], [insert.value]);
    enum insertedKey = EntityIdentity(0, 4);
    const queue = MutationActions([UpdateAction(0, ownerKey)], [
        DeleteAction(malformed ? 1 : 0, ownerKey)
    ], [InsertAction(0, 0, insertedKey)]);
    ManagedUpdateContext context;
    transaction.executeWithoutResult((TransactionStatus status) {
        context = new ManagedUpdateContext(dataSource, key, null, null, 1);
        context.owner().name = "After insert";
        auto owner = new VersionedOwner;
        owner.id = insertedKey.identifier;
        owner.name = "Queued insert";
        owner.revision = 7;
        uint[1] ordinals;
        auto values = new AttributeValue[3];
        auto connection = DataSourceUtils.getConnection(dataSource);
        scope (exit)
            DataSourceUtils.releaseConnection(connection, dataSource);

        const result = flushManagedMutations(connection, context.managed, plans, queue, ordinals[],
            values, InsertInputs([owner]));
        assert(result.value.failedPhase == MutationPhase.deletes && result.value.failedAction == 0);
        assert(result.error.code == (malformed ? Status.invalidArgument : Status.conflict));
        assert(result.value.inserted == (malformed ? 0 : 1) && result.value.updated == (malformed ? 0 : 1));
        if (malformed)
            assertDeleteAbsent(connection, 4);
        else
        {
            assertStored(connection, "Queued insert", 7, 4);
            assert(context.owner(insertedKey) is owner);
        }
        assertStored(connection, malformed ? "Outer" : "After insert", malformed ? 11 : 12);
        status.setRollbackOnly();
    });
    assert(context.completion == TransactionSynchronization.STATUS_ROLLED_BACK && context.detached(insertedKey));
    assertReleased(context, dataSource, key);
    assertAbsent(dataSource, 4);
    assertStored(dataSource, "Outer", 11);
}

private void assertAbsent(DataSource dataSource, long identifier)
{
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    assertDeleteAbsent(connection, identifier);
}

private final class ManagedFlushFailure : Exception
{
    Status status;
    size_t action;
    size_t attribute;
    MutationPhase phase;

    this(Error error, size_t action = size_t.max, MutationPhase phase = MutationPhase.none)
    {
        super(error.message);
        status = error.code;
        this.action = action;
        attribute = error.offset;
        this.phase = phase;
    }
}

private final class ManagedUpdateContext : TransactionSynchronization
{
    private DataSource dataSource;
    private Object key;
    private ManagedEntities managed;
    private UpdatePlan[] plans;
    private UpdateAction[] actions;
    private DeletePlan[] deletePlans;
    private DeleteAction[] deletions;
    private AttributeValue[] values;
    private bool retired;
    long pid;
    size_t writes;
    size_t removed;
    int completion = -1;
    bool retiredBeforeConnectionRelease;

    this(DataSource dataSource, Object key, UpdateAction[] actions = null,
            DeleteAction[] deletions = null, size_t reserved = 0)
    {
        this.dataSource = dataSource;
        this.key = key;
        this.actions = actions;
        this.deletions = deletions;
        const read = planManagedResult(&mapping, projection, 0);
        const write = planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 3));
        assert(read.ok && write.ok);
        plans = [write.value];
        if (deletions.length != 0)
        {
            enum sql = "delete from jpa_version_probe where id = ? and version = ?";
            const valid = planDelete(&mapping, sql, 1, 2);
            const stale = planDelete(&mapping, sql ~ " and false", 1, 2);
            assert(valid.ok && stale.ok);
            deletePlans = [valid.value, stale.value];
        }
        values = new AttributeValue[3];
        const count = deletions.length != 0 ? 3 : (actions.length == 0 ? 1 : actions.length);
        auto fields = new AttributeSnapshot[18];
        auto bytes = new ubyte[96];
        ManagedSnapshotSlot[] slots = [
            ManagedSnapshotSlot(fields[0 .. 3], bytes[0 .. 16], fields[3 .. 6], bytes[16 .. 32]),
            ManagedSnapshotSlot(fields[6 .. 9], bytes[32 .. 48], fields[9 .. 12], bytes[48 .. 64]),
            ManagedSnapshotSlot(fields[12 .. 15], bytes[64 .. 80], fields[15 .. 18], bytes[80 .. 96])
        ];
        Error error;
        const capacity = count + reserved;
        managed = ManagedEntities(new IdentitySlot[capacity], new Object[capacity], error, slots[0 .. capacity]);
        assert(error.code == Status.ok);

        auto connection = DataSourceUtils.getConnection(dataSource);
        scope (exit)
            DataSourceUtils.releaseConnection(connection, dataSource);
        pid = readBackendPid(connection);
        loadRows(read.value, connection, managed, count);
        TransactionSynchronizationManager.bindResource(key, this);
        scope (failure)
            TransactionSynchronizationManager.unbindResource(key);
        TransactionSynchronizationManager.registerSynchronization(this);
    }

    VersionedOwner owner(EntityIdentity identity = ownerKey)
    {
        auto found = managed.find(identity);
        assert(found.ok);
        return cast(VersionedOwner) found.value;
    }

    bool detached(EntityIdentity identity = ownerKey)
    {
        return managed.find(identity).error.code == Status.notFound;
    }

    override int getOrder()
    {
        return DataSourceUtils.CONNECTION_SYNCHRONIZATION_ORDER - 100;
    }

    override void suspend()
    {
        assert(TransactionSynchronizationManager.unbindResource(key) is this);
    }

    override void resume()
    {
        TransactionSynchronizationManager.bindResource(key, this);
    }

    override void flush()
    {
        assert(TransactionSynchronizationManager.isActualTransactionActive());
        try
        {
            flushPending();
        }
        catch (Exception failure)
        {
            auto holder = cast(ConnectionHolder) TransactionSynchronizationManager.getResource(cast(Object) dataSource);
            assert(holder !is null);
            holder.setRollbackOnly();
            throw failure;
        }
    }

    override void beforeCommit(bool readOnly)
    {
        if (!readOnly && TransactionSynchronizationManager.isActualTransactionActive())
            flushPending();
    }

    override void beforeCompletion()
    {
        if (!TransactionSynchronizationManager.isActualTransactionActive())
        {
            retiredBeforeConnectionRelease = TransactionSynchronizationManager.hasResource(cast(Object) dataSource);
            retire();
        }
    }

    override void afterCompletion(int status)
    {
        completion = status;
        if (!retired)
            retire();
    }

    private void flushPending()
    {
        assert(TransactionSynchronizationManager.getResource(key) is this);
        auto connection = DataSourceUtils.getConnection(dataSource);
        scope (exit)
            DataSourceUtils.releaseConnection(connection, dataSource);
        auto holder = cast(ConnectionHolder) TransactionSynchronizationManager.getResource(cast(Object) dataSource);
        assert(holder !is null && holder.getConnection() is connection);
        uint[1] ordinals;
        if (deletions.length != 0)
        {
            const layout = MutationPlans(plans, deletePlans);
            const queue = MutationActions(actions, deletions);
            const mixed = flushManagedMutations(connection, managed, layout, queue, ordinals[], values);
            writes += mixed.value.updated;
            removed += mixed.value.deleted;
            if (!mixed.ok)
                throw new ManagedFlushFailure(mixed.error, mixed.value.failedAction, mixed.value.failedPhase);
            return;
        }
        if (actions.length != 0)
        {
            const batch = flushManagedUpdates(connection, managed, plans, actions, ordinals[], values);
            writes += batch.value.updated;
            if (!batch.ok)
                throw new ManagedFlushFailure(batch.error, batch.value.failedAction);
            return;
        }
        const outcome = flushManagedUpdate(plans[0], connection, managed, ownerKey, ordinals[], values);
        if (!outcome.ok)
            throw new ManagedFlushFailure(outcome.error);
        writes += outcome.value.updated;
    }

    private void retire()
    {
        assert(TransactionSynchronizationManager.unbindResource(key) is this);
        managed.clear();
        retired = true;
    }
}

private long readBackendPid(Connection connection)
{
    auto statement = connection.prepareStatement(backendPid);
    scope (exit)
        statement.close();
    auto result = statement.executeQuery();
    scope (exit)
        result.close();
    assert(result.next());
    return result.getLong(1);
}

private void assertStored(DataSource dataSource, string name, long revision, long identifier = 1)
{
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    assertStored(connection, name, revision, identifier);
}

private void assertReleased(ManagedUpdateContext context, DataSource dataSource, Object key)
{
    assert(context.detached());
    assert(!TransactionSynchronizationManager.hasResource(key));
    assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
}

/// Checks versioned and unversioned deletion, including retirement and rollback.
void verifyManagedDeletes(DataSource dataSource, JdbcTemplate jdbc)
{
    enum deleteOwner = "delete from jpa_version_probe where version = ? and id = ?";
    const planned = planDelete(&mapping, deleteOwner, 2, 1);
    const multiple = planDelete(&mapping,
            "delete from jpa_version_probe where id >= ? and ?::bigint is not null", 1, 2);
    const broken = planDelete(&mapping, "delete from missing_jpa_fixture where version = ? and id = ?", 2, 1);
    const read = planManagedResult(&mapping, projection, 0);
    assert(planned.ok && multiple.ok && broken.ok && read.ok);
    assert(planDelete(&mapping, deleteOwner, 1, 1).error.code == Status.invalidArgument);
    assert(planDelete(&mapping, deleteOwner, 1).error.code == Status.invalidArgument);

    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    connection.setAutoCommit(false);
    scope (exit)
        connection.rollback();
    auto fields = new AttributeSnapshot[3];
    auto bytes = new ubyte[16];
    ManagedSnapshotSlot[1] snapshot = [ManagedSnapshotSlot(fields, bytes)];
    IdentitySlot[1] identity;
    Object[1] roots;
    Error error;
    scope managed = ManagedEntities(identity[], roots[], error, snapshot[]);
    assert(error.code == Status.ok);
    loadRows(read.value, connection, managed);

    auto owner = cast(VersionedOwner) managed.find(ownerKey).value;
    owner.id = 2;
    const changed = executeManagedDelete(planned.value, connection, managed, ownerKey);
    assert(changed.code == Status.invalidArgument && changed.offset == 0);
    owner.id = 1;
    {
        auto independent = dataSource.getConnection();
        scope (exit)
            independent.close();
        assert(independent.getAutoCommit());
        assert(executeManagedDelete(planned.value, independent, managed, ownerKey).code == Status.invalidArgument);
    }
    assertStored(connection, "Outer", 11);
    verifyDeleteRebind(connection, planned.value, read.value, RebindPhase.identifier);
    verifyDeleteRebind(connection, planned.value, read.value, RebindPhase.binding);
    verifyDeleteRebind(connection, planned.value, read.value, RebindPhase.close);

    assert(executeManagedDelete(multiple.value, connection, managed, ownerKey).code == Status.ioError);
    assert(managed.find(ownerKey).value is owner);
    assertDeleteAbsent(connection);
    connection.rollback();
    assertStored(connection, "Outer", 11);
    verifyDeleteDriverFailure(broken.value, connection, managed, owner);
    connection.rollback();
    assertStored(connection, "Outer", 11);

    owner.revision = 100;
    assert(executeManagedDelete(planned.value, connection, managed, ownerKey).code == Status.ok);
    assert(managed.find(ownerKey).error.code == Status.notFound);
    assert(executeManagedDelete(planned.value, connection, managed, ownerKey).code == Status.notFound);
    assertDeleteAbsent(connection);
    connection.rollback();
    assertStored(connection, "Outer", 11);

    loadRows(read.value, connection, managed);
    owner = cast(VersionedOwner) managed.find(ownerKey).value;
    jdbc.execute("update jpa_version_probe set name = 'Delete winner', version = 12 where id = 1");
    const stale = executeManagedDelete(planned.value, connection, managed, ownerKey);
    assert(stale.code == Status.conflict && managed.find(ownerKey).value is owner);
    assert(owner.revision == 11);
    assertStored(connection, "Delete winner", 12);
    connection.rollback();

    verifyUnversionedDelete(connection, managed);
    connection.rollback();
    assertStored(connection, "Delete winner", 12);
}

private final class RebindContext
{
    IdentitySlot[1] identities;
    Object[1] roots;
    ManagedSnapshotSlot[1] snapshots;
    ManagedEntities managed;
    LoadedSnapshotPlan plan;

    this(LoadedSnapshotPlan loadedPlan, bool refresh = false)
    {
        plan = loadedPlan;
        snapshots = [
            ManagedSnapshotSlot(new AttributeSnapshot[3], new ubyte[refresh ? 32 : 16], refresh
                    ? new AttributeSnapshot[3] : null, refresh ? new ubyte[16] : null)
        ];
        Error error;
        managed = ManagedEntities(identities[], roots[], error, snapshots[]);
        assert(error.code == Status.ok);
    }

    void reattach() nothrow @nogc
    {
        auto owner = cast(VersionedOwner) managed.detach(ownerKey).value;
        assert(owner !is null);
        owner.name = "Reattached";
        assert(managed.manage(ownerKey, owner, plan).code == Status.ok);
    }

}

private final class NestedUpdateConnection : BlackHole!Connection
{
    private Connection connection;
    private RebindContext context;
    private UpdatePlan plan;
    private bool refresh;
    uint transactionChecks;

    this(Connection connection, RebindContext context, UpdatePlan plan, bool refresh)
    {
        this.connection = connection;
        this.context = context;
        this.plan = plan;
        this.refresh = refresh;
    }

    override bool getAutoCommit()
    {
        ++transactionChecks;
        if (transactionChecks != 1)
            return connection.getAutoCommit();
        auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
        const reads = owner.nameReads;
        uint[1] ordinals;
        auto values = new AttributeValue[3];
        const allocated = GC.stats().allocatedInCurrentThread;
        const nested = refresh ? flushManagedUpdate(plan, this, context.managed, ownerKey, ordinals[], values)
            : executeVersionedUpdate(plan, this, context.managed, ownerKey, ordinals[]);
        const allocatedAfter = GC.stats().allocatedInCurrentThread;
        assertStored(connection, "Winner", 8);
        assert(nested.error.code == Status.conflict, "recursive update accepted the in-flight attachment");
        assert(allocatedAfter == allocated);
        assert(owner.nameReads == reads && transactionChecks == 1);
        return connection.getAutoCommit();
    }

    override PreparedStatement prepareStatement(string sql)
    {
        return connection.prepareStatement(sql);
    }
}

private void verifyNestedUpdate(Connection connection, const ref UpdatePlan update,
        const ref ManagedRowMaterializationPlan readPlan, bool nestedRefresh)
{
    const snapshot = planLoadedSnapshot(&mapping);
    assert(snapshot.ok);
    auto context = new RebindContext(snapshot.value, true);
    scope (exit)
        context.managed.clear();
    loadRows(readPlan, connection, context.managed);
    auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
    assert(owner !is null);
    auto wrapper = new NestedUpdateConnection(connection, context, update, nestedRefresh);
    owner.name = "Outer edit";
    uint[1] ordinals;
    auto values = new AttributeValue[3];
    const outer = flushManagedUpdate(update, wrapper, context.managed, ownerKey, ordinals[], values);
    assert(wrapper.transactionChecks == 1 && outer.ok && outer.value.updated && owner.revision == 9);
    assertStored(connection, "Outer edit", 9);
    const dirty = context.managed.dirty(ownerKey, ordinals[]);
    assert(dirty.ok && dirty.value == 0);

    owner.name = "Follow-up";
    const next = flushManagedUpdate(update, connection, context.managed, ownerKey, ordinals[], values);
    assert(next.ok && next.value.updated && owner.revision == 10);
    assertStored(connection, "Follow-up", 10);
    connection.rollback();
    assertStored(connection, "Winner", 8);
}

private void verifyUpdateCaptureRebind(Connection connection, const ref UpdatePlan update,
        const ref ManagedRowMaterializationPlan readPlan)
{
    const plan = planLoadedSnapshot(&mapping);
    assert(plan.ok);
    auto context = new RebindContext(plan.value, true);
    scope (exit)
        context.managed.clear();
    loadRows(readPlan, connection, context.managed);
    auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
    assert(owner !is null);
    const prior = context.managed.lazyHandle(ownerKey);
    assert(prior.ok);

    uint[1] ordinals;
    auto values = new AttributeValue[3];
    // Publish the alternate bank so the next stage borrows the primary bank, which the reattachment will use.
    owner.name = "First edit";
    const first = flushManagedUpdate(update, connection, context.managed, ownerKey, ordinals[], values);
    assert(first.ok && first.value.updated && owner.revision == 9);

    owner.name = "Attempted";
    owner.rebindOnNameRead = owner.nameReads + 2;
    owner.updateRebind = context;
    const allocated = GC.stats().allocatedInCurrentThread;
    const outcome = flushManagedUpdate(update, connection, context.managed, ownerKey, ordinals[], values);
    assert(outcome.error.code == Status.conflict, "a retired update captured into the replacement attachment");
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(owner.updateRebind is null && owner.revision == 9);
    assert(context.managed.find(ownerKey).value is owner);
    assert(context.managed.resolveLazyOwner(prior.value).error.code == Status.notFound);
    const dirty = context.managed.dirty(ownerKey, ordinals[]);
    assert(dirty.ok && dirty.value == 0);
    assertStored(connection, "First edit", 9);
    foreach (ref value; values)
        assert(value.kind == AttributeKind.nullValue);

    owner.name = "Retry";
    const retried = flushManagedUpdate(update, connection, context.managed, ownerKey, ordinals[], values);
    assert(retried.ok && retried.value.updated && owner.revision == 10);
    assertStored(connection, "Retry", 10);
    connection.rollback();
    assertStored(connection, "Winner", 8);
}

private void verifyUpdateStatementRebind(Connection connection, const ref UpdatePlan update,
        const ref ManagedRowMaterializationPlan readPlan, RebindPhase phase, bool refresh)
{
    const plan = planLoadedSnapshot(&mapping);
    assert(plan.ok);
    auto context = new RebindContext(plan.value, true);
    scope (exit)
        context.managed.clear();
    loadRows(readPlan, connection, context.managed);
    auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
    assert(owner !is null);
    const prior = context.managed.lazyHandle(ownerKey);
    assert(prior.ok);

    owner.name = "Attempted";
    auto wrapping = new RebindingConnection(connection, context, phase);
    uint[1] ordinals;
    auto values = new AttributeValue[3];
    const outcome = refresh ? flushManagedUpdate(update, wrapping, context.managed, ownerKey, ordinals[], values)
        : executeVersionedUpdate(update, wrapping, context.managed, ownerKey, ordinals[]);
    assert(outcome.error.code == Status.conflict);
    assert(context.managed.find(ownerKey).value is owner && owner.revision == 8);
    assert(context.managed.resolveLazyOwner(prior.value).error.code == Status.notFound);
    const dirty = context.managed.dirty(ownerKey, ordinals[]);
    assert(dirty.ok && dirty.value == 0);
    foreach (ref value; values)
        assert(value.kind == AttributeKind.nullValue);

    if (phase == RebindPhase.close)
    {
        assertStored(connection, "Attempted", 9);
        connection.rollback();
    }
    assertStored(connection, "Winner", 8);

    owner.name = "Retry";
    const retried = flushManagedUpdate(update, connection, context.managed, ownerKey, ordinals[], values);
    assert(retried.ok && retried.value.updated && owner.revision == 9);
    assertStored(connection, "Retry", 9);
    connection.rollback();
    assertStored(connection, "Winner", 8);
}

private void verifyUpdatePreflightRebind(Connection connection, const ref UpdatePlan update,
        const ref ManagedRowMaterializationPlan readPlan, RebindPhase phase, bool refresh)
{
    const plan = planLoadedSnapshot(&mapping);
    assert(plan.ok);
    auto context = new RebindContext(plan.value, refresh);
    scope (exit)
        context.managed.clear();
    loadRows(readPlan, connection, context.managed);
    auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
    assert(owner !is null);
    const prior = context.managed.lazyHandle(ownerKey);
    assert(prior.ok);

    owner.name = "Attempted";
    auto writing = connection;
    final switch (phase)
    {
    case RebindPhase.dirty:
        owner.rebindOnNameRead = owner.nameReads + 1;
        owner.updateRebind = context;
        break;
    case RebindPhase.identifier:
        owner.identifierRebind = context;
        break;
    case RebindPhase.autoCommit:
        writing = new RebindingConnection(connection, context, phase);
        break;
    case RebindPhase.binding, RebindPhase.close:
        assert(false, "expected a preflight callback");
    }

    uint[1] ordinals;
    auto values = new AttributeValue[3];
    const allocated = GC.stats().allocatedInCurrentThread;
    const outcome = refresh ? flushManagedUpdate(update, writing, context.managed, ownerKey, ordinals[], values)
        : executeVersionedUpdate(update, writing, context.managed, ownerKey, ordinals[]);
    assert(outcome.error.code == Status.conflict, "a retired preflight target proceeded to UPDATE");
    assert(GC.stats().allocatedInCurrentThread == allocated);
    assert(context.managed.find(ownerKey).value is owner && owner.revision == 8);
    assert(context.managed.resolveLazyOwner(prior.value).error.code == Status.notFound);
    const dirty = context.managed.dirty(ownerKey, ordinals[]);
    assert(dirty.ok && dirty.value == 0);
    assertStored(connection, "Winner", 8);
}

private enum RebindPhase
{
    dirty,
    identifier,
    autoCommit,
    binding,
    close,
}

private final class RebindingStatement : BlackHole!PreparedStatement
{
    private PreparedStatement statement;
    private RebindContext attached;
    private RebindPhase phase;

    this(PreparedStatement statement, RebindContext attached, RebindPhase phase)
    {
        this.statement = statement;
        this.attached = attached;
        this.phase = phase;
    }

    override void setLong(int position, long value)
    {
        statement.setLong(position, value);
        reattach(RebindPhase.binding);
    }

    override void setString(int position, string value)
    {
        statement.setString(position, value);
    }

    override int executeUpdate()
    {
        return statement.executeUpdate();
    }

    override void close()
    {
        statement.close();
        reattach(RebindPhase.close);
    }

    private void reattach(RebindPhase current)
    {
        if (phase == current && attached !is null)
        {
            attached.reattach();
            attached = null;
        }
    }
}

private final class RebindingConnection : BlackHole!Connection
{
    private Connection connection;
    private RebindContext attached;
    private RebindPhase phase;

    this(Connection connection, RebindContext attached, RebindPhase phase)
    {
        this.connection = connection;
        this.attached = attached;
        this.phase = phase;
    }

    override bool getAutoCommit()
    {
        if (phase == RebindPhase.autoCommit && attached !is null)
        {
            attached.reattach();
            attached = null;
        }
        return connection.getAutoCommit();
    }

    override PreparedStatement prepareStatement(string sql)
    {
        return new RebindingStatement(connection.prepareStatement(sql), attached, phase);
    }
}

private void verifyDeleteRebind(Connection connection, const ref DeletePlan deletePlan,
        const ref ManagedRowMaterializationPlan readPlan, RebindPhase phase)
{
    const loaded = planLoadedSnapshot(&mapping);
    assert(loaded.ok);
    auto context = new RebindContext(loaded.value);
    scope (exit)
        context.managed.clear();
    loadRows(readPlan, connection, context.managed);
    auto owner = cast(VersionedOwner) context.managed.find(ownerKey).value;
    assert(owner !is null);
    const prior = context.managed.lazyHandle(ownerKey);
    assert(prior.ok);

    auto deleting = connection;
    if (phase == RebindPhase.identifier)
        owner.identifierRebind = context;
    else
        deleting = new RebindingConnection(connection, context, phase);
    const before = GC.stats().allocatedInCurrentThread;
    const result = executeManagedDelete(deletePlan, deleting, context.managed, ownerKey);
    assert(result.code == Status.conflict, "rebound owner was deleted through an earlier attachment");
    if (phase == RebindPhase.identifier)
        assert(GC.stats().allocatedInCurrentThread == before);
    assert(owner.identifierRebind is null);
    assert(context.managed.find(ownerKey).value is owner);
    assert(context.managed.resolveLazyOwner(prior.value).error.code == Status.notFound);
    uint[1] dirtyOrdinals;
    const dirty = context.managed.dirty(ownerKey, dirtyOrdinals[]);
    assert(dirty.ok && dirty.value == 0);
    if (phase == RebindPhase.close)
    {
        assertDeleteAbsent(connection);
        connection.rollback();
    }
    assertStored(connection, "Outer", 11);
}

private void assertDeleteAbsent(Connection connection, long identifier = 1)
{
    auto statement = connection.prepareStatement("select count(*) from jpa_version_probe where id = ?");
    scope (exit)
        statement.close();
    statement.setLong(1, identifier);
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next() && rows.getLong(1) == 0);
}

private void verifyDeleteDriverFailure(const ref DeletePlan plan, Connection connection,
        scope ref ManagedEntities managed, VersionedOwner owner)
{
    try
    {
        executeManagedDelete(plan, connection, managed, ownerKey);
        assert(false, "driver DELETE failure must propagate");
    }
    catch (SQLException failure)
    {
        assert(failure.getSQLState() == "42P01");
    }
    assert(managed.find(ownerKey).value is owner);
}

private void verifyUnversionedDelete(Connection connection, scope ref ManagedEntities managed)
{
    static immutable EntityMapping unversioned = EntityMapping("UnversionedOwner", ownerType,
            "jpa_version_probe", mapping.attributes, mapping.construct, [], mapping.isExactType, [0]);
    enum sql = "delete from jpa_version_probe where id = ?";
    const plan = planDelete(&unversioned, sql, 1);
    assert(planDelete(&unversioned, sql, 1, 2).error.code == Status.invalidArgument);
    const read = planManagedResult(&unversioned, projection, 0);
    assert(plan.ok && read.ok);
    assert(executeManagedDelete(plan.value, connection, managed, ownerKey).code == Status.invalidArgument);
    assert(managed.detach(ownerKey).ok);
    loadRows(read.value, connection, managed);
    assert(executeManagedDelete(plan.value, connection, managed, ownerKey).code == Status.ok);
    assert(managed.find(ownerKey).error.code == Status.notFound);
    assertDeleteAbsent(connection);
}

/// Checks assigned-ID insertion, already-managed identity rejection, and rollback.
void verifyManagedInserts(DataSource dataSource)
{
    enum sql = "insert into jpa_version_probe (name, version, id) values (?, ?, ?)";
    static immutable ParameterBinding[] bindings = [
        ParameterBinding(1, 1), ParameterBinding(2, 2), ParameterBinding(0, 3)
    ];
    const planned = planInsert(&mapping, sql, bindings);
    const multiple = planInsert(&mapping, sql ~ ", ('unexpected', 0, 6)", bindings);
    assert(planned.ok && multiple.ok);
    assert(planInsert(&mapping, sql, bindings[0 .. 2]).error.code == Status.invalidArgument);

    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    connection.setAutoCommit(false);
    scope (exit)
        connection.rollback();
    auto fields = new AttributeSnapshot[3];
    auto bytes = new ubyte[16];
    ManagedSnapshotSlot[1] snapshot = [ManagedSnapshotSlot(fields, bytes)];
    IdentitySlot[1] identity;
    Object[1] roots;
    Error error;
    scope managed = ManagedEntities(identity[], roots[], error, snapshot[]);
    assert(error.code == Status.ok);

    auto owner = new VersionedOwner;
    owner.id = 4;
    owner.revision = 3;
    owner.name = "More bytes than the reserved snapshot arena";
    const key = EntityIdentity(0, 4);
    auto values = new AttributeValue[3];
    const exhausted = executeManagedInsert(planned.value, connection, managed, key, owner, values);
    assert(exhausted.code == Status.outOfMemory && exhausted.offset == 1);
    assert(managed.find(key).error.code == Status.notFound);
    assertDeleteAbsent(connection, 4);

    owner.name = "Inserted";
    const wrongId = EntityIdentity(0, 5);
    const mismatched = executeManagedInsert(planned.value, connection, managed, wrongId, owner, values);
    assert(mismatched.code == Status.invalidArgument && mismatched.offset == 0);
    assert(managed.find(wrongId).error.code == Status.notFound);
    assertDeleteAbsent(connection, 4);

    assert(executeManagedInsert(multiple.value, connection, managed, key, owner, values).code == Status.ioError);
    assert(managed.find(key).error.code == Status.notFound);
    connection.rollback();
    assertDeleteAbsent(connection, 4);
    assertDeleteAbsent(connection, 6);
    verifyInsertDriverFailure(planned.value, connection, managed, values);
    connection.rollback();

    const reads = owner.nameReads;
    assert(executeManagedInsert(planned.value, connection, managed, key, owner, values).code == Status.ok);
    assert(managed.find(key).value is owner && owner.nameReads == reads + 1);
    assertStored(connection, "Inserted", 3, 4);
    uint[1] dirtySlots;
    const dirty = managed.dirty(key, dirtySlots[]);
    assert(dirty.ok && dirty.value == 0);
    assert(executeManagedInsert(planned.value, connection, managed, key, owner, values).code == Status.conflict);
    assert(managed.find(key).value is owner);
    foreach (ref value; values)
        assert(value.kind == AttributeKind.nullValue);

    connection.rollback();
    managed.clear();
    assert(managed.find(key).error.code == Status.notFound);
    assertDeleteAbsent(connection, 4);
}

private void verifyInsertDriverFailure(const ref InsertPlan plan, Connection connection,
        scope ref ManagedEntities managed, AttributeValue[] values)
{
    auto owner = new VersionedOwner;
    owner.id = ownerKey.identifier;
    owner.name = "Duplicate";
    try
    {
        executeManagedInsert(plan, connection, managed, ownerKey, owner, values);
        assert(false, "duplicate identity SQL must throw");
    }
    catch (SQLException failure)
    {
        assert(failure.getSQLState() == "23505");
    }
    assert(managed.find(ownerKey).error.code == Status.notFound);
}
