/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module app;

import core.memory : GC;
import flint.arena : Error, RequestArena, Result, Status;
import flint.conc : Deadline;
import flint.engine.aot.any : Any;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping, ResultBinding,
    RowMaterializationPlan, TypedColumnCodec, materializeRow, planResult, validateEntity, validateMapping;
import flint.engine.jpa.identity : EntityIdentity, IdentitySlot;
import flint.engine.jpa.loaded_state : ManagedSnapshotSlot, captureLoadedState, dirtyOrdinals, planLoadedSnapshot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.parameter_binding : ParameterBinding, bindParameters, planParameters;
import flint.engine.jpa.registry : registerMappings;
import flint.engine.jpa.result_binding : materializeManagedRow, planManagedResult;
import flint.engine.jpa.snapshot : AttributeSnapshot;
import flint.engine.jdbc : FlintDataSource, enablePostgres;
import flint.engine.reactor : Backend, Reactor, ReactorOptions, TaskContext, TaskDelegate;
import flint.java.sql : PreparedStatement, ResultSet, SQLException, Types;
import flint.java.time : LocalDate;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcTemplate;
import flint.jdbc.datasource : ConnectionHolder, DataSourceTransactionManager, DataSourceUtils;
import flint.transaction : CannotCreateTransactionException, TransactionDefinition,
    TransactionStatus, UnexpectedRollbackException;
import flint.transaction.support : TransactionSynchronization, TransactionSynchronizationManager, TransactionTemplate;
import jpa_timestamp : verifyTimestampMapping;
import std.process : environment;

@safe:

private enum backendPid = "select pg_backend_pid()::bigint";

private long providerQuery(DataSource dataSource, string sql)
{
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    auto statement = connection.prepareStatement(sql);
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());
    return rows.getLong(1);
}

private class OwnerBase
{
    long id;
    int loadOrder;
}

private class Owner : OwnerBase
{
    string name;
    LocalDate birthDate;
}

private final class DerivedOwner : Owner
{
}

private Object constructOwner()
{
    return new Owner;
}

private bool isExactOwnerType(scope const TypeInfo_Class candidate) nothrow @nogc
{
    return candidate is typeid(Owner);
}

