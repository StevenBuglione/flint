/*
 * Ported from jakarta-persistence 3.2.0: jakarta/persistence/ (see source files below).
 * SPDX-License-Identifier: BSD-3-Clause
 * Modified by the Flint authors: annotations are D UDAs with Jakarta defaults (R2).
 *
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 *   Access.java, AccessType.java, AssociationOverride.java, AssociationOverrides.java,
 *   AttributeOverride.java, Basic.java, Cacheable.java, CollectionTable.java,
 *   DiscriminatorColumn.java, DiscriminatorType.java, DiscriminatorValue.java, Embeddable.java,
 *   Embedded.java, EmbeddedId.java, Entity.java, EnumType.java, Enumerated.java,
 *   ExcludeDefaultListeners.java, FetchType.java, GeneratedValue.java, GenerationType.java,
 *   Id.java, Inheritance.java, InheritanceType.java, JoinColumn.java, JoinColumns.java,
 *   JoinTable.java, Lob.java, MapKey.java, MapKeyEnumerated.java, MapKeyJoinColumn.java,
 *   MapKeyJoinColumns.java, MapKeyTemporal.java, MappedSuperclass.java, OrderBy.java,
 *   OrderColumn.java, PostLoad.java, PostPersist.java, PostRemove.java, PostUpdate.java,
 *   PrePersist.java, PreRemove.java, PreUpdate.java, PrimaryKeyJoinColumn.java,
 *   PrimaryKeyJoinColumns.java, QueryHint.java, SecondaryTable.java, SecondaryTables.java,
 *   SequenceGenerator.java, Table.java, TableGenerator.java, Temporal.java, TemporalType.java,
 *   Transient.java, UniqueConstraint.java, Version.java
 *
 * Copyright (c) 2017, 2023 Oracle and/or its affiliates. All rights reserved.
 *   SequenceGenerators.java, TableGenerators.java
 *
 * Copyright (c) 2023 Oracle and/or its affiliates. All rights reserved.
 *   CheckConstraint.java, EnumeratedValue.java
 *
 * Copyright (c) 2008, 2024 Oracle and/or its affiliates. All rights reserved.
 *   Column.java, MapKeyColumn.java, MapsId.java
 *
 * Copyright (c) 2011, 2023 Oracle and/or its affiliates. All rights reserved.
 *   ForeignKey.java, Index.java
 *
 * Copyright (c) 2013, 2023 Oracle and/or its affiliates. All rights reserved.
 *   ConstraintMode.java
 *
 * Copyright (c) 2022, 2023 Contributors to the Eclipse Foundation
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 *   AttributeOverrides.java
 *
 * Copyright (c) 2008, 2020 Oracle and/or its affiliates. All rights reserved.
 *   ExcludeSuperclassListeners.java, PersistenceUnits.java
 *
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 *   LockModeType.java, NamedQuery.java, NamedQueries.java
 *
 * Copyright (c) 2008, 2023 Oracle and/or its affiliates. All rights reserved.
 *   CascadeType.java, ElementCollection.java, EntityListeners.java, FlushModeType.java, IdClass.java, ManyToMany.java,
 *   ManyToOne.java,
 *   MapKeyClass.java, OneToMany.java, OneToOne.java, PersistenceContext.java, PersistenceContexts.java,
 *   PersistenceContextType.java, PersistenceProperty.java, PersistenceUnit.java
 *
 * Copyright (c) 2011, 2023 Oracle and/or its affiliates. All rights reserved.
 *   Convert.java, Converter.java, Converts.java, SynchronizationType.java
 */

/// Jakarta Persistence mapping annotations and their option enums.
module flint.jakarta.persistence.annotations;

import flint.java.classref : ClassRef;

@safe:

// Entity identity and access

/// Declares that the annotated class is an entity.
struct Entity
{
    /// The entity name.
    string name = "";
}

/// Identifies the primary key of an entity.
struct Id
{
}

