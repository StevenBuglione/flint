/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/criteria/JoinType.java
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 * jakarta/persistence/criteria/Nulls.java:
 * Copyright (c) 2023 Oracle and/or its affiliates. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: D enums in Jakarta declaration order.
 */

/// Query options shared by the Criteria API and its provider contracts.
module flint.jakarta.persistence.criteria.options;

@safe:

/// Determines which rows a Criteria join includes.
enum JoinType
{
    /// Inner join.
    INNER,

    /// Left outer join.
    LEFT,

    /// Right outer join. Support is optional for providers and databases.
    RIGHT,
}

/// Specifies the precedence of null values in an ordered query result.
enum Nulls
{
    /// Leave null precedence unspecified.
    NONE,

    /// Sort null values before non-null values.
    FIRST,

    /// Sort null values after non-null values.
    LAST,
}
