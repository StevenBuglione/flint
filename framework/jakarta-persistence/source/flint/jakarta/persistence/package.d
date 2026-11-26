/// Public Jakarta Persistence API. Import contract and annotation names from this module.
module flint.jakarta.persistence;

public import flint.jakarta.persistence.annotations : Access, AccessType, AssociationOverride,
    AssociationOverrides, AttributeOverride,
    AttributeOverrides, Basic, Cacheable, CascadeType, CheckConstraint, CollectionTable, Column,
    ConstraintMode, Converter,
    DiscriminatorColumn,
    DiscriminatorType, DiscriminatorValue, ElementCollection, Embeddable, Embedded, EmbeddedId,
    Entity, EnumType, Enumerated, EnumeratedValue,
    ExcludeDefaultListeners, ExcludeSuperclassListeners,
    FetchType, FlushModeType, ForeignKey, GeneratedValue, GenerationType, Id, IdClass, Index, Inheritance,
    InheritanceType, JoinColumn, JoinColumns, JoinTable, Lob, LockModeType, ManyToMany, ManyToOne,
    MapKey, MapKeyClass, MapKeyColumn,
    MapKeyEnumerated, MapKeyJoinColumn, MapKeyJoinColumns, MapKeyTemporal, MappedSuperclass,
    MapsId, NamedQueries, NamedQuery,
    OneToMany, OneToOne, OrderBy, OrderColumn, PostLoad, PostPersist, PostRemove, PostUpdate,
    PrePersist, PreRemove, PreUpdate,
    PrimaryKeyJoinColumn, PrimaryKeyJoinColumns, QueryHint, SecondaryTable, SecondaryTables,
    SequenceGenerator, SequenceGenerators,
    Table, TableGenerator, TableGenerators, Temporal, TemporalType, Transient, UniqueConstraint, Version;
public import flint.jakarta.persistence.contracts : AttributeConverter, EntityTransaction;

@safe:
