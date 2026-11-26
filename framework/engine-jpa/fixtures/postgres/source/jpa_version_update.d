/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module jpa_version_update;

import flint.arena : Error, Result, Status;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping, ResultBinding;
import flint.engine.jpa.identity : EntityIdentity, IdentitySlot;
import flint.engine.jpa.loaded_state : ManagedSnapshotSlot;
import flint.engine.jpa.managed_entities : ManagedEntities;
import flint.engine.jpa.parameter_binding : ParameterBinding;
import flint.engine.jpa.result_binding : materializeManagedRow, planManagedResult;
import flint.engine.jpa.snapshot : AttributeSnapshot;
import flint.engine.jpa.update : VersionBindings, executeManagedUpdate, executeVersionedUpdate, planUpdate;
import flint.java.sql : Connection, Types;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcTemplate;

@safe:

private final class VersionedOwner
{
    long id;
    string name;
    long revision;
}

private alias AttrResult = Result!AttributeValue;

private AttrResult readId(Object entity) nothrow @nogc
{
    return AttrResult(AttributeValue(AttributeKind.integer, (cast(VersionedOwner) entity).id));
}

private AttrResult readName(Object entity) nothrow @nogc
{
    return AttrResult(AttributeValue(kind: AttributeKind.text, text: (cast(VersionedOwner) entity).name));
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
                (cast(VersionedOwner) entity).revision = value.integer;
            })
], construct: () => new VersionedOwner, isExactType: (scope const TypeInfo_Class candidate) => candidate is typeid(
            VersionedOwner), idOrdinals: [0], versionOrdinal: 2);

private enum selectRows = "select version, name, id from jpa_version_probe order by id";
private enum updateRow = "update jpa_version_probe set version = ?, name = ? where version = ? and id = ?";

private void assertStored(Connection connection, string name, long revision)
{
    auto statement = connection.prepareStatement("select name, version from jpa_version_probe where id = 1");
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());
    assert(rows.getString(1) == name && rows.getLong(2) == revision);
}

/// Exercises real optimistic predicates, rollback and version exhaustion on PostgreSQL.
void verifyVersionedUpdate(DataSource dataSource, JdbcTemplate jdbc)
{
    jdbc.execute("create table jpa_version_probe (id bigint primary key, name text not null, version bigint not null)");
    jdbc.execute("insert into jpa_version_probe values (1, 'Original', 7), (2, 'Limit', 9223372036854775807)");
    static immutable ResultBinding[] projection = [
        ResultBinding(2, 1), ResultBinding(1, 2), ResultBinding(0, 3)
    ];
    static immutable ParameterBinding[] parameters = [ParameterBinding(1, 2)];
    const rows = planManagedResult(&mapping, projection, 0);
    const plan = planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 3));
    assert(rows.ok && plan.ok);
    assert(planUpdate(&mapping, updateRow, parameters, 4).error.code == Status.unsupported);
    assert(planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 1)).error.code == Status.invalidArgument);
    assert(planUpdate(&mapping, updateRow, parameters, 4, VersionBindings(1, 2)).error.code == Status.invalidArgument);

    IdentitySlot[2] identities;
    Object[2] roots;
    auto fields = new AttributeSnapshot[6];
    auto bytes = new ubyte[32];
    ManagedSnapshotSlot[2] snapshots = [
        ManagedSnapshotSlot(fields[0 .. 3], bytes[0 .. 16]),
        ManagedSnapshotSlot(fields[3 .. 6], bytes[16 .. 32])
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

    enum key = EntityIdentity(0, 1);
    enum limitKey = EntityIdentity(0, 2);
    {
        auto statement = connection.prepareStatement(selectRows);
        scope (exit)
            statement.close();
        auto result = statement.executeQuery();
        scope (exit)
            result.close();
        assert(result.next());
        const first = materializeManagedRow(rows.value, result, managed);
        assert(first.ok && result.next());
        const second = materializeManagedRow(rows.value, result, managed);
        assert(second.ok);
    }

    auto owner = cast(VersionedOwner) managed.find(key).value;
    auto limit = cast(VersionedOwner) managed.find(limitKey).value;
    uint[1] ordinals;
    owner.revision = 100;
    const clean = executeVersionedUpdate(plan.value, connection, managed, key, ordinals[]);
    assert(clean.ok && !clean.value.updated);
    owner.name = "Edited";
    const dirty = managed.dirty(key, ordinals[]);
    assert(dirty.ok && dirty.value == 1 && ordinals[0] == 1);
    assert(executeManagedUpdate(plan.value, connection, managed, key, ordinals[]).error.code == Status.invalidArgument);
    const written = executeVersionedUpdate(plan.value, connection, managed, key, ordinals[]);
    assert(written.ok && written.value.updated && written.value.nextVersion == 8);
    assert(owner.revision == 100);
    assertStored(connection, "Edited", 8);
    connection.rollback();
    assertStored(connection, "Original", 7);

    // This uses another pool lease and commits before the older loaded snapshot writes.
    jdbc.execute("update jpa_version_probe set name = 'Winner', version = 8 where id = 1");
    const stale = executeVersionedUpdate(plan.value, connection, managed, key, ordinals[]);
    assert(stale.error.code == Status.conflict);
    assertStored(connection, "Winner", 8);
    assert(owner.revision == 100 && managed.dirty(key, ordinals[]).value == 1);

    limit.name = "Overflow";
    const overflow = executeVersionedUpdate(plan.value, connection, managed, limitKey, ordinals[]);
    assert(overflow.error.code == Status.resourceExhausted && overflow.error.offset == 2);
}