/// Declares the version field or property of an entity class, which is used to detect optimistic lock failures,
/// ensuring the integrity of optimistic transactions.
struct Version
{
}

/// Specifies that the annotated property or field is not persistent.
struct Transient
{
}

/// Used to specify an access type to be applied to an entity class, mapped superclass, or embeddable class, or to a
/// specific attribute of such a class.
struct Access
{
    /// Specification of field- or property-based access.
    AccessType value;
}

/// Used with the Access annotation to specify an access type to be applied to an entity class, mapped superclass,
/// or embeddable class, or to a specific attribute of such a class.
enum AccessType
{
    FIELD,
    PROPERTY,
}

/// The simplest type of mapping of a persistent field or property to a single database column.
struct Basic
{
    /// Whether the value of the field or property should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.EAGER;
    /// Specifies whether the value of the field or property may be null.
    bool optional = true;
}

/// Defines strategies for fetching data from the database.
enum FetchType
{
    LAZY,
    EAGER,
}

// Identifier generation

/// Specifies a generation strategy for generated primary keys.
struct GeneratedValue
{
    /// The primary key generation strategy that the persistence provider must use to generate the annotated entity
    /// primary key.
    GenerationType strategy = GenerationType.AUTO;
    /// The name of the primary key generator to use, as specified by the `SequenceGenerator` or `TableGenerator`
    /// annotation which declares the generator.
    string generator = "";
}

/// Enumerates the defined primary key generation strategies.
enum GenerationType
{
    TABLE,
    SEQUENCE,
    IDENTITY,
    UUID,
    AUTO,
}

/// Defines a primary key generator that may be referenced by name when a generator element is specified for the
/// GeneratedValue annotation.
struct SequenceGenerator
{
    /// A unique generator name that can be referenced by one or more classes to be the generator for primary key
    /// values.
    string name = "";
    /// The name of the database sequence object from which to obtain primary key values.
    string sequenceName = "";
    /// The catalog of the sequence generator.
    string catalog = "";
    /// The schema of the sequence generator.
    string schema = "";
    /// The value from which the sequence object is to start generating.
    int initialValue = 1;
    /// The amount to increment by when allocating sequence numbers from the sequence.
    int allocationSize = 50;
    /// A SQL fragment appended to the generated DDL statement which creates this sequence.
    string options = "";
}

/// Used to group SequenceGenerator annotations.
struct SequenceGenerators
{
    /// The repeated `SequenceGenerator` mappings.
    SequenceGenerator[] value;
}

/// Defines a primary key generator that may be referenced by name when a generator element is specified for the
/// GeneratedValue annotation.
struct TableGenerator
{
    /// (optional) A unique generator name that can be referenced by one or more classes to be the generator for id
    /// values.
    string name = "";
    /// Name of the table that stores the generated id values.
    string table = "";
    /// The catalog of the table.
    string catalog = "";
    /// The schema of the table.
    string schema = "";
    /// Name of the primary key column in the table.
    string pkColumnName = "";
    /// Name of the column that stores the last value generated.
    string valueColumnName = "";
    /// The primary key value in the generator table that distinguishes this set of generated values from others
    /// that may be stored in the table.
    string pkColumnValue = "";
    /// The initial value to be used to initialize the column that stores the last value generated.
    int initialValue = 0;
    /// The amount to increment by when allocating id numbers from the generator.
    int allocationSize = 50;
    /// Unique constraints that are to be placed on the table.
    UniqueConstraint[] uniqueConstraints = [];
    /// Indexes for the table.
    Index[] indexes = [];
    /// A SQL fragment appended to the generated DDL statement which creates this table.
    string options = "";
}

/// Used to group TableGenerator annotations.
struct TableGenerators
{
    /// The repeated `TableGenerator` mappings.
    TableGenerator[] value;
}

// Value mappings

/// Declares a class which is not itself an entity, but whose mappings are inherited by the entities which extend
/// it.
struct MappedSuperclass
{
}

