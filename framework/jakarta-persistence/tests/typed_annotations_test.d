/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.typed_annotations_test;

import flint.java.classref : classOf;
import flint.jakarta.persistence : CascadeType, ElementCollection, FetchType, IdClass, ManyToMany,
    ManyToOne, OneToMany, OneToOne;

@safe:

@("target and identifier tokens preserve D class and struct names for AOT")
unittest
{
    static struct Key
    {
        long id;
    }

    @IdClass(classOf!Key)
    static class Owner
    {
    }

    const target = ManyToOne(classOf!Owner, [CascadeType.PERSIST]);
    assert(target.targetEntity == classOf!Owner);
    assert(target.cascade == [CascadeType.PERSIST]);
    assert(target.fetch == FetchType.EAGER && target.optional);
    enum id = __traits(getAttributes, Owner)[0];
    assert(id.value == classOf!Key);
}

@("omitted association and collection targets leave inference to the provider")
unittest
{
    assert(OneToMany().targetEntity.name == "");
    assert(OneToMany().fetch == FetchType.LAZY && OneToMany().cascade.length == 0);
    assert(!OneToMany().orphanRemoval);
    assert(OneToOne().fetch == FetchType.EAGER && OneToOne().optional);
    assert(ManyToMany().fetch == FetchType.LAZY && ManyToMany().mappedBy == "");
    assert(ElementCollection().fetch == FetchType.LAZY && ElementCollection().targetClass.name == "");
}
