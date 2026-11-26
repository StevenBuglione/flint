/// Renders immutable Jakarta entity tables and safe accessors in a generated source unit.
module flint_tool.engine.aot.jpa_emit;

import flint_tool.engine.aot.conditions : literal;
import flint_tool.engine.aot.jpa : JpaField, JpaFieldKind, JpaMapping;
import std.conv : to;

@safe:

/// The typed DATE reader and writer are linked only by a unit whose mappings use DATE.
bool usesJpaDate(scope const(JpaMapping)[] mappings) pure nothrow @nogc
{
    foreach (ref mapping; mappings)
        foreach (ref field; mapping.fields)
            if (field.kind == JpaFieldKind.date)
                return true;
    return false;
}

/// Emits one mapping accessor for this source unit and the thunks its tables reference.
string renderJpa(const(JpaMapping)[] mappings)
{
    string declarations;
    string tables;
    foreach (index, ref mapping; mappings)
    {
        const suffix = index.to!string;
        declarations ~= "private Object jpaConstruct_" ~ suffix ~ "()\n{\n    return new " ~ mapping.type ~ ";\n}\n\n"
            ~ "private bool jpaExact_" ~ suffix ~ "(scope const TypeInfo_Class type) nothrow @nogc\n{\n"
            ~ "    return type is typeid(" ~ mapping.type ~ ");\n}\n\n";
        string attributes;
        foreach (ordinal, ref field; mapping.fields)
        {
            const id = suffix ~ "_" ~ ordinal.to!string;
            declarations ~= renderField(mapping.type, field, id);
            attributes ~= attributeLiteral(field, ordinal, id);
        }
        string[] callbacks;
        foreach (number, ref callback; mapping.postLoad)
        {
            const name = "jpaPostLoad_" ~ suffix ~ "_" ~ number.to!string;
            callbacks ~= "&" ~ name;
            const receiver = "cast(" ~ mapping.type ~ ") object";
            const argument = callback.parameterType == "object.Object" ? "object" : receiver;
            const call = callback.listener.length ? "flint.engine.aot.objects.statelessInstance!("
                ~ callback.listener ~ ")()." ~ callback.method ~ "(" ~ argument ~ ")" : "(" ~ receiver
                ~ ")." ~ callback.method ~ "()";
            declarations ~= "private void " ~ name ~ "(Object object)\n{\n    " ~ call ~ ";\n}\n\n";
        }
        import std.array : join;

        tables ~= "    EntityMapping(entityName: " ~ literal(mapping.name) ~ ", typeName: " ~ literal(
                mapping.type) ~ ", table: " ~ literal(
                mapping.table) ~ ",\n        attributes: [\n" ~ attributes
            ~ "        ], construct: &jpaConstruct_" ~ suffix ~ ", isExactType: &jpaExact_" ~ suffix
            ~ ", idOrdinals: [" ~ mapping.id.to!string ~ "], postLoad: [" ~ callbacks.join(", ") ~ "]),\n";
    }
    return declarations ~ "private immutable(EntityMapping)[] jpaTables = [\n" ~ tables ~ "];\n\n"
        ~ "immutable(EntityMapping)[] jpaMappings() nothrow @nogc\n{\n    return jpaTables;\n}\n\n" ~ (
                usesJpaDate(mappings) ? dateCodec : "");
}

private string kindName(JpaFieldKind kind)
{
    final switch (kind)
    {
    case JpaFieldKind.integer:
        return "integer";
    case JpaFieldKind.text:
        return "text";
    case JpaFieldKind.date:
        return "date";
    }
}

private string sqlType(JpaFieldKind kind)
{
    final switch (kind)
    {
    case JpaFieldKind.integer:
        return "BIGINT";
    case JpaFieldKind.text:
        return "VARCHAR";
    case JpaFieldKind.date:
        return "DATE";
    }
}

private string attributeLiteral(const ref JpaField field, size_t ordinal, string id)
{
    return "            AttributeMapping(ordinal: " ~ ordinal.to!string ~ ", name: " ~ literal(
            field.name) ~ ", column: " ~ literal(field.column) ~ ", kind: AttributeKind." ~ kindName(
            field.kind) ~ ", read: &jpaRead_" ~ id ~ ", write: &jpaWrite_" ~ id ~ ", columnNullable: "
        ~ field.nullable.to!string ~ ", acceptsNull: " ~ (field.kind == JpaFieldKind.text)
            .to!string ~ ", insertable: " ~ field.insertable.to!string ~ ", updatable: "
            ~ field.updatable.to!string ~ ", columnLength: " ~ field.length.to!string
            ~ ", sqlType: Types." ~ sqlType(field.kind) ~ "),\n";
}

private string renderField(string type, const ref JpaField field, string id)
{
    const member = "entity." ~ field.name;
    string read, write;
    final switch (field.kind)
    {
    case JpaFieldKind.integer:
        read = "    value.integer = " ~ member ~ ";\n";
        write = "value.integer";
        break;
    case JpaFieldKind.text:
        read = "    value.text = " ~ member ~ ";\n"
            ~ "    if (value.text is null)\n        value.kind = AttributeKind.nullValue;\n";
        write = "value.text";
        break;
    case JpaFieldKind.date:
        read = "    value.integer = " ~ member ~ ".toEpochDay();\n";
        write = "LocalDate.ofEpochDay(value.integer)";
        break;
    }
    const castEntity = "    auto entity = cast(" ~ type ~ ") object;\n";
    const wrongType = "Error(Status.invalidArgument, \"wrong JPA entity type\")";
    const readThunk = "private Result!AttributeValue jpaRead_" ~ id
        ~ "(Object object) nothrow @nogc\n{\n" ~ castEntity
        ~ "    if (entity is null)\n        return Result!AttributeValue(AttributeValue.init, "
        ~ wrongType ~ ");\n" ~ "    AttributeValue value;\n    value.kind = AttributeKind." ~ kindName(
                field.kind) ~ ";\n" ~ read ~ "    return Result!AttributeValue(value);\n}\n\n";
    return readThunk ~ "private void jpaWrite_" ~ id ~ "(Object object, const ref AttributeValue value)\n{\n"
        ~ castEntity ~ "    " ~ member ~ " = " ~ write ~ ";\n}\n\n";
}

private enum dateCodec = `
private AttributeValue jpaReadDate(ResultSet row, int column, AttributeKind kind)
{
    assert(kind == AttributeKind.date);
    AttributeValue value;
    value.kind = kind;
    value.integer = row.getObject!LocalDate(column).toEpochDay();
    return value;
}

private void jpaWriteDate(PreparedStatement statement, int parameter, scope const ref AttributeValue value)
{
    assert(value.kind == AttributeKind.date);
    statement.setObject(parameter, Any.of(LocalDate.ofEpochDay(value.integer)));
}

TypedColumnCodec jpaTypedCodec() nothrow @nogc
{
    return TypedColumnCodec(read: &jpaReadDate, write: &jpaWriteDate);
}

`;
