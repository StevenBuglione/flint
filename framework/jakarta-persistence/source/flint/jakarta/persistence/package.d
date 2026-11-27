/// Public Jakarta Persistence API. Import contract and annotation names from this module.
module flint.jakarta.persistence;

public import flint.jakarta.persistence.annotations : Access, AccessType, AssociationOverride,
    AssociationOverrides, AttributeOverride,
    AttributeOverrides, Basic, Cacheable, CascadeType, CheckConstraint, CollectionTable, Column,
    ColumnResult, ConstraintMode, ConstructorResult,
    Convert, Converter, Converts, DiscriminatorColumn, DiscriminatorType, DiscriminatorValue,
    ElementCollection, Embeddable, Embedded,
    EmbeddedId, Entity, EntityListeners,
    EntityResult, EnumType, Enumerated, EnumeratedValue, ExcludeDefaultListeners,
    ExcludeSuperclassListeners, FetchType, FieldResult,
    FlushModeType, ForeignKey, GeneratedValue, GenerationType, Id, IdClass, Index, Inheritance,
    InheritanceType, JoinColumn, JoinColumns, JoinTable, Lob, LockModeType, ManyToMany, ManyToOne,
    MapKey, MapKeyClass, MapKeyColumn,
    MapKeyEnumerated, MapKeyJoinColumn, MapKeyJoinColumns, MappedSuperclass, MapsId,
    NamedAttributeNode, NamedEntityGraph, NamedEntityGraphs, NamedNativeQueries,
    NamedNativeQuery, NamedQueries, NamedQuery,
    NamedStoredProcedureQueries, NamedStoredProcedureQuery, NamedSubgraph, OneToMany, OneToOne,
    OrderBy, OrderColumn, ParameterMode, PersistenceContext,
    PersistenceContexts, PersistenceContextType,
    PersistenceProperty, PersistenceUnit, PersistenceUnits, PostLoad, PostPersist, PostRemove,
    PostUpdate, PrePersist, PreRemove, PreUpdate,
    PrimaryKeyJoinColumn, PrimaryKeyJoinColumns,
    QueryHint, SecondaryTable, SecondaryTables, SequenceGenerator, SequenceGenerators,
    SqlResultSetMapping, SqlResultSetMappings, StoredProcedureParameter,
    SynchronizationType, Table, TableGenerator, TableGenerators, TemporalType, Transient, UniqueConstraint, Version;
public import flint.jakarta.persistence.contracts : AttributeConverter, CacheRetrieveMode,
    CacheStoreMode, EntityTransaction, FindOption, LockOption,
    Parameter, PersistenceUnitTransactionType,
    PessimisticLockScope, RefreshOption, SharedCacheMode, TupleElement, ValidationMode;

@safe:

// The deprecated attribute keeps the re-export itself quiet; importers of these names still see the deprecation.
deprecated("since 3.2: newly-written code should use the date/time types defined in java.time")
{
    public import flint.jakarta.persistence.annotations : MapKeyTemporal, Temporal;
}
