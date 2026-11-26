/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/AttributeConverter.java
 * Copyright (c) 2011, 2023 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/EntityTransaction.java:
 * Copyright (c) 2008, 2024 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/CacheRetrieveMode.java, CacheStoreMode.java, PessimisticLockScope.java:
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/FindOption.java, LockOption.java, RefreshOption.java:
 * Copyright (c) 2023 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/ParameterMode.java, SynchronizationType.java:
 * Copyright (c) 2011, 2023 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/PersistenceContextType.java:
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: D interfaces (R3), nullable integer (R5), DDoc exceptions (R8),
 * and built-in options as enums (D-JPA-2).
 */

/// Internal declarations re-exported from the Jakarta Persistence public modules (D-JPA-1).
module flint.jakarta.persistence.contracts;

import std.typecons : Nullable;

@safe:

/// Converts between a persistent attribute type X and a basic database column type Y.
interface AttributeConverter(X, Y)
{
    /// Converts the value to store in a database column.
    Y convertToDatabaseColumn(X attribute);

    /// Converts the column value to the entity attribute type. The caller supplies the database type Y.
    X convertToEntityAttribute(Y dbData);
}

/// Controls resource-local transactions obtained through an entity manager.
interface EntityTransaction
{
    /// Starts a resource transaction. Throws IllegalStateException if a transaction is already active.
    void begin();

    /// Flushes changes and commits. Throws IllegalStateException if inactive, or RollbackException if commit fails.
    void commit();

    /// Rolls back. Throws IllegalStateException if inactive, or PersistenceException for an unexpected error.
    void rollback();

    /// Marks an active transaction rollback-only. Throws IllegalStateException if inactive.
    void setRollbackOnly();

    /// Returns the rollback-only marker. Throws IllegalStateException if inactive.
    bool getRollbackOnly();

    /// Reports whether a resource transaction is in progress. Throws PersistenceException for an unexpected error.
    bool isActive();

    /// Gives the provider a timeout hint in seconds. An unset value leaves the timeout to the database.
    void setTimeout(Nullable!int timeout);

    /// Returns the timeout hint, with an unset value distinct from zero seconds.
    Nullable!int getTimeout();
}

/// A provider-defined option for an entity lookup.
interface FindOption
{
}

/// A provider-defined option for refreshing an entity.
interface RefreshOption
{
}

/// A provider-defined option for locking an entity.
interface LockOption
{
}

/// Controls reading entities from the second-level cache (D-JPA-2).
enum CacheRetrieveMode
{
    /// Allow cache reads.
    USE,

    /// Read entities from the database.
    BYPASS,
}

/// Controls writing entities to the second-level cache (D-JPA-2).
enum CacheStoreMode
{
    /// Store results and updates in the cache, without replacing entries on a database read.
    USE,

    /// Skip cache writes.
    BYPASS,

    /// Store results and updates in the cache, replacing entries on a database read.
    REFRESH,
}

/// Controls which rows a pessimistic lock covers (D-JPA-2).
enum PessimisticLockScope
{
    /// Lock rows storing the entity's non-collection state, including its foreign keys.
    NORMAL,

    /// Also lock join-table and collection-table rows for relationships and collections owned by the entity.
    EXTENDED,
}

/// Direction of a stored procedure parameter.
enum ParameterMode
{
    /// Input parameter.
    IN,

    /// Input and output parameter.
    INOUT,

    /// Output parameter.
    OUT,

    /// Reference cursor that can return a result set.
    REF_CURSOR,
}

/// Lifetime of a persistence context.
enum PersistenceContextType
{
    /// Default. The context is scoped to a transaction.
    TRANSACTION,

    /// The context can span transactions.
    EXTENDED,
}

/// Controls whether the persistence context joins the current transaction automatically.
enum SynchronizationType
{
    /// Join the current transaction automatically.
    SYNCHRONIZED,

    /// Join the current transaction only after an explicit joinTransaction call.
    UNSYNCHRONIZED,
}