/// Declares a type whose instances are stored as an intrinsic part of an owning entity, sharing the identity of the
/// entity.
struct Embeddable
{
}

/// Declares a persistent field or property of an entity whose value is an instance of an embeddable class.
struct Embedded
{
}

/// Specifies that the annotated persistent field or property of an entity class or mapped superclass is the
/// composite primary key of the entity.
struct EmbeddedId
{
}

/// Specifies that a persistent property or field should be persisted as an enumerated type.
struct Enumerated
{
    /// The type used in mapping an enum type.
    EnumType value = EnumType.ORDINAL;
}

/// Specifies that an annotated field of a Java enum type is the source of database column values for an Enumerated
/// enumerated mapping.
struct EnumeratedValue
{
}

/// Enumerates available options for mapping enumerated types.
enum EnumType
{
    ORDINAL,
    STRING,
}

/// Specifies that the annotated persistent property or field should be persisted as a large object to a database-
/// native large object (LOB) type.
struct Lob
{
}

/// This annotation must be specified for persistent fields or properties of type java.util.Date and
/// java.util.Calendar.
struct Temporal
{
    /// The type used in mapping `java.util.Date` or `java.util.Calendar`.
    TemporalType value;
}

/// Type used to indicate a specific mapping of java.util.Date or java.util.Calendar.
enum TemporalType
{
    DATE,
    TIME,
    TIMESTAMP,
}

// Table and column mappings

/// Specifies the primary table mapped by the annotated entity type.
struct Table
{
    /// The name of the table.
    string name = "";
    /// The catalog of the table.
    string catalog = "";
    /// The schema of the table.
    string schema = "";
    /// Unique constraints to be placed on the table.
    UniqueConstraint[] uniqueConstraints = [];
    /// Indexes for the table.
    Index[] indexes = [];
    /// Check constraints to be applied to the table.
    CheckConstraint[] check = [];
    /// A comment to be applied to the table.
    string comment = "";
    /// A SQL fragment appended to the generated DDL statement which creates this table.
    string options = "";
}

/// Specifies the column mapped by the annotated persistent property or field.
struct Column
{
    /// The name of the column.
    string name = "";
    /// Whether the column is a unique key.
    bool unique = false;
    /// Whether the database column is nullable.
    bool nullable = true;
    /// Whether the column is included in SQL INSERT statements generated by the persistence provider.
    bool insertable = true;
    /// Whether the column is included in SQL UPDATE statements generated by the persistence provider.
    bool updatable = true;
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// The name of the table that contains the column.
    string table = "";
    /// The column length.
    int length = 255;
    /// The precision for a column of SQL type `decimal` or `numeric`, or of similar database-native type.
    int precision = 0;
    /// The scale for a column of SQL type `decimal` or `numeric`, or of similar database-native type.
    int scale = 0;
    /// The number of decimal digits to use for storing fractional seconds in a SQL `time` or `timestamp` column.
    int secondPrecision = -1;
    /// Check constraints to be applied to the column.
    CheckConstraint[] check = [];
    /// A comment to be applied to the column.
    string comment = "";
}

/// Used to specify a SQL check constraint on a column or table when schema generation is in effect.
struct CheckConstraint
{
    /// The name of the constraint.
    string name = "";
    /// The native SQL expression to be checked.
    string constraint;
    /// A SQL fragment appended to the generated DDL which creates this constraint.
    string options = "";
}

/// Used in schema generation to specify creation of an index.
struct Index
{
    /// The name of the index.
    string name = "";
    /// The columns included in the index, in order, following the BNF rule `column_list` given above.
    string columnList;
    /// Whether the index is unique.
    bool unique = false;
    /// A SQL fragment appended to the generated DDL which creates this index.
    string options = "";
}

