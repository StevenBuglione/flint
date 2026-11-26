module entity_information_tests;

import flint.data.repository.core : EntityInformation, EntityMetadata;
import flint.data.repository.core.support : DelegatingEntityInformation;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException;
import std.typecons : Nullable;

@safe:

private final class Entity
{
    override string toString() const
    {
        return "test entity";
    }
}

private class Information(ID) : EntityInformation!(Entity, ID)
{
    alias Id = typeof((cast(EntityInformation!(Entity, ID)) null).getId(null));
    Id id;
    int lookups;

    mixin EntityInformation!(Entity, ID).Defaults;

    override ClassRef getJavaType()
    {
        return classOf!Entity;
    }

    override bool isNew(Entity entity)
    {
        return entity !is null;
    }

    override Id getId(Entity entity)
    {
        lookups++;
        return id;
    }

    override ClassRef getIdType()
    {
        return classOf!ID;
    }
}

@("required value identifier preserves zero and distinguishes null entities from absent IDs")
unittest
{
    auto source = new Information!long;
    EntityInformation!(Entity, long) information = source;
    auto entity = new Entity;

    try
    {
        information.getRequiredId(null);
        assert(0, "Null entity accepted");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Entity must not be null");
    }
    assert(source.lookups == 0);

    try
    {
        information.getRequiredId(entity);
        assert(0, "Absent identifier accepted");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Could not obtain required identifier from entity test entity");
    }
    source.id = Nullable!long(0);
    assert(information.getRequiredId(entity) == 0);
    assert(source.lookups == 2);
}

private final class CustomRequiredId : Information!Object
{
    override Object getRequiredId(Entity entity)
    {
        assert(0, "The delegating instance must use its own interface default");
    }
}

@("metadata delegation preserves reference identifier identity and uses the interface default")
unittest
{
    auto source = new CustomRequiredId;
    auto entity = new Entity;
    auto id = new Object;
    source.id = id;
    EntityInformation!(Entity, Object) information = new DelegatingEntityInformation!(Entity, Object)(source);
    EntityMetadata!Entity metadata = information;
    assert(metadata.getJavaType() == classOf!Entity);
    assert(information.getIdType() == classOf!Object);
    assert(information.isNew(entity) && !information.isNew(null));
    assert(information.getId(entity) is id);
    assert(information.getRequiredId(entity) is id);
    assert(source.lookups == 2);
}
