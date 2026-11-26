/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.operation_options_test;

import flint.jakarta.persistence : CacheRetrieveMode, CacheStoreMode, FindOption, LockOption,
    PessimisticLockScope, RefreshOption;

@safe:

@("one provider option can participate in find, refresh and lock")
unittest
{
    static final class ProviderOption : FindOption, RefreshOption, LockOption
    {
    }

    auto option = new ProviderOption;
    const FindOption find = option;
    const RefreshOption refresh = option;
    const LockOption lock = option;
    assert(cast(const ProviderOption) find is option);
    assert(cast(const ProviderOption) refresh is option);
    assert(cast(const ProviderOption) lock is option);
}

@("cache and pessimistic lock settings preserve the Jakarta enum values")
unittest
{
    assert(CacheRetrieveMode.init == CacheRetrieveMode.USE);
    assert(cast(int) CacheRetrieveMode.BYPASS == 1);
    assert(CacheStoreMode.init == CacheStoreMode.USE);
    assert(cast(int) CacheStoreMode.BYPASS == 1 && cast(int) CacheStoreMode.REFRESH == 2);
    assert(PessimisticLockScope.init == PessimisticLockScope.NORMAL);
    assert(cast(int) PessimisticLockScope.EXTENDED == 1);
}
