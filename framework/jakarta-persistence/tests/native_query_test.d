/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.native_query_test;

import flint.jakarta.persistence : ColumnResult, ConstructorResult, EntityResult, FieldResult, LockModeType,
    NamedNativeQueries, NamedNativeQuery, QueryHint, SqlResultSetMapping, SqlResultSetMappings;
import flint.java.classref : ClassRef, classOf;

@safe:

private class Owner
{
}

private struct OwnerSummary
{
}

@("native query and result mapping defaults leave the result type and shape unspecified")
unittest
{
    enum query = NamedNativeQuery("owners", "select * from owners");
    static assert(query.hints.length == 0 && query.resultClass.name == "" && query.resultSetMapping == "");
    static assert(query.entities.length == 0 && query.classes.length == 0 && query.columns.length == 0);

    enum mapping = SqlResultSetMapping("owner");
    static assert(mapping.entities.length == 0 && mapping.classes.length == 0 && mapping.columns.length == 0);
    enum entity = EntityResult(classOf!Owner);
    static assert(entity.entityClass == classOf!Owner && entity.lockMode == LockModeType.OPTIMISTIC);
    static assert(entity.fields.length == 0 && entity.discriminatorColumn == "");
    static assert(ColumnResult("owner_id").type.name == "");
}

@("grouped native query metadata retains named and inline mappings in constructor column order")
unittest
{
    enum field = FieldResult("id", "owner_id");
    enum entity = EntityResult(classOf!Owner, LockModeType.NONE, [field], "owner_type");
    enum id = ColumnResult("owner_id", classOf!long);
    enum name = ColumnResult("owner_name", classOf!string);
    enum summary = ConstructorResult(classOf!OwnerSummary, [id, name]);
    enum ownerMapping = SqlResultSetMapping("owner.summary", [entity], [summary], [name]);
    enum sql = "select * from owners";
    enum named = NamedNativeQuery("named", sql, resultSetMapping: "owner.summary");
    enum hint = QueryHint(name: "org.hibernate.readOnly", value: "true");
    enum inlineQuery = NamedNativeQuery("inline", sql, [hint], ClassRef.init, "",
                ownerMapping.entities, ownerMapping.classes, ownerMapping.columns);
    enum typed = NamedNativeQuery("entity", sql, resultClass: classOf!Owner);

    @SqlResultSetMappings([ownerMapping, SqlResultSetMapping("owner.scalar", columns: [id])])
    @NamedNativeQueries([named, inlineQuery, typed])
    static class Queries
    {
    }

    enum metadata = __traits(getAttributes, Queries);
    enum mappings = metadata[0].value;
    enum queries = metadata[1].value;
    static assert(mappings.length == 2 && queries.length == 3);
    static assert(queries[0].resultSetMapping == mappings[0].name);
    static assert(queries[1].query == sql && queries[1].resultSetMapping == "");
    static assert(queries[2].resultClass == classOf!Owner);
    static assert(queries[1].hints[0].name == "org.hibernate.readOnly" && queries[1].hints[0].value == "true");
    static assert(queries[1].entities[0].discriminatorColumn == "owner_type");
    static assert(queries[1].entities[0].fields[0].name == "id");
    static assert(queries[1].entities[0].fields[0].column == "owner_id");
    static assert(queries[1].classes[0].targetClass == classOf!OwnerSummary);
    static assert(queries[1].classes[0].columns[0].type == classOf!long);
    static assert(queries[1].classes[0].columns[1].type == classOf!string);
    static assert(queries[1].columns[0].name == "owner_name" && mappings[1].columns[0].name == "owner_id");
}
