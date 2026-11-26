/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.criteria_metamodel_test;

import flint.jakarta.persistence.criteria : JoinType, Nulls;
import flint.jakarta.persistence.metamodel : BasicType, Bindable, StaticMetamodel, Type;
import flint.jakarta.persistence.metamodel_runtime : Attribute, CollectionAttribute, EmbeddableType,
    ListAttribute, ManagedType, MapAttribute, PluralAttribute, SetAttribute, SingularAttribute;
import flint.java.classref : ClassRef, classOf;
import flint.java.util : Collection, List, Map, Set;
import std.traits : EnumMembers, getUDAs;

@safe:

private final class Owner
{
}

@StaticMetamodel(classOf!Owner)
private final class OwnerMetamodel
{
}

@("metamodel contracts expose class tokens through typed provider interfaces")
unittest
{
    static final class BasicLong : BasicType!long, Bindable!long
    {
        override Type!long.PersistenceType getPersistenceType()
        {
            return Type!long.PersistenceType.BASIC;
        }

        override ClassRef getJavaType()
        {
            return classOf!long;
        }

        override Bindable!long.BindableType getBindableType()
        {
            return Bindable!long.BindableType.PLURAL_ATTRIBUTE;
        }

        override ClassRef getBindableJavaType()
        {
            return classOf!long;
        }
    }

    auto descriptor = new BasicLong;
    Type!long persistentType = descriptor;
    Bindable!long binding = descriptor;
    assert(persistentType.getPersistenceType() == Type!long.PersistenceType.BASIC);
    assert(persistentType.getJavaType() == classOf!long);
    assert(binding.getBindableType() == Bindable!long.BindableType.PLURAL_ATTRIBUTE);
    assert(binding.getBindableJavaType() == classOf!long);

    static assert(is(Type!long.PersistenceType == Type!Owner.PersistenceType));
    static assert(is(Bindable!long.BindableType == Bindable!Owner.BindableType));
    static assert(getUDAs!(OwnerMetamodel, StaticMetamodel)[0].value == classOf!Owner);
}

@("Criteria option enums preserve Jakarta declaration order")
unittest
{
    static assert([EnumMembers!JoinType] == [JoinType.INNER, JoinType.LEFT, JoinType.RIGHT]);
    static assert([EnumMembers!Nulls] == [Nulls.NONE, Nulls.FIRST, Nulls.LAST]);
}

private final class BasicDescriptor(T) : BasicType!T
{
    override Type!T.PersistenceType getPersistenceType()
    {
        return Type!T.PersistenceType.BASIC;
    }

    override ClassRef getJavaType()
    {
        return classOf!T;
    }
}

@("a map attribute links its declaring type, key type and bindable value type")
unittest
{
    static final class OwnerType : EmbeddableType!Owner
    {
        override Type!Owner.PersistenceType getPersistenceType()
        {
            return Type!Owner.PersistenceType.EMBEDDABLE;
        }

        override ClassRef getJavaType()
        {
            return classOf!Owner;
        }
    }

    alias AttributeMap = Map!(string, long);

    static final class ValuesAttribute : MapAttribute!(Owner, string, long)
    {
        override string getName()
        {
            return "values";
        }

        override Attribute!(Owner, AttributeMap).PersistentAttributeType getPersistentAttributeType()
        {
            return Attribute!(Owner, AttributeMap).PersistentAttributeType.ELEMENT_COLLECTION;
        }

        override ManagedType!Owner getDeclaringType()
        {
            return new OwnerType;
        }

        override ClassRef getJavaType()
        {
            return classOf!AttributeMap;
        }

        override bool isAssociation()
        {
            return false;
        }

        override bool isCollection()
        {
            return true;
        }

        override Bindable!long.BindableType getBindableType()
        {
            return Bindable!long.BindableType.PLURAL_ATTRIBUTE;
        }

        override ClassRef getBindableJavaType()
        {
            return classOf!long;
        }

        override PluralAttribute!(Owner, AttributeMap, long).CollectionType getCollectionType()
        {
            return PluralAttribute!(Owner, AttributeMap, long).CollectionType.MAP;
        }

        override Type!long getElementType()
        {
            return new BasicDescriptor!long;
        }

        override ClassRef getKeyJavaType()
        {
            return classOf!string;
        }

        override Type!string getKeyType()
        {
            return new BasicDescriptor!string;
        }
    }

    MapAttribute!(Owner, string, long) values = new ValuesAttribute;
    Attribute!(Owner, AttributeMap) attribute = values;
    PluralAttribute!(Owner, AttributeMap, long) collection = values;
    Bindable!long binding = values;
    assert(attribute.getName() == "values" && attribute.isCollection() && !attribute.isAssociation());
    assert(attribute.getDeclaringType().getJavaType() == classOf!Owner);
    assert(attribute.getPersistentAttributeType() == Attribute!(Owner, AttributeMap)
            .PersistentAttributeType.ELEMENT_COLLECTION);
    assert(attribute.getJavaType() == classOf!AttributeMap);
    assert(collection.getCollectionType() == PluralAttribute!(Owner, AttributeMap, long).CollectionType.MAP);
    assert(collection.getElementType().getJavaType() == binding.getBindableJavaType());
    assert(binding.getBindableType() == Bindable!long.BindableType.PLURAL_ATTRIBUTE);
    assert(values.getKeyType().getJavaType() == values.getKeyJavaType());
    assert(values.getKeyJavaType() == classOf!string);
}

@("the metamodel preserves attribute specialization and shares nested kind types")
unittest
{
    static assert(is(SingularAttribute!(Owner, long) : Attribute!(Owner, long)));
    static assert(is(SingularAttribute!(Owner, long) : Bindable!long));
    static assert(is(typeof(SingularAttribute!(Owner, long).init.isId()) == bool));
    static assert(is(typeof(SingularAttribute!(Owner, long).init.isVersion()) == bool));
    static assert(is(typeof(SingularAttribute!(Owner, long).init.isOptional()) == bool));
    static assert(is(typeof(SingularAttribute!(Owner, long).init.getType()) == Type!long));
    static assert(is(CollectionAttribute!(Owner, long) : PluralAttribute!(Owner, Collection!long, long)));
    static assert(is(ListAttribute!(Owner, long) : PluralAttribute!(Owner, List!long, long)));
    static assert(is(SetAttribute!(Owner, long) : PluralAttribute!(Owner, Set!long, long)));
    static assert(is(Attribute!(Owner, long).PersistentAttributeType == Attribute!(Owner, string)
            .PersistentAttributeType));
    static assert(is(PluralAttribute!(Owner, List!long, long)
            .CollectionType == PluralAttribute!(Owner, Set!string, string).CollectionType));
    alias Kind = Attribute!(Owner, long).PersistentAttributeType;
    static assert([EnumMembers!Kind] == [
        Kind.MANY_TO_ONE, Kind.ONE_TO_ONE, Kind.BASIC, Kind.EMBEDDED, Kind.MANY_TO_MANY,
        Kind.ONE_TO_MANY, Kind.ELEMENT_COLLECTION
    ]);
    alias Shape = PluralAttribute!(Owner, List!long, long).CollectionType;
    static assert([EnumMembers!Shape] == [Shape.COLLECTION, Shape.SET, Shape.LIST, Shape.MAP]);
}
