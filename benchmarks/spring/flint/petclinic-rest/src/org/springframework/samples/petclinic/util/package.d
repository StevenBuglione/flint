/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.util.EntityUtils`,
ported to Flint. Copyright 2002-2013 the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: `Class<T> entityClass` is the template parameter `T` (R4).
+/
module org.springframework.samples.petclinic.util;

import flint.engine.aot.any : Any;
import flint.java.util : Collection;
import flint.orm : ObjectRetrievalFailureException;
import org.springframework.samples.petclinic.model : BaseEntity;

@safe:

/// Utility methods for handling entities.
abstract class EntityUtils
{
    /// Look up the entity of the given class with the given id in the given collection. Throws
    /// `ObjectRetrievalFailureException` if the entity was not found.
    static T getById(T : BaseEntity, E:
            T)(Collection!E entities, int entityId)
    {
        foreach (entity; entities.toArray())
        {
            if (entity.getId() == entityId)
            {
                if (auto typed = cast(T) entity)
                    return typed;
            }
        }
        throw new ObjectRetrievalFailureException(typeid(T), Any.of(entityId));
    }
}
