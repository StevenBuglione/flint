/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/spi/LoadState.java
 * Copyright (c) 2008, 2020 Oracle and/or its affiliates. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: D enum declaration.
 */

/// Jakarta Persistence provider SPI.
module flint.jakarta.persistence.spi;

@safe:

/// Reports whether a persistence provider can determine that state is loaded.
enum LoadState
{
    /// The state is loaded.
    LOADED,

    /// The state has yet to be loaded.
    NOT_LOADED,

    /// The provider cannot determine the load state.
    UNKNOWN,
}