/// Specifies that a unique constraint is to be included in the generated DDL for a primary or secondary table.
struct UniqueConstraint
{
    /// The name of the constraint.
    string name = "";
    /// The names of the column which make up the constraint.
    string[] columnNames;
    /// A SQL fragment appended to the generated DDL which creates this constraint.
    string options = "";
}

/// Specifies a secondary table for the annotated entity class.
struct SecondaryTable
{
    /// The name of the table.
    string name;
    /// The catalog of the table.
    string catalog = "";
    /// The schema of the table.
    string schema = "";
    /// The columns that are used to join with the primary table.
    PrimaryKeyJoinColumn[] pkJoinColumns = [];
    /// Used to specify or control the generation of a foreign key constraint for the columns corresponding to the
    /// `#pkJoinColumns` element when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// Unique constraints that are to be placed on the table.
    UniqueConstraint[] uniqueConstraints = [];
    /// Indexes for the table.
    Index[] indexes = [];
    /// Check constraints to be applied to the table.
    CheckConstraint[] check = [];
    /// A comment to be applied to the table.
    string comment = "";
    /// A SQL fragment appended to the generated DDL statement which creates this table.
    string options = "";
}

/// Specifies multiple secondary tables for an entity.
struct SecondaryTables
{
    /// The secondary tables for an entity.
    SecondaryTable[] value;
}

// Joins and overrides

/// Specifies the handling of foreign key constraints when schema generation is in effect.
struct ForeignKey
{
    /// Used to specify whether a foreign key constraint should be generated when schema generation is in effect.
    ConstraintMode value = ConstraintMode.CONSTRAINT;
    /// The name of the foreign key constraint.
    string name = "";
    /// The foreign key constraint definition.
    string foreignKeyDefinition = "";
    /// A SQL fragment appended to the generated DDL which creates this foreign key.
    string options = "";
}

/// Used to control the application of a constraint.
enum ConstraintMode
{
    CONSTRAINT,
    NO_CONSTRAINT,
    PROVIDER_DEFAULT,
}

/// Specifies a column for joining an entity association or element collection.
struct JoinColumn
{
    /// The name of the foreign key column.
    string name = "";
    /// The name of the column referenced by this foreign key column.
    string referencedColumnName = "";
    /// Whether the property is a unique key.
    bool unique = false;
    /// Whether the foreign key column is nullable.
    bool nullable = true;
    /// Whether the column is included in SQL INSERT statements generated by the persistence provider.
    bool insertable = true;
    /// Whether the column is included in SQL UPDATE statements generated by the persistence provider.
    bool updatable = true;
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// The name of the table that contains the column.
    string table = "";
    /// Used to specify or control the generation of a foreign key constraint when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// Check constraints to be applied to the column.
    CheckConstraint[] check = [];
    /// A comment to be applied to the column.
    string comment = "";
}

/// Specifies the mapping for composite foreign keys.
struct JoinColumns
{
    /// The join columns that map the relationship.
    JoinColumn[] value;
    /// Used to specify or control the generation of a foreign key constraint when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
}

/// Specifies the mapping of an association to an intermediate join table.
struct JoinTable
{
    /// The name of the join table.
    string name = "";
    /// The catalog of the table.
    string catalog = "";
    /// The schema of the table.
    string schema = "";
    /// The foreign key columns of the join table which reference the primary table of the entity owning the
    /// association.
    JoinColumn[] joinColumns = [];
    /// The foreign key columns of the join table which reference the primary table of the entity that does not own
    /// the association.
    JoinColumn[] inverseJoinColumns = [];
    /// Used to specify or control the generation of a foreign key constraint for the columns corresponding to the
    /// `#joinColumns` element when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// Used to specify or control the generation of a foreign key constraint for the columns corresponding to the
    /// `#inverseJoinColumns` element when table generation is in effect.
    ForeignKey inverseForeignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// Unique constraints to be placed on the table.
    UniqueConstraint[] uniqueConstraints = [];
    /// Indexes for the table.
    Index[] indexes = [];
    /// Check constraints to be applied to the table.
    CheckConstraint[] check = [];
    /// A comment to be applied to the table.
    string comment = "";
    /// A SQL fragment appended to the generated DDL statement which creates this table.
    string options = "";
}

