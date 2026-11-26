module jpa_probe.entity;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.jakarta.persistence : Column, Entity, EntityListeners, Id, MappedSuperclass, PostLoad, Table, Transient;
import flint.java.classref : classOf;
import flint.java.time : LocalDate;

@safe:

/// Activates AOT extraction for the fixture.
@FlintBootApplication
final class JpaApplication
{
}

/// Declares the inherited identifier and the second callback.
@MappedSuperclass
class OwnerIdentity
{
    /// Assigned primary key.
    @Id
    @Column(name: "id", nullable: false, updatable: false)
    long id;
    @Transient
    private int phase;

    /// Runs after the listener.
    @PostLoad
    void identityLoaded()
    {
        assert(phase == 1);
        phase = 2;
    }
}

/// Adds a persistent field and callback between the identifier class and concrete entity.
@MappedSuperclass
class OwnerBase : OwnerIdentity
{
    /// External code carried through row materialization.
    @Column(nullable: false)
    string code;

    /// Runs after the identifier class's callback.
    @PostLoad
    void baseLoaded()
    {
        assert(phase == 2 && code == "C1");
        phase = 3;
    }
}

/// Checks the first callback sees the materialized identifier.
final class OwnerListener
{
    /// Records listener invocation.
    @PostLoad
    void afterLoad(OwnerIdentity owner)
    {
        assert(owner.id == 1 && owner.phase == 0);
        owner.phase = 1;
    }

    /// An unannotated overload that the generated callback must skip.
    void afterLoad(Owner owner)
    {
        assert(owner is null, "unexpected exact-type PostLoad overload");
    }
}

/// Maps the text and DATE columns of the fixture table.
@Entity("Owner")
@Table("jpa_seam_probe")
@EntityListeners([classOf!OwnerListener])
final class Owner : OwnerBase
{
    /// Owner's display name.
    @Column(name: "name", nullable: false)
    string name;
    /// Owner's birth date.
    @Column(name: "birth_date", nullable: false)
    LocalDate birthDate;

    /// Checks that owned fields and the superclass callback are ready.
    @PostLoad
    void ownerLoaded()
    {
        assert(phase == 3 && name == "One" && birthDate == LocalDate.of(1968, 2, 29));
        phase = 4;
    }

    /// Final lifecycle phase observed by the linked test.
    int loadedPhase() const
    {
        return phase;
    }
}

version (JpaUnreachableConstructor)
{
    /// Exercises the diagnostic for a generated constructor call.
    @Entity
    final class UnreachableOwner
    {
        /// Assigned primary key.
        @Id
        long id;

        private this()
        {
        }
    }
}

version (JpaStatefulListener)
{
    /// Exercises the diagnostic for a listener needing per-unit storage.
    final class StatefulListener
    {
        /// Number of loads observed by this instance.
        int count;

        /// Increments the instance counter.
        @PostLoad
        void afterLoad(Object)
        {
            ++count;
        }
    }

    /// References the stateful listener from a mapped entity.
    @Entity
    @EntityListeners([classOf!StatefulListener])
    final class StatefulOwner
    {
        /// Assigned primary key.
        @Id
        long id;
    }
}
