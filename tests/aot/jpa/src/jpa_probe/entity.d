module jpa_probe.entity;

import flint.boot.autoconfigure : FlintBootApplication;
import flint.jakarta.persistence : Column, Entity, EntityListeners, Id, MappedSuperclass, PostLoad, Table, Transient;
import flint.java.classref : classOf;
import flint.java.time : LocalDate;

@safe:

@FlintBootApplication
final class JpaApplication
{
}

@MappedSuperclass
class OwnerBase
{
    @Id
    @Column(name: "id", nullable: false, updatable: false)
    long id;
    @Transient
    private int phase;

    @PostLoad
    void baseLoaded()
    {
        assert(phase == 1);
        phase = 2;
    }
}

final class OwnerListener
{
    @PostLoad
    void afterLoad(Owner owner)
    {
        assert(owner.id == 1 && owner.phase == 0);
        owner.phase = 1;
    }
}

@Entity("Owner")
@Table("jpa_seam_probe")
@EntityListeners([classOf!OwnerListener])
final class Owner : OwnerBase
{
    @Column(name: "name", nullable: false)
    string name;
    @Column(name: "birth_date", nullable: false)
    LocalDate birthDate;

    @PostLoad
    void ownerLoaded()
    {
        assert(phase == 2 && name == "One" && birthDate == LocalDate.of(1968, 2, 29));
        phase = 3;
    }
}

version (JpaUnreachableConstructor)
{
    @Entity
    final class UnreachableOwner
    {
        @Id
        long id;

        private this()
        {
        }
    }
}