private Result!AttributeValue readId(Object object) nothrow @nogc
{
    auto value = cast(Owner) object;
    if (value is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Owner"));
    return Result!AttributeValue(AttributeValue(AttributeKind.integer, value.id));
}

private Result!AttributeValue readName(Object object) nothrow @nogc
{
    auto owner = cast(Owner) object;
    if (owner is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Owner"));
    AttributeValue value;
    if (owner.name !is null)
    {
        value.kind = AttributeKind.text;
        value.text = owner.name;
    }
    return Result!AttributeValue(value);
}

private void writeId(Object object, const ref AttributeValue value)
{
    (cast(Owner) object).id = value.integer;
}

private void writeName(Object object, const ref AttributeValue value)
{
    (cast(Owner) object).name = value.kind == AttributeKind.nullValue ? null : value.text;
}

private Result!AttributeValue readBirthDate(Object object) nothrow @nogc
{
    auto owner = cast(Owner) object;
    if (owner is null)
        return Result!AttributeValue(AttributeValue.init, Error(Status.invalidArgument, "expected Owner"));
    return Result!AttributeValue(AttributeValue(AttributeKind.date, owner.birthDate.toEpochDay()));
}

private AttributeValue readTypedColumn(ResultSet row, int column, AttributeKind kind)
{
    assert(kind == AttributeKind.date);
    return AttributeValue(kind, row.getObject!LocalDate(column).toEpochDay());
}

private void writeTypedColumn(PreparedStatement statement, int parameter, scope const ref AttributeValue value)
{
    assert(value.kind == AttributeKind.date);
    statement.setObject(parameter, Any.of(LocalDate.ofEpochDay(value.integer)));
}

private immutable ownerCodec = TypedColumnCodec(&readTypedColumn, &writeTypedColumn);

private void writeBirthDate(Object object, const ref AttributeValue value)
{
    (cast(Owner) object).birthDate = LocalDate.ofEpochDay(value.integer);
}

private void postLoadListener(Object object)
{
    auto owner = cast(Owner) object;
    assert(owner.id == 1 && owner.name == "One" && owner.loadOrder == 0);
    assert(owner.birthDate == LocalDate.of(1968, 2, 29));
    owner.loadOrder = 1;
}

private void postLoadMappedSuperclass(Object object)
{
    auto owner = cast(Owner) object;
    assert(owner.loadOrder == 1);
    owner.loadOrder = 2;
}

private void postLoadOwner(Object object)
{
    auto owner = cast(Owner) object;
    assert(owner.loadOrder == 2);
    owner.loadOrder = 3;
}

private immutable AttributeMapping[] ownerAttributes = [
    AttributeMapping(0, "id", "id", AttributeKind.integer, &readId, &writeId, false, false, true,
            false, 0, Types.BIGINT),
    AttributeMapping(1, "name", "name", AttributeKind.text, &readName, &writeName, false, true,
            true, true, 0, Types.LONGVARCHAR),
    AttributeMapping(2, "birthDate", "birth_date", AttributeKind.date, &readBirthDate,
            &writeBirthDate, false, false, true, true, 0, Types.DATE),
];

private immutable EntityMapping ownerMapping = EntityMapping("Owner", "app.Owner", "jpa_seam_probe", ownerAttributes,
        &constructOwner, [&postLoadListener, &postLoadMappedSuperclass, &postLoadOwner], &isExactOwnerType, [
            0
]);

private void requireExpectedEntity(Object entity)
{
    const error = validateEntity(ownerMapping, entity);
    if (error.code != Status.ok)
        throw new Exception(error.message);
}

private immutable ResultBinding[] ownerBindings = [
    ResultBinding(1, 1), ResultBinding(2, 2), ResultBinding(0, 3)
];

private enum selectOwner = "select name, birth_date, id from jpa_seam_probe where id = ?";

private Owner providerLoadOwner(DataSource dataSource, scope const ref RowMaterializationPlan plan,
        long id, string sql = selectOwner)
{
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    auto statement = connection.prepareStatement(sql);
    scope (exit)
        statement.close();
    statement.setLong(1, id);
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());

    if (sql == selectOwner)
    {
        const before = GC.stats().allocatedInCurrentThread;
        const date = ownerCodec.read(rows, 2, AttributeKind.date);
        assert(GC.stats().allocatedInCurrentThread == before);
        assert(date.integer == LocalDate.of(1968, 2, 29).toEpochDay());
    }
    auto loaded = materializeRow(plan, rows);
    if (!loaded.ok)
    {
        auto message = loaded.error.message;
        if (loaded.error.offset < ownerMapping.attributes.length)
            message ~= " " ~ ownerMapping.attributes[loaded.error.offset].name;
        throw new Exception(message);
    }
    return cast(Owner) loaded.value;
}

private void requireNullRejection(DataSource dataSource, scope const ref RowMaterializationPlan plan,
        string sql, string attribute)
{
    try
        cast(void) providerLoadOwner(dataSource, plan, 1, sql);
    catch (Exception failure)
    {
        assert(failure.msg == "Cannot map SQL NULL to " ~ attribute);
        return;
    }
    assert(false, "SQL NULL must be rejected");
}

private void failPostLoad(Object entity)
{
    assert((cast(Owner) entity).name == "One");
    throw new Exception("intentional managed PostLoad failure");
}

private void verifyManagedLoadFailure(ResultSet rows, scope ref ManagedEntities managed)
{
    static immutable EntityMapping failing = EntityMapping("Owner", "app.Owner", "jpa_seam_probe",
            ownerAttributes, &constructOwner, [&failPostLoad], &isExactOwnerType, [0]);
    const plan = planManagedResult(&failing, ownerBindings, 1, ownerCodec);
    assert(plan.ok);
    try
    {
        cast(void) materializeManagedRow(plan.value, rows, managed);
        assert(false, "PostLoad failure must propagate");
    }
    catch (Exception failure)
    {
        assert(failure.msg == "intentional managed PostLoad failure");
    }
    assert(managed.find(EntityIdentity(1, 1)).error.code == Status.notFound);
    assert(managed.find(EntityIdentity(0, 1)).ok);
}

private void verifyManagedIdentity(DataSource dataSource)
{
    const plan = planManagedResult(&ownerMapping, ownerBindings, 0, ownerCodec);
    assert(plan.ok);
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    auto statement = connection.prepareStatement("select name, birth_date, id from jpa_seam_probe where id = 1 "
            ~ "union all select name, birth_date, null from jpa_seam_probe where id = 1 order by id nulls last");
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());

    IdentitySlot[2] backing;
    Object[2] entities;
    // The context allocates its bounded backing at startup. All slot operations borrow it.
    auto fields = new AttributeSnapshot[6];
    auto bytes = new ubyte[16];
    ManagedSnapshotSlot[2] snapshots = [
        ManagedSnapshotSlot(fields[0 .. 3], bytes[0 .. 8]),
        ManagedSnapshotSlot(fields[3 .. 6], bytes[8 .. 16])
    ];
    Error error;
    {
        scope managed = ManagedEntities(backing[], entities[], error, snapshots[]);
        assert(error.code == Status.ok);
        const key = EntityIdentity(0, 1);
        const snapshotPlan = planLoadedSnapshot(&ownerMapping);
        assert(snapshotPlan.ok);
        auto oversized = new Owner;
        oversized.name = "Longer name";
        const rejected = managed.manage(key, oversized, snapshotPlan.value);
        assert(rejected.code == Status.outOfMemory && rejected.offset == 1);
        assert(managed.find(key).error.code == Status.notFound);

        auto first = materializeManagedRow(plan.value, rows, managed);
        assert(first.ok && (cast(const Owner) first.value).loadOrder == 3);

        uint[2] ordinals;
        const before = GC.stats().allocatedInCurrentThread;
        const original = managed.dirty(key, ordinals[]);
        assert(original.ok && original.value == 0);
        (cast(Owner) first.value).name = "Edited";
        const found = materializeManagedRow(plan.value, rows, managed);
        assert(found.ok && found.value is first.value);
        const dirty = managed.dirty(key, ordinals[]);
        assert(dirty.ok && dirty.value == 1 && ordinals[0] == 1);
        assert(GC.stats().allocatedInCurrentThread == before);
        verifyManagedLoadFailure(rows, managed);
        // A second callback failure must reach PostLoad using the reclaimed slot bytes.
        verifyManagedLoadFailure(rows, managed);
        const detached = managed.detach(key);
        assert(detached.ok && detached.value is first.value);
        assert(managed.dirty(key, ordinals[]).error.code == Status.notFound);
        const loadedAgain = materializeManagedRow(plan.value, rows, managed);
        assert(loadedAgain.ok && loadedAgain.value !is first.value);
        assert((cast(const Owner) loadedAgain.value).loadOrder == 3);
        const clean = managed.dirty(key, ordinals[]);
        assert(clean.ok && clean.value == 0);

        assert(rows.next());
        const missing = materializeManagedRow(plan.value, rows, managed);
        assert(missing.error.code == Status.invalidArgument && missing.error.offset == 0);
        assert(managed.find(key).value is loadedAgain.value);
        managed.clear();
        assert(managed.dirty(key, ordinals[]).error.code == Status.notFound);
    }
    foreach (entity; entities)
        assert(entity is null);
}

