/// Public Jakarta Persistence API. Import contract and annotation names from this module.
module flint.jakarta.persistence;

public import flint.jakarta.persistence.annotations : Access, AccessType, AssociationOverride,
    AssociationOverrides, AttributeOverride,
    AttributeOverrides, Basic, Cacheable, CheckConstraint, CollectionTable, Column, ConstraintMode,
    DiscriminatorColumn, DiscriminatorType,
    DiscriminatorValue, Embeddable, Embedded, EmbeddedId, Entity, EnumType, Enumerated,
    EnumeratedValue, ExcludeDefaultListeners,
    ExcludeSuperclassListeners, FetchType, ForeignKey, GeneratedValue, GenerationType, Id, Index,
    Inheritance, InheritanceType,
    JoinColumn, JoinColumns, JoinTable, Lob, MapKey, MapKeyColumn, MapKeyEnumerated,
    MapKeyJoinColumn, MapKeyJoinColumns,
    MapKeyTemporal, MappedSuperclass, MapsId, OrderBy, OrderColumn, PostLoad, PostPersist,
    PostRemove, PostUpdate, PrePersist,
    PreRemove, PreUpdate, PrimaryKeyJoinColumn, PrimaryKeyJoinColumns, QueryHint, SecondaryTable,
    SecondaryTables, SequenceGenerator,
    SequenceGenerators, Table, TableGenerator,
    TableGenerators, Temporal, TemporalType, Transient, UniqueConstraint, Version;
public import flint.jakarta.persistence.contracts : AttributeConverter, EntityTransaction;

@safe:
