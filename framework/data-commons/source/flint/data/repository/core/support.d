// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/repository/core/support/DelegatingEntityInformation.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.repository.core.support;

import flint.data.domain.persistable : NullableId;
import flint.data.repository.core : EntityInformation;
import flint.java.classref : ClassRef;

@safe:

/// An EntityInformation that forwards metadata and state to another instance.
class DelegatingEntityInformation(T, ID) : EntityInformation!(T, ID)
{
    private EntityInformation!(T, ID) delegateInformation;

    /// Wraps the supplied metadata.
    this(EntityInformation!(T, ID) delegateInformation)
    {
        this.delegateInformation = delegateInformation;
    }

    mixin EntityInformation!(T, ID).Defaults;

    override ClassRef getJavaType()
    {
        return delegateInformation.getJavaType();
    }

    override bool isNew(T entity)
    {
        return delegateInformation.isNew(entity);
    }

    override NullableId!ID getId(T entity)
    {
        return delegateInformation.getId(entity);
    }

    override ClassRef getIdType()
    {
        return delegateInformation.getIdType();
    }
}
