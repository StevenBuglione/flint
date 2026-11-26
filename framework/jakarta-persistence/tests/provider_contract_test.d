/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.provider_contract_test;

import flint.jakarta.persistence : AttributeConverter, EntityTransaction;
import std.typecons : Nullable;

@safe:

@("attribute converters retain different entity and column types")
unittest
{
    static struct AccountId
    {
        long value;
    }

    static final class AccountIdConverter : AttributeConverter!(AccountId, long)
    {
        override long convertToDatabaseColumn(AccountId id)
        {
            return id.value;
        }

        override AccountId convertToEntityAttribute(long column)
        {
            return AccountId(column);
        }
    }

    AttributeConverter!(AccountId, long) converter = new AccountIdConverter;
    const id = converter.convertToEntityAttribute(91);
    assert(id == AccountId(91));
    assert(converter.convertToDatabaseColumn(id) == 91);
}

@("resource transaction contract distinguishes an unset timeout from zero seconds")
unittest
{
    static final class RecordingTransaction : EntityTransaction
    {
        private Nullable!int timeout;
        private bool active;
        private bool rollbackOnly;

        override void begin()
        {
            active = true;
        }

        override void commit()
        {
            active = false;
        }

        override void rollback()
        {
            active = false;
        }

        override void setRollbackOnly()
        {
            rollbackOnly = true;
        }

        override bool getRollbackOnly()
        {
            return rollbackOnly;
        }

        override bool isActive()
        {
            return active;
        }

        override void setTimeout(Nullable!int seconds)
        {
            timeout = seconds;
        }

        override Nullable!int getTimeout()
        {
            return timeout;
        }
    }

    EntityTransaction tx = new RecordingTransaction;
    assert(tx.getTimeout().isNull);
    tx.setTimeout(Nullable!int(0));
    assert(tx.getTimeout().get == 0);
    tx.begin();
    tx.setRollbackOnly();
    assert(tx.isActive() && tx.getRollbackOnly());
    tx.rollback();
    assert(!tx.isActive());
    tx.setTimeout(Nullable!int.init);
    assert(tx.getTimeout().isNull);
}
