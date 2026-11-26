/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.procedure_options_test;

import flint.jakarta.persistence : NamedStoredProcedureQueries, NamedStoredProcedureQuery, ParameterMode,
    PersistenceUnitTransactionType, QueryHint, SharedCacheMode, StoredProcedureParameter, ValidationMode;
import flint.jakarta.persistence.spi : LoadState;
import flint.java.classref : classOf;
import std.traits : EnumMembers;

@safe:

private class Owner
{
}

@("a stored procedure query can omit its result shape and use default input parameters")
unittest
{
    enum query = NamedStoredProcedureQuery("refresh", "refresh_owners");
    static assert(query.parameters.length == 0 && query.hints.length == 0);
    static assert(query.resultClasses.length == 0 && query.resultSetMappings.length == 0);

    enum parameter = StoredProcedureParameter(type: classOf!long);
    static assert(parameter.name == "" && parameter.mode == ParameterMode.IN);
    static assert(parameter.type == classOf!long);
}

@("grouped procedure queries preserve parameter order and each result declaration")
unittest
{
    enum ownerId = StoredProcedureParameter("owner_id", ParameterMode.IN, classOf!long);
    enum cursor = StoredProcedureParameter("result", ParameterMode.REF_CURSOR, classOf!Owner);
    enum hint = QueryHint(name: "jakarta.persistence.query.timeout", value: "100");
    enum typed = NamedStoredProcedureQuery("find", "owners", [ownerId, cursor], [classOf!Owner]);
    enum mapped = NamedStoredProcedureQuery("summary", "report", [], [], ["owner.summary"], [hint]);

    @NamedStoredProcedureQueries([typed, mapped])
    static class Procedures
    {
    }

    enum queries = __traits(getAttributes, Procedures)[0].value;
    static assert(queries.length == 2 && queries[0].parameters.length == 2);
    static assert(queries[0].parameters[0] == ownerId && queries[0].parameters[1] == cursor);
    static assert(queries[0].resultClasses == [classOf!Owner]);
    static assert(queries[1].procedureName == "report" && queries[1].resultClasses.length == 0);
    static assert(queries[1].resultSetMappings == ["owner.summary"]);
    static assert(queries[1].hints[0].value == "100");
}

@("bootstrap modes and the SPI load state keep the Jakarta declaration order")
unittest
{
    static assert([EnumMembers!PersistenceUnitTransactionType] == [
        PersistenceUnitTransactionType.JTA, PersistenceUnitTransactionType.RESOURCE_LOCAL
    ]);
    static assert([EnumMembers!SharedCacheMode] == [
        SharedCacheMode.ALL, SharedCacheMode.NONE, SharedCacheMode.ENABLE_SELECTIVE,
        SharedCacheMode.DISABLE_SELECTIVE, SharedCacheMode.UNSPECIFIED
    ]);
    static assert([EnumMembers!ValidationMode] == [
        ValidationMode.AUTO, ValidationMode.CALLBACK, ValidationMode.NONE
    ]);
    static assert([EnumMembers!LoadState] == [
        LoadState.LOADED, LoadState.NOT_LOADED, LoadState.UNKNOWN
    ]);
}