/// Specifies the table that is used for the mapping of collections of basic or embeddable types.
struct CollectionTable
{
    /// The name of the collection table.
    string name = "";
    /// The catalog of the table.
    string catalog = "";
    /// The schema of the table.
    string schema = "";
    /// The foreign key columns of the collection table which reference the primary table of the entity.
    JoinColumn[] joinColumns = [];
    /// Used to specify or control the generation of a foreign key constraint for the columns corresponding to the
    /// `#joinColumns` element when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// Unique constraints that are to be placed on the table.
    UniqueConstraint[] uniqueConstraints = [];
    /// Indexes for the table.
    Index[] indexes = [];
    /// A SQL fragment appended to the generated DDL statement which creates this table.
    string options = "";
}

/// Specifies a primary key column that is used as a foreign key to join to another table.
struct PrimaryKeyJoinColumn
{
    /// The name of the primary key column of the current table.
    string name = "";
    /// The name of the primary key column of the table being joined to.
    string referencedColumnName = "";
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// Used to specify or control the generation of a foreign key constraint for the primary key join column when
    /// table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
}

/// Groups PrimaryKeyJoinColumn annotations.
struct PrimaryKeyJoinColumns
{
    /// One or more `PrimaryKeyJoinColumn` annotations.
    PrimaryKeyJoinColumn[] value;
    /// Used to specify or control the generation of a foreign key constraint when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
}

/// Used to override the mapping of a Basic (whether explicit or default) property or field or Id property or field.
struct AttributeOverride
{
    /// The name of the property whose mapping is being overridden if property-based access is being used, or the
    /// name of the field if field-based access is used.
    string name;
    /// The column that is being mapped to the persistent attribute.
    Column column;
}

/// Used to override mappings of multiple properties or fields.
struct AttributeOverrides
{
    /// One or more field or property mapping overrides.
    AttributeOverride[] value;
}

/// Used to override a mapping for an entity relationship.
struct AssociationOverride
{
    /// The name of the relationship property whose mapping is being overridden if property-based access is being
    /// used, or the name of the relationship field if field-based access is used.
    string name;
    /// The join column(s) being mapped to the persistent attribute(s).
    JoinColumn[] joinColumns = [];
    /// Used to specify or control the generation of a foreign key constraint for the columns corresponding to the
    /// `joinColumns` element when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
    /// The join table that maps the relationship.
    JoinTable joinTable = JoinTable.init;
}

/// Used to override mappings of multiple relationship properties or fields.
struct AssociationOverrides
{
    /// The association override mappings that are to be applied to the relationship field or property.
    AssociationOverride[] value;
}

// Inheritance and ordering

/// Specifies the inheritance mapping strategy for the entity class hierarchy which descends from the annotated
/// entity class.
struct Inheritance
{
    /// The inheritance mapping strategy for the entity inheritance hierarchy.
    InheritanceType strategy = InheritanceType.SINGLE_TABLE;
}

/// Enumerated the options for mapping entity inheritance.
enum InheritanceType
{
    SINGLE_TABLE,
    TABLE_PER_CLASS,
    JOINED,
}

/// Specifies the discriminator column for the InheritanceType#SINGLE_TABLE SINGLE_TABLE and InheritanceType#JOINED
/// JOINED Inheritance inheritance mapping strategies.
struct DiscriminatorColumn
{
    /// The name of column to be used for the discriminator.
    string name = "DTYPE";
    /// The type of object/column to use as a class discriminator.
    DiscriminatorType discriminatorType = DiscriminatorType.STRING;
    /// The SQL fragment that is used when generating the DDL for the discriminator column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// The column length for String-based discriminator types.
    int length = 31;
}

