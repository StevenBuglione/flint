/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Provider-owned metadata for a compiled Jakarta Persistence mapping.
module flint.engine.jpa.mapping;

import flint.arena : Error, Result, Status;
import flint.jakarta.persistence : GenerationType;
import flint.java.sql : Types;

@safe:

/// Representation of one mapped database value at the entity boundary.
enum AttributeKind
{
    nullValue,
    integer,
    floatingPoint,
    boolean,
    text,
    binary,
}

/// A transient value for an entity read or write. Arena snapshots copy text and bytes into owned storage.
struct AttributeValue
{
    /// Identifies the value stored below.
    AttributeKind kind;
    /// A signed integer value.
    long integer;
    /// A floating-point value.
    double floatingPoint;
    /// A boolean value.
    bool boolean;
    /// Immutable UTF-8 text owned by the entity or the JDBC result.
    string text;
    /// The binary slice for this operation.
    const(ubyte)[] bytes;
}

/// One persistent attribute. Ordinals include inherited persistent attributes in order.
struct AttributeMapping
{
    /// Zero-based attribute index, including the persistent attributes of mapped superclasses.
    uint ordinal;
    /// Name of the field or property in the entity.
    string name;
    /// Name of the mapped SQL column.
    string column;
    /// The mapped value representation.
    AttributeKind kind;
    /// Reads a value from an instance of the mapped entity class.
    Result!AttributeValue function(Object) @safe nothrow @nogc read;
    /// Writes a value to the entity. Callers supply owned storage for any retained references.
    void function(Object, const ref AttributeValue) @safe write;
    /// The SQL column permits NULL values.
    bool columnNullable = true;
    /// The D attribute can represent a null separately from its ordinary values.
    bool acceptsNull;
    /// Include this column in generated inserts.
    bool insertable = true;
    /// Include this column in generated updates.
    bool updatable = true;
    /// Declared maximum length for a column whose type has a length.
    uint columnLength;
    /// The JDBC type code used by the dialect and binders.
    int sqlType = Types.OTHER;
}

/// A lifecycle callback, invoked at the public boundary after row values are owned.
alias LifecycleCallback = void function(Object) @safe;

/// One immutable entity mapping generated and registered at application startup.
struct EntityMapping
{
    /// Jakarta entity name used by JPQL.
    string entityName;
    /// Fully qualified D entity type name.
    string typeName;
    /// Primary SQL table for this entity.
    string table;
    /// Persistent attributes in inherited-first ordinal order.
    immutable(AttributeMapping)[] attributes;
    /// Constructs a GC-owned instance at the API boundary.
    Object function() @safe construct;
    /// PostLoad callbacks in listener, mapped-superclass, then entity order.
    immutable(LifecycleCallback)[] postLoad;
    /// Whether a class exactly matches the concrete class used by the accessors.
    bool function(scope const TypeInfo_Class) @safe nothrow @nogc isExactType;
    /// Attribute ordinals that form the primary key, in key order.
    immutable(uint)[] idOrdinals;
    /// Attribute ordinal used for optimistic locking. An absent version uses uint.max.
    uint versionOrdinal = uint.max;
    /// Whether the sole primary key attribute has a generated value.
    bool generatesId;
    /// Jakarta generation strategy for generated identifiers.
    GenerationType generationStrategy = GenerationType.AUTO;
    /// Name of the generator when the mapping specifies one.
    string generator;
}

/// Checks the provider's exact entity contract before calling its accessors.
Error validateEntity(scope const ref EntityMapping mapping, scope Object entity) nothrow @nogc
{
    if (entity is null || mapping.isExactType is null || !mapping.isExactType(typeid(entity)))
        return Error(Status.invalidArgument, "entity type does not match its mapping");
    return Error.init;
}

/// Checks the mapping shape before publishing it to the provider.
Error validateMapping(scope const ref EntityMapping mapping) nothrow @nogc
{
    if (mapping.entityName.length == 0 || mapping.typeName.length == 0 || mapping.table.length == 0)
        return Error(Status.invalidArgument, "entity mapping needs an entity name, D type name and table");
    if (mapping.isExactType is null || mapping.construct is null || mapping.attributes.length == 0)
        return Error(Status.invalidArgument, "entity mapping needs a concrete type, constructor and attributes");
    const attributes = validateAttributes(mapping.attributes);
    if (attributes.code != Status.ok)
        return attributes;
    foreach (callback; mapping.postLoad)
        if (callback is null)
            return Error(Status.invalidArgument, "missing PostLoad callback");
    return validateIdentifiers(mapping);
}

private Error validateAttributes(scope const(AttributeMapping)[] attributes) nothrow @nogc
{
    foreach (index, ref attribute; attributes)
    {
        if (attribute.ordinal != index || attribute.name.length == 0 || attribute.column.length == 0
                || attribute.kind < AttributeKind.integer || attribute.kind > AttributeKind.binary
                || attribute.sqlType == Types.NULL || attribute.read is null || attribute.write is null)
            return Error(Status.invalidArgument, "invalid persistent attribute mapping", index);
    }
    return Error.init;
}

private Error validateIdentifiers(scope const ref EntityMapping mapping) nothrow @nogc
{
    if (mapping.idOrdinals.length == 0 || (mapping.generatesId && mapping.idOrdinals.length != 1))
        return Error(Status.invalidArgument, "entity mapping needs an id and generation requires a simple id");
    if (mapping.versionOrdinal != uint.max && mapping.versionOrdinal >= mapping.attributes.length)
        return Error(Status.invalidArgument, "invalid version attribute ordinal");
    foreach (index, ordinal; mapping.idOrdinals)
    {
        if (ordinal >= mapping.attributes.length || ordinal == mapping.versionOrdinal)
            return Error(Status.invalidArgument, "invalid id attribute ordinal", index);
        foreach (previous; mapping.idOrdinals[0 .. index])
            if (ordinal == previous)
                return Error(Status.invalidArgument, "duplicate id attribute ordinal", index);
    }
    return Error.init;
}