private void verifyDirtySnapshots(Owner owner)
{
    const plan = planLoadedSnapshot(&ownerMapping);
    assert(plan.ok);
    ubyte[64] backing;
    scope arena = RequestArena(backing[]);
    AttributeSnapshot[3] snapshots;
    uint[2] ordinals;
    const priorId = owner.id;
    const priorName = owner.name;
    const priorBirthDate = owner.birthDate;
    const nextBirthDate = LocalDate.of(1968, 3, 1);
    scope (exit)
    {
        owner.id = priorId;
        owner.name = priorName;
        owner.birthDate = priorBirthDate;
    }

    const before = GC.stats().allocatedInCurrentThread;
    scope loaded = captureLoadedState(plan.value, owner, arena, snapshots[]);
    assert(loaded.ok);
    const clean = dirtyOrdinals(loaded.value, owner, arena, ordinals[]);
    assert(clean.ok && clean.value == 0);
    owner.name = null;
    const nullName = dirtyOrdinals(loaded.value, owner, arena, ordinals[]);
    assert(nullName.ok && nullName.value == 1 && ordinals[0] == 1);

    owner.id = priorId + 1;
    owner.name = "Edited";
    owner.birthDate = nextBirthDate;
    ubyte[1] stagingBytes;
    scope stagingArena = RequestArena(stagingBytes[]);
    AttributeSnapshot[3] staging;
    scope const failed = captureLoadedState(plan.value, owner, stagingArena, staging[]);
    assert(failed.error.code == Status.outOfMemory && failed.error.offset == 1);
    uint[1] insufficient = [uint.max];
    assert(dirtyOrdinals(loaded.value, owner, arena, insufficient[]).error.code == Status.resourceExhausted);
    assert(insufficient[0] == uint.max);
    const dirty = dirtyOrdinals(loaded.value, owner, arena, ordinals[]);
    assert(dirty.ok && dirty.value == 2);
    assert(ordinals[0] == 1 && ordinals[1] == 2);
    assert(GC.stats().allocatedInCurrentThread == before);
}

