# JPA association metadata proposal

This is a startup contract proposal under [ADR-034](../../adr/ADR-034-jpa-engine.md). It uses the pinned Hibernate ORM 7.1.0 sources at `02eb1ac3e09b28a954b530c607357b6495ce5957`. The classic PetClinic source revision still needs confirmation. The fixtures below establish behavior for the initial direct foreign-key registration proof.

## Direct foreign keys

| Declaration | Foreign key | Referenced key |
| --- | --- | --- |
| Owning `ManyToOne` | Column on the owner table | Target primary key |
| To-many with `mappedBy` | Column from the target's resolved owning `ManyToOne` | Owner primary key |
| To-many with an explicit `JoinColumn` | Declared column on the target table | Owner primary key |

Emit the ordered entity table and plain static association declarations as one immutable persistence-unit input. Each declaration carries owner and target mapping ordinals into that table, column names, and a zero-based association ordinal within the concrete owner. Verify the ordered entity table identity before resolving any ordinal. Bind to exact registered descriptors after entity registration and before publishing the full provider registry. Spring composition performs this after the AOT application registry finishes loading. Declare inherited associations first. Association ordinals occupy their own table. Scalar attribute ordinals stay stable.

AOT resolves names and physical columns using the configured naming rules. For `OneToMany(mappedBy = …)`, it resolves the target property to an owning `ManyToOne` ordinal. A mapped-by declaration cannot also define a join column or join table. Registration requires that the owning edge points back to the exact original owner mapping and references its primary key. The checked edge reuses that foreign-key column. A directly declared target-side join may refer to a physical column with no corresponding scalar attribute on the target.

Registration runs before publication. It checks exact membership of both mapping descriptors in the same persistence unit, unique association names and dense ordinals per owner, orientation of the owning edge, and referenced key compatibility. The first proof uses one signed integer identifier per mapping and covers joins to that identifier. Resolve ordinals and physical columns once, so the fetch path uses an already checked plan.

## Row and transaction boundary

For a to-one, the row plan must capture the foreign key and its SQL NULL state before the cursor advances. Zero and negative IDs are valid. SQL NULL on an optional edge represents an absent association. A present key requires target resolution. The source of the scalar foreign-key value and the moment it is attached to the entity still need review. The existing scalar attribute writer contract and loaded snapshots stay in place for this proof.

A to-many binds the owner's canonical ID to the target-side foreign key. Materialize matching targets through the existing identity index to reuse managed instances. The eventual checked SQL plan carries explicit JDBC result positions and a typed parameter slot. Ordering expressions, joins through a third table, cascade work, and proxy generation require separate slices. The confirmed classic revision will determine which of those slices the application needs.

A lazy façade retains its original attachment handle. It returns an initialized payload before looking up a context. An unloaded access resolves the owner and starts one attempt before acquiring a connection. With Spring transactions, the provider uses the transaction-bound holder through `DataSourceUtils`. A connection acquisition failure settles the attempt so the caller can retry. After acquisition the provider holds the originating lease until I/O is terminal. It stages GC-owned results, then rechecks the attachment in the current context and publishes on success. A detached façade retains initialized null and empty results. A stale unloaded access fails before connection acquisition. Spring suspension and resumption follow the existing holder and context contract. `DataSourceUtils.releaseConnection` consults the current binding. Release must honor the holder that supplied the lease. The cleanup strategy for suspension and reentrant completion needs data-access review before fetch integration.

## Pinned evidence and test scope

| Hibernate case | Evidence for this proposal |
| --- | --- |
| [`MultiLevelCascadeRegularIdBasedParentChildAssociationTest`](https://github.com/hibernate/hibernate-orm/blob/02eb1ac3e09b28a954b530c607357b6495ce5957/hibernate-core/src/test/java/org/hibernate/orm/test/jpa/cascade/multilevel/MultiLevelCascadeRegularIdBasedParentChildAssociationTest.java) | `Parent.children` names the target's owning `Child.parent` property through `mappedBy`. Both identifiers are `Long`. |
| [`PersistOnLazyCollectionTests`](https://github.com/hibernate/hibernate-orm/blob/02eb1ac3e09b28a954b530c607357b6495ce5957/hibernate-core/src/test/java/org/hibernate/orm/test/mapping/cascade/PersistOnLazyCollectionTests.java) | `Order.lineItems` declares its target-side `order_fk` with `JoinColumn`. The tests count the owner query, observe an uninitialized collection after flush, and check detached access. |
| [`City`](https://github.com/hibernate/hibernate-orm/blob/02eb1ac3e09b28a954b530c607357b6495ce5957/hibernate-core/src/test/java/org/hibernate/orm/test/annotations/onetomany/City.java) and [`OneToManyTest`](https://github.com/hibernate/hibernate-orm/blob/02eb1ac3e09b28a954b530c607357b6495ce5957/hibernate-core/src/test/java/org/hibernate/orm/test/annotations/onetomany/OneToManyTest.java) | The same target entity has collections through different foreign keys. `testListWithBagSemanticAndOrderBy` checks declared attribute ordering for one and default key ordering for the other. |
| [`SimpleLazySubSelectFetchTests`](https://github.com/hibernate/hibernate-orm/blob/02eb1ac3e09b28a954b530c607357b6495ce5957/hibernate-core/src/test/java/org/hibernate/orm/test/mapping/fetch/subselect/SimpleLazySubSelectFetchTests.java) | The fixture distinguishes an unloaded collection from a loaded empty collection and checks the number of SQL statements around access. Its Hibernate subselect strategy is specific to that fixture. |

A local DMD and LDC prototype used hand-written descriptors to normalize all three direct foreign-key shapes after resolving registered pointers. It rejected a foreign mapping descriptor with identical names, a missing or misdirected `mappedBy` edge, a join to a non-key column, and duplicate names and ordinals or gapped ordinals. A later linked PostgreSQL proof needs actual association fetches, statement counts, initialized empty results, stale access without JDBC, cancellation with terminal lease cleanup, and the existing DMD and LDC gates.