/// Defines supported types of the discriminator column.
enum DiscriminatorType
{
    STRING,
    CHAR,
    INTEGER,
}

/// Specifies the value of the discriminator column for the annotated entity type.
struct DiscriminatorValue
{
    /// The value that indicates that the row is an entity of the annotated entity type.
    string value;
}

/// Specifies the ordering of the elements of a collection-valued association or element collection at the point
/// when the association or collection is retrieved.
struct OrderBy
{
    /// An `orderby_list`.
    string value = "";
}

/// Specifies a column that is used to maintain the persistent order of a list.
struct OrderColumn
{
    /// The name of the ordering column.
    string name = "";
    /// Whether the database column is nullable.
    bool nullable = true;
    /// Whether the column is included in SQL INSERT statements generated by the persistence provider.
    bool insertable = true;
    /// Whether the column is included in SQL UPDATE statements generated by the persistence provider.
    bool updatable = true;
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
}

/// Designates a ManyToOne or OneToOne relationship attribute that provides the mapping for an EmbeddedId primary
/// key, an attribute within an EmbeddedId primary key, or a simple primary key of the parent entity.
struct MapsId
{
    /// The name of the attribute within the composite key to which the relationship attribute corresponds.
    string value = "";
}

/// Specifies the map key for associations of type java.util.Map when the map key is itself the primary key or a
/// persistent field or property of the entity that is the value of the map.
struct MapKey
{
    /// The name of the persistent field or property of the associated entity that is used as the map key.
    string name = "";
}

/// Specifies the mapping for the key column of a map whose map key is a basic type.
struct MapKeyColumn
{
    /// The name of the map key column.
    string name = "";
    /// Whether the column is a unique key.
    bool unique = false;
    /// Whether the database column is nullable.
    bool nullable = false;
    /// Whether the column is included in SQL INSERT statements generated by the persistence provider.
    bool insertable = true;
    /// Whether the column is included in SQL UPDATE statements generated by the persistence provider.
    bool updatable = true;
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// The name of the table that contains the column.
    string table = "";
    /// The column length.
    int length = 255;
    /// The precision for a column of SQL type `decimal` or `numeric`, or of similar database-native type.
    int precision = 0;
    /// The scale for a column of SQL type `decimal` or `numeric`, or of similar database-native type.
    int scale = 0;
}

/// Specifies the enum type for a map key whose basic type is an enumerated type.
struct MapKeyEnumerated
{
    /// The type used in mapping a map key enum type.
    EnumType value = EnumType.ORDINAL;
}

/// This annotation must be specified for persistent map keys of type java.util.Date and java.util.Calendar.
struct MapKeyTemporal
{
    /// The type used in mapping `java.util.Date` or `java.util.Calendar`.
    TemporalType value;
}

/// Specifies a mapping to an entity that is a map key.
struct MapKeyJoinColumn
{
    /// The name of the foreign key column for the map key.
    string name = "";
    /// The name of the column referenced by this foreign key column.
    string referencedColumnName = "";
    /// Whether the property is a unique key.
    bool unique = false;
    /// Whether the foreign key column is nullable.
    bool nullable = false;
    /// Whether the column is included in SQL INSERT statements generated by the persistence provider.
    bool insertable = true;
    /// Whether the column is included in SQL UPDATE statements generated by the persistence provider.
    bool updatable = true;
    /// The SQL fragment that is used when generating the DDL for the column.
    string columnDefinition = "";
    /// A SQL fragment appended to the generated DDL which declares this column.
    string options = "";
    /// The name of the table that contains the foreign key column.
    string table = "";
    /// Used to specify or control the generation of a foreign key constraint when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
}

/// Supports composite map keys that reference entities.
struct MapKeyJoinColumns
{
    /// The map key join columns that are used to map to the entity that is the map key.
    MapKeyJoinColumn[] value;
    /// Used to specify or control the generation of a foreign key constraint when table generation is in effect.
    ForeignKey foreignKey = ForeignKey(ConstraintMode.PROVIDER_DEFAULT);
}

