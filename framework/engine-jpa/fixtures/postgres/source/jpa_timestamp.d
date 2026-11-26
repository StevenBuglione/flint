/* Copyright (c) 2026 the Flint authors. SPDX-License-Identifier: Apache-2.0 */

/// Verifies the application-supplied TIMESTAMP codec on the pinned peer.
module jpa_timestamp;

import core.memory : GC;
import flint.arena : Result, Status;
import flint.engine.aot.any : Any;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    ResultBinding, TypedColumnCodec, materializeRow, planResult;
import flint.java.sql : PreparedStatement, ResultSet, Types;
import flint.java.time : LocalDateTime, ZoneOffset;
import flint.javax.sql : DataSource;

@safe:

private enum microsPerSecond = 1_000_000;
private enum microsPerDay = 86_400L * microsPerSecond;

private final class AuditRecord
{
    long id;
    LocalDateTime recordedAt;
}

private long epochMicros(LocalDateTime value) pure nothrow @nogc
{
    return value.toLocalDate().toEpochDay() * microsPerDay + value.toLocalTime().toNanoOfDay() / 1_000;
}

private LocalDateTime fromEpochMicros(long value)
{
    auto seconds = value / microsPerSecond;
    auto micros = value % microsPerSecond;
    if (micros < 0)
    {
        --seconds;
        micros += microsPerSecond;
    }
    return LocalDateTime.ofEpochSecond(seconds, cast(int) micros * 1_000, ZoneOffset.UTC);
}

private enum auditType = "jpa_timestamp.AuditRecord";
private immutable EntityMapping mapping = EntityMapping(entityName: "AuditRecord", typeName: auditType,
    table: "audit_records", attributes: [
            AttributeMapping(ordinal: 0, name: "id", column: "id", kind: AttributeKind.integer,
            read: &readId, write: &writeId, sqlType: Types.BIGINT),
            AttributeMapping(ordinal: 1, name: "recordedAt", column: "recorded_at", kind: AttributeKind.timestamp,
            read: &readTimestamp, write: &writeTimestamp, sqlType: Types.TIMESTAMP)
], construct: () => new AuditRecord, isExactType: (scope const TypeInfo_Class type) => type is typeid(AuditRecord),
    idOrdinals: [0]);

private Result!AttributeValue readId(Object entity) nothrow @nogc
{
    return Result!AttributeValue(AttributeValue(AttributeKind.integer, (cast(AuditRecord) entity).id));
}

private void writeId(Object entity, const ref AttributeValue value)
{
    (cast(AuditRecord) entity).id = value.integer;
}

private Result!AttributeValue readTimestamp(Object entity) nothrow @nogc
{
    const recordedAt = (cast(AuditRecord) entity).recordedAt;
    return Result!AttributeValue(AttributeValue(AttributeKind.timestamp, epochMicros(recordedAt)));
}

private void writeTimestamp(Object entity, const ref AttributeValue value)
{
    (cast(AuditRecord) entity).recordedAt = fromEpochMicros(value.integer);
}

private AttributeValue readColumn(ResultSet row, int column, AttributeKind kind)
{
    assert(kind == AttributeKind.timestamp);
    return AttributeValue(kind, epochMicros(row.getObject!LocalDateTime(column)));
}

private void bindColumn(PreparedStatement statement, int index, scope const ref AttributeValue value)
{
    assert(value.kind == AttributeKind.timestamp);
    statement.setObject(index, Any.of(fromEpochMicros(value.integer)));
}

/// Checks fractional pre-epoch timestamps, projection order and NULL rejection.
void verifyTimestampMapping(DataSource dataSource)
{
    immutable TypedColumnCodec codec = TypedColumnCodec(&readColumn, &bindColumn, 1u << AttributeKind.timestamp);
    static immutable ResultBinding[] projection = [ResultBinding(1, 1), ResultBinding(0, 2)];
    const plan = planResult(&mapping, projection, codec);
    assert(plan.ok);

    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    auto statement = connection.prepareStatement(
            "select cast(? as timestamp), 7::bigint union all select null::timestamp, 8::bigint order by 2");
    scope (exit)
        statement.close();
    const expected = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 123_456_000);
    const encoded = AttributeValue(AttributeKind.timestamp, -876_544);
    codec.write(statement, 1, encoded);
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());

    const before = GC.stats().allocatedInCurrentThread;
    const read = codec.read(rows, 1, AttributeKind.timestamp);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(read.integer == encoded.integer);
    const row = materializeRow(plan.value, rows);
    assert(row.ok);
    const audit = cast(const AuditRecord) row.value;
    assert(audit.id == 7 && audit.recordedAt == expected);

    assert(rows.next());
    const missing = materializeRow(plan.value, rows);
    assert(!missing.ok && missing.error.code == Status.invalidArgument && missing.error.offset == 1);
}
