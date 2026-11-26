# Jakarta Persistence metamodel lookup proposal

The metamodel attribute interfaces are available in `flint.jakarta.persistence.metamodel_runtime`. This proposal describes the next lookup contracts under [ADR-034](../../adr/ADR-034-jpa-engine.md). The source inventory uses Jakarta Persistence 3.2.0 at `320bface63284bf72f5844dc34f6b8ddad7b39c7`.

## Lookup inventory

| Source type | Deferred elements | Contract to preserve |
| --- | ---: | --- |
| `ManagedType` | 28 | Six set-returning methods. Two general attribute lookups. Ten name-only lookups by attribute kind and ten overloads with type tokens. Keep inherited and declared lookups distinct. |
| `IdentifiableType` | 10 | Interface, four ID and version type-token lookups, the nearest mapped superclass or entity, two presence queries, the ID class attribute set, and wildcard ID type. |
| `Metamodel` | 8 | Interface, one entity-name lookup, three class-token lookups, and the managed, entity, and embeddable type sets. |
| `EntityType` and `MappedSuperclassType` | 3 | Two interfaces and the entity-name accessor. |

Jakarta includes attributes declared on mapped superclasses in inherited lookups. For an `Owner` that extends `BaseEntity`, an inherited ID can still be a `SingularAttribute<BaseEntity, Long>`. A declared lookup on `Owner` must reject that ID. `getSupertype()` returns null when the type has no mapped superclass or entity ancestor. A simple or embedded ID counts as a single ID attribute. `getId` and `getDeclaredId` reject an ID class, while `getIdClassAttributes` requires one.

The inventory comes from the pinned Java interfaces. [ManagedType](https://github.com/jakartaee/persistence/blob/320bface63284bf72f5844dc34f6b8ddad7b39c7/api/src/main/java/jakarta/persistence/metamodel/ManagedType.java), [IdentifiableType](https://github.com/jakartaee/persistence/blob/320bface63284bf72f5844dc34f6b8ddad7b39c7/api/src/main/java/jakarta/persistence/metamodel/IdentifiableType.java), [Metamodel](https://github.com/jakartaee/persistence/blob/320bface63284bf72f5844dc34f6b8ddad7b39c7/api/src/main/java/jakarta/persistence/metamodel/Metamodel.java), [EntityType](https://github.com/jakartaee/persistence/blob/320bface63284bf72f5844dc34f6b8ddad7b39c7/api/src/main/java/jakarta/persistence/metamodel/EntityType.java), [MappedSuperclassType](https://github.com/jakartaee/persistence/blob/320bface63284bf72f5844dc34f6b8ddad7b39c7/api/src/main/java/jakarta/persistence/metamodel/MappedSuperclassType.java).

## Retaining the type information each lookup returns

| Jakarta result | Proposed D surface |
| --- | --- |
| `Attribute<? super X, ?>` | A common metadata interface with the declaring type available as metadata. |
| `Attribute<X, ?>` | A metadata interface parameterized by the exact declaring type `X`. |
| `SingularAttribute<? super X, Y>` | A metadata interface parameterized by value type `Y`. It retains `Bindable!Y`, `Type!Y`, and the actual declaring type as metadata. |
| `SingularAttribute<X, Y>` | The existing interface parameterized by both `X` and `Y`. |

Use the existing descriptor object through each supported metadata interface. An exact typed attribute still returns `ManagedType!X` from `getDeclaringType()`. The proposed common interfaces also let an R10 `Set` retain the matching metadata type. Declared sets can keep `X`, while inherited sets hold descriptors from different declaring types. Keep provider state insulated from writes through a returned set. Each common view retains the supported attribute kind, association and collection flags, and the declaring type's persistence kind. A singular view also retains ID, version and optionality metadata. A name-only singular result needs an erased value type that can still expose its metamodel type.

The provider verifies the supported declaring hierarchy when it binds metadata. An inherited lookup can return an attribute only from the requested type or one of its mapped supertypes. Apply the same owner and persistence-unit checks where Criteria accepts such results, including `Path.get` and `From.join`. The wildcard view retains the original declaring descriptor so a consuming path can perform those checks. Exact declaring types use the existing typed contract. A checked cast in the R4 wrapper preserves the requested value type and raises the specified `IllegalArgumentException` when no matching attribute exists. For production, share the provider lookup between the typed wrapper and name-only form. Wider class-token use follows the R4 distinction between symbolic and runtime class values.

## Proof and remaining design work

A local `@safe` prototype ran on DMD and LDC. It exercises two templated singular lookups over a hand-written provider. The inherited lookup kept the parent descriptor, the typed value, and the mapped attribute and type flags. The declared lookup returned the concrete owner's descriptor and rejected the inherited ID. Tests also rejected missing names and incompatible value types, excluded an unrelated owner at typed registration, and stored the original descriptors in manually populated inherited and declared R10 sets. The two successful lookups and their identity and type checks allocated zero current-thread GC bytes after setup.

The remaining proof covers the name-only lookup, singular sets, wrong attribute kind, typed map keys and collection elements, wildcard `Type<?>`, entity and embeddable lookup views, and exact JPA lookup diagnostics. The wildcard declaring-type view also needs the managed-type lookup surface so callers can navigate from a returned attribute to its declaring type. These depend on the registry lookup and owner checks. This is a proposed Java wildcard adaptation. Review its API and budget before adding public metadata interfaces or changing the existing inheritance. The committed API inventory continues to defer these lookups.