// Lifecycle

/// Specifies the callback listener classes for an entity or mapped superclass.
struct EntityListeners
{
    /// Listener classes in callback invocation order.
    ClassRef[] value;
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PrePersist
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PostPersist
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PreRemove
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PostRemove
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PreUpdate
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PostUpdate
{
}

/// Specifies a callback method for the corresponding lifecycle event.
struct PostLoad
{
}

/// Specifies that the invocation of default listeners is to be excluded for the entity class (or mapped superclass)
/// and its subclasses.
struct ExcludeDefaultListeners
{
}

/// Specifies that the invocation of superclass listeners is to be excluded for the entity class (or mapped
/// superclass) and its subclasses.
struct ExcludeSuperclassListeners
{
}

// Query hints and cache

/// Used to supply a query property or hint to the NamedQuery or NamedNativeQuery annotation.
struct QueryHint
{
    /// Value of the hint.
    string value;
    /// Name of the hint.
    string name;
}

/// Specifies whether an entity should be cached, if caching is enabled, and when the value of the persistence.xml
/// caching element is SharedCacheMode#ENABLE_SELECTIVE or SharedCacheMode#DISABLE_SELECTIVE.
struct Cacheable
{
    /// Whether or not the entity should be cached.
    bool value = true;
}

// Association targets and cascades

/// Defines the set of cascadable operations that are propagated to the associated entity.
enum CascadeType
{
    ALL,
    PERSIST,
    MERGE,
    REMOVE,
    REFRESH,
    DETACH,
}

/// Specifies a single-valued association to another entity class that has many-to-one multiplicity.
struct ManyToOne
{
    /// The entity class targeted by the association. An empty ClassRef asks the provider to infer it.
    ClassRef targetEntity = ClassRef.init;
    /// The operations that must be cascaded to the target of the association.
    CascadeType[] cascade = [];
    /// Whether the association should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.EAGER;
    /// Whether the association is optional.
    bool optional = true;
}

/// Specifies a many-valued association with one-to-many multiplicity.
struct OneToMany
{
    /// The entity class targeted by the association. An empty ClassRef asks the provider to infer it.
    ClassRef targetEntity = ClassRef.init;
    /// The operations that must be cascaded to the target of the association.
    CascadeType[] cascade = [];
    /// Whether the association should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.LAZY;
    /// The field that owns the relationship.
    string mappedBy = "";
    /// Whether to apply the remove operation to entities that have been removed from the relationship and to
    /// cascade the remove operation to those entities.
    bool orphanRemoval = false;
}

/// Specifies a single-valued association to another entity class that has one-to-one multiplicity.
struct OneToOne
{
    /// The entity class targeted by the association. An empty ClassRef asks the provider to infer it.
    ClassRef targetEntity = ClassRef.init;
    /// The operations that must be cascaded to the target of the association.
    CascadeType[] cascade = [];
    /// Whether the association should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.EAGER;
    /// Whether the association is optional.
    bool optional = true;
    /// The field that owns the relationship.
    string mappedBy = "";
    /// Whether to apply the remove operation to entities that have been removed from the relationship and to
    /// cascade the remove operation to those entities.
    bool orphanRemoval = false;
}

/// Specifies a many-valued association with many-to-many multiplicity, mapping to an intermediate table called the
/// join table.
struct ManyToMany
{
    /// The entity class targeted by the association. An empty ClassRef asks the provider to infer it.
    ClassRef targetEntity = ClassRef.init;
    /// The operations that must be cascaded to the target of the association.
    CascadeType[] cascade = [];
    /// Whether the association should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.LAZY;
    /// The field that owns the relationship.
    string mappedBy = "";
}

/// Declares a collection of instances of a Basic basic type or Embeddable embeddable class.
struct ElementCollection
{
    /// The basic or embeddable class that is the element type of the collection.
    ClassRef targetClass = ClassRef.init;
    /// Whether the collection should be lazily loaded or must be eagerly fetched.
    FetchType fetch = FetchType.LAZY;
}

/// Specifies the type of the map key for associations of type java.util.Map.
struct MapKeyClass
{
    /// The type of the map key.
    ClassRef value;
}

// Type tokens and converters

/// Specifies a composite primary key type whose fields or properties map to the Id identifier fields or properties
/// of the annotated entity class.
struct IdClass
{
    /// The primary key class, which must declare fields or properties with names and types that match the `Id`
    /// fields and properties of the annotated entity class.
    ClassRef value;
}

/// Declares an AttributeConverter and controls whether it is applied automatically.
struct Converter
{
    /// Automatically applies the converter to eligible attributes of the target type.
    bool autoApply = false;
}

/// Selects, overrides or disables conversion of an attribute value.
struct Convert
{
    /// Explicit converter type. An unset value lets the provider select an applicable converter.
    ClassRef converter = ClassRef.init;
    /// Attribute name or dotted path, relative to the annotated type or attribute.
    string attributeName = "";
    /// Disables automatic or inherited conversion.
    bool disableConversion = false;
}

/// Groups conversion overrides on the same declaration.
struct Converts
{
    /// The conversion overrides.
    Convert[] value;
}

/// Declares a dependency on a container-managed entity manager and its persistence context.
struct PersistenceContext
{
    /// Name of the reference in the environment naming context.
    string name = "";
    /// Name of the persistence unit to use.
    string unitName = "";
    /// Lifetime of the context.
    PersistenceContextType type = PersistenceContextType.TRANSACTION;
    /// How the context joins the current transaction.
    SynchronizationType synchronization = SynchronizationType.SYNCHRONIZED;
    /// Properties for the container or provider.
    PersistenceProperty[] properties = [];
}

/// Groups multiple persistence context dependencies on one declaration.
struct PersistenceContexts
{
    /// The declared dependencies.
    PersistenceContext[] value;
}

/// A property passed to the container or persistence provider.
struct PersistenceProperty
{
    /// Value of the property.
    string value;
    /// Name of the property.
    string name;
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

/// Declares a dependency on an entity manager factory for a persistence unit.
struct PersistenceUnit
{
    /// Name of the reference in the environment naming context.
    string name = "";
    /// Name of the persistence unit to use.
    string unitName = "";
}

/// Groups multiple persistence unit dependencies on one declaration.
struct PersistenceUnits
{
    /// The declared dependencies.
    PersistenceUnit[] value;
}

// Query options and JPQL declarations

/// Controls when the persistence provider flushes pending updates.
enum FlushModeType
{
    /// Flush at transaction commit. The provider may also flush earlier.
    COMMIT,

    /// Default mode. Queries in a joined transaction must see pending updates that affect their results.
    AUTO,
}

/// Lock mode for a persistence operation. D-JPA-2 adapts this enum at the EntityManager option boundary.
enum LockModeType
{
    READ,
    WRITE,
    OPTIMISTIC,
    OPTIMISTIC_FORCE_INCREMENT,
    PESSIMISTIC_READ,
    PESSIMISTIC_WRITE,
    PESSIMISTIC_FORCE_INCREMENT,
    NONE,
}

/// Declares a JPQL query scoped to the persistence unit.
struct NamedQuery
{
    /// Name supplied to EntityManager.createNamedQuery.
    string name;
    /// JPQL source supplied to Flint AOT.
    string query;
    /// Optional declared result type. The requested type can override it.
    ClassRef resultClass = ClassRef.init;
    /// Lock mode. A mode other than NONE requires a transaction joined to the persistence context.
    LockModeType lockMode = LockModeType.NONE;
    /// Provider query hints.
    QueryHint[] hints = [];
}

/// Groups named JPQL queries on an entity or mapped superclass.
struct NamedQueries
{
    /// The query declarations.
    NamedQuery[] value;
}
