/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/metamodel/Attribute.java, ManagedType.java,
 * EmbeddableType.java, SingularAttribute.java, PluralAttribute.java, CollectionAttribute.java,
 * ListAttribute.java, SetAttribute.java, and MapAttribute.java.
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 * Contributor: Linda DeMichiel (2.0 and 2.1).
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: class tokens (R4), typed collection interfaces (R10),
 * shared nested enums (R13), and the metamodel runtime sibling (R22).
 */

/// Runtime Jakarta Persistence metamodel attribute contracts.
module flint.jakarta.persistence.metamodel_runtime;

import flint.jakarta.persistence.metamodel : Bindable, Type;
import flint.java.classref : ClassRef;

@safe:

private enum PersistentAttributeKind
{
    /// Many-to-one association.
    MANY_TO_ONE,
    /// One-to-one association.
    ONE_TO_ONE,
    /// Basic attribute.
    BASIC,
    /// Embeddable class attribute.
    EMBEDDED,
    /// Many-to-many association.
    MANY_TO_MANY,
    /// One-to-many association.
    ONE_TO_MANY,
    /// Element collection.
    ELEMENT_COLLECTION,
}

private enum CollectionKind
{
    /// Collection-valued attribute.
    COLLECTION,
    /// Set-valued attribute.
    SET,
    /// List-valued attribute.
    LIST,
    /// Map-valued attribute.
    MAP,
}

/// Describes an entity, mapped superclass, or embeddable class.
interface ManagedType(X) : Type!X
{
}

/// Describes an embeddable class.
interface EmbeddableType(X) : ManagedType!X
{
}

/// Describes an attribute of type Y declared on a managed type X.
interface Attribute(X, Y)
{
    /// The persistence kind shared by all attribute specializations.
    alias PersistentAttributeType = PersistentAttributeKind;

    /// Returns the name of the attribute.
    string getName();

    /// Returns the persistent attribute kind.
    PersistentAttributeType getPersistentAttributeType();

    /// Returns the managed type that declares this attribute.
    ManagedType!X getDeclaringType();

    /// Returns the class token for the attribute value type.
    ClassRef getJavaType();

    /// Reports whether the attribute represents an association.
    bool isAssociation();

    /// Reports whether the attribute represents a collection.
    bool isCollection();
}

/// Describes a single-valued attribute of type T declared on a managed type X.
interface SingularAttribute(X, T) : Attribute!(X, T), Bindable!T
{
    /// Reports whether this attribute is an identifier or part of an identifier.
    bool isId();

    /// Reports whether the attribute is an optimistic locking version.
    bool isVersion();

    /// Reports whether the attribute may be null.
    bool isOptional();

    /// Returns the type of the attribute value.
    Type!T getType();
}

/// Describes a collection C with elements of type E declared on a managed type X.
interface PluralAttribute(X, C, E) : Attribute!(X, C), Bindable!E
{
    /// The collection kind shared by all plural attribute specializations.
    alias CollectionType = CollectionKind;

    /// Returns the kind of collection represented by this attribute.
    CollectionType getCollectionType();

    /// Returns the metamodel type of the elements, or values for a map.
    Type!E getElementType();
}

/// Describes a collection-valued attribute.
template CollectionAttribute(X, E)
{
    import flint.java.util : Collection;

    interface CollectionAttribute : PluralAttribute!(X, Collection!E, E)
    {
    }
}

/// Describes a set-valued attribute.
template SetAttribute(X, E)
{
    import flint.java.util : Set;

    interface SetAttribute : PluralAttribute!(X, Set!E, E)
    {
    }
}

/// Describes a list-valued attribute.
template ListAttribute(X, E)
{
    import flint.java.util : List;

    interface ListAttribute : PluralAttribute!(X, List!E, E)
    {
    }
}

/// Describes a map-valued attribute with keys K and values V.
template MapAttribute(X, K, V)
{
    import flint.java.util : Map;

    interface MapAttribute : PluralAttribute!(X, Map!(K, V), V)
    {
        /// Returns the class token of the map's key type.
        ClassRef getKeyJavaType();

        /// Returns the metamodel type of the map's keys.
        Type!K getKeyType();
    }
}
