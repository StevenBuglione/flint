/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/metamodel/Type.java, Bindable.java,
 * BasicType.java, and StaticMetamodel.java.
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: class tokens (R4), shared nested enums (R13), and a metamodel UDA (R2).
 */

/// Jakarta Persistence metamodel API.
module flint.jakarta.persistence.metamodel;

import flint.java.classref : ClassRef;

@safe:

private enum PersistenceTypeValue
{
    /// Entity class.
    ENTITY,

    /// Embeddable class.
    EMBEDDABLE,

    /// Mapped superclass.
    MAPPED_SUPERCLASS,

    /// Basic attribute type.
    BASIC,
}

private enum BindableTypeValue
{
    /// Single-valued attribute type.
    SINGULAR_ATTRIBUTE,

    /// Collection-valued attribute type.
    PLURAL_ATTRIBUTE,

    /// Entity type.
    ENTITY_TYPE,
}

/// Represents a persistent object or attribute of type X.
interface Type(X)
{
    /// Kind of persistent type, shared across all X.
    alias PersistenceType = PersistenceTypeValue;

    /// Returns the kind of persistent type.
    PersistenceType getPersistenceType();

    /// Returns the class token for the represented type.
    ClassRef getJavaType();
}

/// Represents a basic attribute, including an enumerated, large object, or temporal attribute.
interface BasicType(X) : Type!X
{
}

/// Represents an object or attribute that can be bound into a Criteria path.
interface Bindable(T)
{
    /// Kind of bindable type, shared across all T.
    alias BindableType = BindableTypeValue;

    /// Returns the kind of bindable type.
    BindableType getBindableType();

    /// Returns the element type for a plural attribute, or the entity or attribute type otherwise.
    ClassRef getBindableJavaType();
}

/// Marks a static metamodel class for the specified entity, mapped superclass, or embeddable class.
struct StaticMetamodel
{
    /// Class represented by the metamodel.
    ClassRef value;
}
