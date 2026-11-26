/* Copyright (c) 2026 the Flint authors. SPDX-License-Identifier: Apache-2.0 */

/// Verifies the application-supplied TIMESTAMP codec on the pinned peer.
module jpa_timestamp;

import core.memory : GC;
import flint.arena : Result, Status;
import flint.engine.aot.any : Any;
import flint.engine.jpa : AttributeKind, AttributeMapping, AttributeValue, EntityMapping,
    ResultBinding, RowMaterializationPlan, TypedColumnCodec, materializeRow, planResult;
import flint.engine.jpa.parameter_binding : ParameterBinding, ParameterBindingPlan, bindParameters, planParameters;
import flint.engine.jpa.timestamp : decodeTimestampMicros, encodeTimestampMicros;
import flint.java.sql : PreparedStatement, ResultSet, Types;
import flint.java.time : LocalDate, LocalDateTime, LocalTime;
import flint.javax.sql : DataSource;

@safe:

private final class AuditRecord
{
    long id;
    LocalDateTime recordedAt;
}

private Result!long epochMicros(LocalDateTime value) pure nothrow @nogc
{
    return encodeTimestampMicros(value.toLocalDate().toEpochDay(), value.toLocalTime().toNanoOfDay());
}

private LocalDateTime fromEpochMicros(long value)
{
    const decoded = decodeTimestampMicros(value);
    if (!decoded.ok)
        throw new Exception(decoded.error.message);
    return LocalDateTime.of(LocalDate.ofEpochDay(decoded.value.epochDay),
            LocalTime.ofNanoOfDay(decoded.value.nanoOfDay));
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
    const encoded = epochMicros(recordedAt);
    return Result!AttributeValue(AttributeValue(AttributeKind.timestamp, encoded.value), encoded.error);
}

private void writeTimestamp(Object entity, const ref AttributeValue value)
{
    (cast(AuditRecord) entity).recordedAt = fromEpochMicros(value.integer);
}

private AttributeValue readColumn(ResultSet row, int column, AttributeKind kind)
{
    assert(kind == AttributeKind.timestamp);
    const encoded = epochMicros(row.getObject!LocalDateTime(column));
    if (!encoded.ok)
        throw new Exception(encoded.error.message);
    return AttributeValue(kind, encoded.value);
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
    static immutable ParameterBinding[] parameters = [ParameterBinding(1, 1)];
    const writePlan = planParameters(&mapping, parameters, codec);
    assert(writePlan.ok);
    const fractional = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 123_455_500);
    const rounded = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 123_456_000);
    verifyTimestampRow(statement, plan.value, writePlan.value, fractional, rounded, -876_544);
    const belowHalf = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 999_999_499);
    const beforeEpoch = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 999_999_000);
    verifyTimestampRow(statement, plan.value, writePlan.value, belowHalf, beforeEpoch, -1);
    const atHalf = LocalDateTime.of(1969, 12, 31, 23, 59, 59, 999_999_500);
    verifyTimestampRow(statement, plan.value, writePlan.value, atHalf, LocalDateTime.of(1970, 1, 1, 0, 0), 0);
    const first = LocalDateTime.of(1, 1, 1, 0, 0);
    verifyTimestampRow(statement, plan.value, writePlan.value, first, first, -62_135_596_800_000_000);
    const last = LocalDateTime.of(9999, 12, 31, 23, 59, 59, 999_999_000);
    verifyTimestampRow(statement, plan.value, writePlan.value, last, last, 253_402_300_799_999_999);

    auto writeRecord = new AuditRecord;
    writeRecord.recordedAt = LocalDateTime.of(9999, 12, 31, 23, 59, 59, 999_999_500);
    const overflow = bindParameters(writePlan.value, statement, writeRecord);
    assert(overflow.code == Status.invalidArgument && overflow.offset == 1);
}

private void verifyTimestampRow(PreparedStatement statement, scope const ref RowMaterializationPlan readPlan,
        scope const ref ParameterBindingPlan writePlan, LocalDateTime input, LocalDateTime expected, long micros)
{
    auto writeRecord = new AuditRecord;
    writeRecord.recordedAt = input;
    assert(bindParameters(writePlan, statement, writeRecord).code == Status.ok);
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    assert(rows.next());

    const before = GC.stats().allocatedInCurrentThread;
    const read = readColumn(rows, 1, AttributeKind.timestamp);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(read.integer == micros);
    const row = materializeRow(readPlan, rows);
    assert(row.ok);
    const audit = cast(const AuditRecord) row.value;
    assert(audit.id == 7 && audit.recordedAt == expected);

    assert(rows.next());
    const missing = materializeRow(readPlan, rows);
    assert(!missing.ok && missing.error.code == Status.invalidArgument && missing.error.offset == 1);
}