private void providerInsert(DataSource dataSource, long id, string name)
{
    auto owner = new Owner;
    owner.id = id;
    owner.name = name;
    owner.birthDate = LocalDate.of(1968, 2, 29);
    requireExpectedEntity(owner);
    auto connection = DataSourceUtils.getConnection(dataSource);
    scope (exit)
        DataSourceUtils.releaseConnection(connection, dataSource);
    auto statement = connection.prepareStatement("insert into jpa_seam_probe (id, name, birth_date) values (?, ?, ?)");
    scope (exit)
        statement.close();
    auto idValue = ownerMapping.attributes[0].read(owner);
    auto nameValue = ownerMapping.attributes[1].read(owner);
    const birthDate = ownerMapping.attributes[2].read(owner);
    assert(idValue.ok && nameValue.ok && birthDate.ok);
    statement.setLong(1, idValue.value.integer);
    statement.setString(2, nameValue.value.text);
    ownerCodec.write(statement, 3, birthDate.value);
    assert(statement.executeUpdate() == 1);
}

private void verifyOwnerParameters(DataSource dataSource)
{
    static immutable ParameterBinding[] bindings = [
        ParameterBinding(0, 3), ParameterBinding(1, 2), ParameterBinding(2, 1)
    ];
    const required = planParameters(&ownerMapping, bindings, ownerCodec);
    assert(required.ok);

    EntityMapping nullableMapping = ownerMapping;
    auto attributes = nullableMapping.attributes.dup;
    attributes[1].columnNullable = true;
    nullableMapping.attributes = attributes.idup;
    const mappings = [nullableMapping].idup;
    const nullable = planParameters(&mappings[0], bindings, ownerCodec);
    assert(nullable.ok);

    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    enum sql = "select cast(? as date), cast(? as text), cast(? as bigint)";
    auto owner = new Owner;
    owner.id = 17;
    owner.birthDate = LocalDate.of(1968, 2, 29);
    {
        auto rejected = connection.prepareStatement(sql);
        scope (exit)
            rejected.close();
        assert(bindParameters(required.value, rejected, new DerivedOwner).code == Status.invalidArgument);
        const error = bindParameters(required.value, rejected, owner);
        assert(error.code == Status.invalidArgument && error.offset == 1);
    }

    auto statement = connection.prepareStatement(sql);
    scope (exit)
        statement.close();
    foreach (name; [null, "Seventeen"])
    {
        owner.name = name;
        assert(bindParameters(nullable.value, statement, owner).code == Status.ok);
        auto rows = statement.executeQuery();
        scope (exit)
            rows.close();
        assert(rows.next());
        assert(rows.getObject!LocalDate(1) == owner.birthDate);
        assert(rows.getString(2) == name && rows.wasNull() == (name is null));
        assert(rows.getLong(3) == owner.id);
    }
}

private final class ContextProbe : TransactionSynchronization
{
    private Object key;
    private DataSource dataSource;
    private long pid;
    private bool retired;
    long pendingId = 2;
    int completion = -1;
    bool flushed;
    bool completedBeforeConnectionRelease;

    this(Object key, DataSource dataSource, long pid)
    {
        this.key = key;
        this.dataSource = dataSource;
        this.pid = pid;
        TransactionSynchronizationManager.bindResource(key, this);
        TransactionSynchronizationManager.registerSynchronization(this);
    }

    override void suspend()
    {
        assert(TransactionSynchronizationManager.unbindResource(key) is this);
    }

    override void resume()
    {
        TransactionSynchronizationManager.bindResource(key, this);
    }

    override int getOrder()
    {
        return DataSourceUtils.CONNECTION_SYNCHRONIZATION_ORDER - 100;
    }

    override void flush()
    {
        if (!TransactionSynchronizationManager.isActualTransactionActive())
            throw new Exception("flush requires an active transaction");
        try
            flushPending();
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

    private void flushPending()
    {
        if (flushed || pendingId == 0)
            return;
        assert(TransactionSynchronizationManager.getResource(key) is this);
        assert(providerQuery(dataSource, backendPid) == pid);
        providerInsert(dataSource, pendingId, "Two");
        flushed = true;
    }

    override void beforeCompletion()
    {
        if (TransactionSynchronizationManager.isActualTransactionActive())
            return;
        completedBeforeConnectionRelease = TransactionSynchronizationManager.hasResource(cast(Object) dataSource);
        retire();
    }

    override void afterCompletion(int status)
    {
        completion = status;
        if (status != STATUS_COMMITTED)
            flushed = false;
        if (!retired)
            retire();
    }

    private void retire()
    {
        assert(TransactionSynchronizationManager.unbindResource(key) is this);
        pendingId = 0;
        retired = true;
    }
}

private RowMaterializationPlan verifyMappingContract()
{
    assert(planResult(null, ownerBindings).error.code == Status.invalidArgument);
    assert(planResult(&ownerMapping, [ResultBinding(1, 1)]).error.code == Status.invalidArgument);
    assert(planResult(&ownerMapping, [ResultBinding(1, 1), ResultBinding(1, 2), ResultBinding(0, 3)], ownerCodec)
            .error.code == Status.invalidArgument);
    assert(planResult(&ownerMapping, [ResultBinding(1, 1), ResultBinding(2, 2), ResultBinding(0, 0)], ownerCodec)
            .error.code == Status.invalidArgument);
    static immutable EntityMapping[] descriptors = [ownerMapping];
    const registered = registerMappings(descriptors, [typeid(Owner)]);
    assert(registered.ok);
    auto owner = new Owner;
    auto derived = new DerivedOwner;
    const before = GC.stats().allocatedInCurrentThread;
    const mapping = registered.value.findExactObject(owner);
    assert(registered.value.findExactObject(derived) is null);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(mapping is &descriptors[0] && mapping is registered.value.findType("app.Owner"));
    assert(mapping is registered.value.findEntity("Owner"));
    const planned = planResult(mapping, ownerBindings, ownerCodec);
    assert(planned.ok);
    assert(validateMapping(ownerMapping).code == Status.ok);
    assert(validateEntity(ownerMapping, new Owner).code == Status.ok);
    assert(validateEntity(ownerMapping, new OwnerBase).code == Status.invalidArgument);
    assert(validateEntity(ownerMapping, new DerivedOwner).code == Status.invalidArgument);
    assert(validateEntity(ownerMapping, null).code == Status.invalidArgument);

    EntityMapping broken = ownerMapping;
    broken.idOrdinals = [3];
    assert(validateMapping(broken).code == Status.invalidArgument);
    broken.idOrdinals = [0, 0];
    assert(validateMapping(broken).code == Status.invalidArgument);
    broken.idOrdinals = [0];
    broken.versionOrdinal = 0;
    assert(validateMapping(broken).code == Status.invalidArgument);
    broken.versionOrdinal = 3;
    assert(validateMapping(broken).code == Status.invalidArgument);
    return planned.value;
}

private void verifyFlushFailure(FlintDataSource dataSource, TransactionTemplate transaction, bool explicit)
{
    auto key = new Object;
    ContextProbe context;
    bool rejected;
    try
    {
        transaction.executeWithoutResult((TransactionStatus status) {
            assert(status.isNewTransaction());
            context = new ContextProbe(key, dataSource, providerQuery(dataSource, backendPid));
            providerInsert(dataSource, 10, "will roll back");
            context.pendingId = 1;
            if (explicit)
            {
                try
                {
                    context.flush();
                    assert(false, "duplicate insert must fail");
                }
                catch (SQLException failure)
                    assert(failure.getSQLState() == "23505");
            }
        });
    }
    catch (UnexpectedRollbackException failure)
    {
        assert(explicit);
        rejected = true;
    }
    catch (SQLException failure)
    {
        assert(!explicit && failure.getSQLState() == "23505");
        rejected = true;
    }
    assert(rejected);
    assert(!context.flushed && context.completion == TransactionSynchronization.STATUS_ROLLED_BACK);
    assert(!TransactionSynchronizationManager.hasResource(key));
    assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
    assert(providerQuery(dataSource, "select count(*) from jpa_seam_probe where id = 10") == 0);
}

private void verifySynchronizationOnly(FlintDataSource dataSource,
        DataSourceTransactionManager manager, JdbcTemplate jdbc)
{
    auto supports = new TransactionTemplate(manager);
    supports.setPropagationBehavior(TransactionDefinition.PROPAGATION_SUPPORTS);
    auto key = new Object;
    ContextProbe context;
    supports.executeWithoutResult((TransactionStatus status) {
        assert(!status.isNewTransaction());
        assert(!TransactionSynchronizationManager.isActualTransactionActive());
        const pid = jdbc.queryForObject!long(backendPid);
        context = new ContextProbe(key, dataSource, pid);
        assert(providerQuery(dataSource, backendPid) == pid);
    });
    assert(context.completedBeforeConnectionRelease && !context.flushed);
    assert(context.completion == TransactionSynchronization.STATUS_COMMITTED);
    assert(!TransactionSynchronizationManager.hasResource(key));
    assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
}

private void verifySingleConnectionTimeout()
{
    auto dataSource = new FlintDataSource(environment.get("POSTGRES_URL"));
    dataSource.setUsername(environment.get("POSTGRES_USER"));
    dataSource.setPassword(environment.get("POSTGRES_PASS"));
    dataSource.setMaximumPoolSize(1);
    dataSource.setConnectionTimeout(100);
    scope (exit)
        dataSource.close();
    auto manager = new DataSourceTransactionManager(dataSource);
    auto outer = new TransactionTemplate(manager);
    auto inner = new TransactionTemplate(manager);
    inner.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    auto key = new Object;
    outer.executeWithoutResult((TransactionStatus status) {
        const pid = providerQuery(dataSource, backendPid);
        auto context = new ContextProbe(key, dataSource, pid);
        bool exhausted;
        try
        {
            inner.executeWithoutResult((TransactionStatus) {
                assert(false, "the sole connection should still belong to the outer transaction");
            });
        }
        catch (CannotCreateTransactionException)
            exhausted = true;
        assert(exhausted);
        assert(TransactionSynchronizationManager.getResource(key) is context);
        assert(providerQuery(dataSource, backendPid) == pid);
        status.setRollbackOnly();
    });
    assert(!TransactionSynchronizationManager.hasResource(key));
    assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
    assert(providerQuery(dataSource, backendPid) > 0);
}

private final class InterleavedTransactions
{
    private DataSource dataSource;
    private TransactionTemplate transaction;
    private Object key;
    private long[2] pids;
    private ContextProbe[2] contexts;
    uint arrived;
    uint finished;
    Exception failure;

    this(DataSource dataSource, TransactionTemplate transaction)
    {
        this.dataSource = dataSource;
        this.transaction = transaction;
        key = new Object;
    }

    void step() nothrow
    {
        auto owner = Reactor.current();
        try
            transact();
        catch (Exception caught)
        {
            failure = caught;
            owner.stop();
            return;
        }
        if (++finished == 2)
            owner.stop();
    }

    private void transact()
    {
        auto owner = Reactor.current();
        const index = cast(size_t) owner.currentTask().value.requestId;
        transaction.executeWithoutResult((TransactionStatus status) {
            assert(status.isNewTransaction());
            assert(!TransactionSynchronizationManager.hasResource(key));
            auto jdbc = new JdbcTemplate(dataSource);
            pids[index] = jdbc.queryForObject!long(backendPid);
            contexts[index] = new ContextProbe(key, dataSource, pids[index]);
            contexts[index].pendingId = 0;
            ++arrived;
            const expires = Deadline.afterMillis(3_000).monotonicNanoseconds;
            while (arrived < 2)
            {
                if (Deadline.afterMillis(0).monotonicNanoseconds >= expires)
                    throw new Exception("the other transaction did not reach the barrier");
                assert(owner.yieldUntil(Deadline.afterMillis(1)).code == Status.ok);
            }
            assert(contexts[0]!is contexts[1] && pids[0] != pids[1]);
            assert(TransactionSynchronizationManager.getResource(key) is contexts[index]);
            assert(providerQuery(dataSource, backendPid) == pids[index]);
        });
        assert(contexts[index].completion == TransactionSynchronization.STATUS_COMMITTED);
        assert(!TransactionSynchronizationManager.hasResource(key));
        assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
    }
}

private void verifyInterleavedTransactions(DataSource dataSource, TransactionTemplate transaction) @system
{
    ReactorOptions options;
    options.backend = Backend.epoll;
    options.cores = 1;
    options.fiberPoolSize = 2;
    auto reactor = Reactor.create(options);
    assert(reactor.ok);
    auto fixture = new InterleavedTransactions(dataSource, transaction);
    // Test harness only, as in tx/tests/synchronization_manager.d. JDBC and tx façades may allocate.
    auto task = cast(TaskDelegate)&fixture.step;
    foreach (index; 0 .. 2)
        assert(reactor.value.postStartup(0, task, TaskContext(index)).code == Status.ok);
    assert(reactor.value.run().code == Status.ok);
    if (fixture.failure !is null)
        throw fixture.failure;
    assert(fixture.arrived == 2 && fixture.finished == 2);
}

void main() @system
{
    const ownerPlan = verifyMappingContract();
    enablePostgres();
    auto dataSource = new FlintDataSource(environment.get("POSTGRES_URL"));
    dataSource.setUsername(environment.get("POSTGRES_USER"));
    dataSource.setPassword(environment.get("POSTGRES_PASS"));
    dataSource.setMaximumPoolSize(2);
    dataSource.setConnectionTimeout(1_000);
    scope (exit)
        dataSource.close();

    verifyTimestampMapping(dataSource);
    verifyOwnerParameters(dataSource);
    auto jdbc = new JdbcTemplate(dataSource);
    jdbc.execute(
            "create table jpa_seam_probe (id bigint primary key, name text not null, " ~ "birth_date date not null)");
    auto manager = new DataSourceTransactionManager(dataSource);
    auto outer = new TransactionTemplate(manager);
    auto inner = new TransactionTemplate(manager);
    inner.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    auto key = new Object;
    ContextProbe outerContext;
    ContextProbe innerContext;
    Owner materialized;

    outer.executeWithoutResult((TransactionStatus status) {
        assert(status.isNewTransaction());
        const outerPid = jdbc.queryForObject!long(backendPid);
        assert(providerQuery(dataSource, backendPid) == outerPid);
        outerContext = new ContextProbe(key, dataSource, outerPid);
        providerInsert(dataSource, 1, "One");
        materialized = providerLoadOwner(dataSource, ownerPlan, 1);
        assert(materialized.loadOrder == 3);
        verifyManagedIdentity(dataSource);
        verifyDirtySnapshots(materialized);
        requireNullRejection(dataSource, ownerPlan,
            "select name, birth_date, null::bigint from jpa_seam_probe where id = ?", "id");
        requireNullRejection(dataSource, ownerPlan,
            "select name, null::date, id from jpa_seam_probe where id = ?", "birthDate");
        assert(jdbc.queryForObject!long("select count(*) from jpa_seam_probe") == 1);

        inner.executeWithoutResult((TransactionStatus nested) {
            assert(!TransactionSynchronizationManager.hasResource(key));
            const innerPid = jdbc.queryForObject!long(backendPid);
            assert(innerPid != outerPid && providerQuery(dataSource, backendPid) == innerPid);
            innerContext = new ContextProbe(key, dataSource, innerPid);
            assert(jdbc.queryForObject!long("select count(*) from jpa_seam_probe") == 0);
            providerInsert(dataSource, 3, "Three");
            nested.setRollbackOnly();
        });

        assert(!innerContext.flushed && innerContext.completion == TransactionSynchronization.STATUS_ROLLED_BACK);
        assert(TransactionSynchronizationManager.getResource(key) is outerContext);
        assert(jdbc.queryForObject!long(backendPid) == outerPid);
    });

    assert(materialized.id == 1 && materialized.name == "One");
    assert(materialized.birthDate == LocalDate.of(1968, 2, 29));
    const birthDate = ownerMapping.attributes[2].read(materialized);
    assert(birthDate.ok && birthDate.value.integer == materialized.birthDate.toEpochDay());
    assert(outerContext.flushed && outerContext.completion == TransactionSynchronization.STATUS_COMMITTED);
    assert(!TransactionSynchronizationManager.hasResource(key));
    assert(!TransactionSynchronizationManager.hasResource(cast(Object) dataSource));
    assert(jdbc.queryForObject!long("select sum(id)::bigint from jpa_seam_probe") == 3);
    verifyFlushFailure(dataSource, outer, true);
    verifyFlushFailure(dataSource, outer, false);
    verifySynchronizationOnly(dataSource, manager, jdbc);
    verifyInterleavedTransactions(dataSource, outer);
    verifySingleConnectionTimeout();
}
