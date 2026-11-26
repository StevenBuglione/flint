module data_annotation_tests;

import flint.data.annotation : AccessType, CreatedBy, CreatedDate, Id, Immutable, LastModifiedBy,
    LastModifiedDate, Persistent, ReadOnlyProperty, Reference, Transient, TypeAlias, Version;
import flint.engine.aot.descriptor : MergedAnnotation, descriptorOf;
import flint.java.classref : ClassRef, classOf;

@safe:

@TypeAlias("accounts")
@Immutable
@AccessType(AccessType.Type.PROPERTY)
private class Account
{
    @Id
    long getKey()
    {
        return 42;
    }

    @Version
    int revision;

    @CreatedBy
    string creator;

    @CreatedDate
    long created;

    @LastModifiedBy
    string editor;

    @LastModifiedDate
    long edited;

    @ReadOnlyProperty
    string accountNumber;

    @Transient
    string temporary;
}

private final class PremiumAccount : Account
{
}

@Reference(to: classOf!Account)
private struct AccountReference
{
}

private final class Invoice
{
    @Reference(classOf!Account)
    long owner;

    @AccountReference
    long debtor;

    @Reference
    long other;
}

private T annotationValue(T)(scope const(MergedAnnotation)[] annotations)
{
    foreach (ref annotation; annotations)
    {
        if (annotation.type == classOf!T.name)
        {
            assert(annotation.error is null);
            return annotation.value.get!T();
        }
    }
    assert(false, "Missing annotation " ~ classOf!T.name);
}

@("Persistence and audit annotations are discoverable on fields and getters")
unittest
{
    auto descriptor = descriptorOf!Account();
    annotationValue!Id(descriptor.property("key").annotations);
    annotationValue!Version(descriptor.property("revision").annotations);
    annotationValue!CreatedBy(descriptor.property("creator").annotations);
    annotationValue!CreatedDate(descriptor.property("created").annotations);
    annotationValue!LastModifiedBy(descriptor.property("editor").annotations);
    annotationValue!LastModifiedDate(descriptor.property("edited").annotations);
    annotationValue!ReadOnlyProperty(descriptor.property("accountNumber").annotations);
    annotationValue!Transient(descriptor.property("temporary").annotations);
}

@("Type aliases compose Persistent and remain observable through the owner type hierarchy")
unittest
{
    auto descriptor = descriptorOf!Account();
    assert(annotationValue!TypeAlias(descriptor.annotations).value == "accounts");
    assert(annotationValue!AccessType(descriptor.annotations).value == AccessType.Type.PROPERTY);
    annotationValue!Immutable(descriptor.annotations);
    annotationValue!Persistent(descriptor.annotations);

    auto inherited = descriptorOf!PremiumAccount();
    assert(annotationValue!TypeAlias(inherited.annotations).value == "accounts");
}

@("Reference mirrors direct and composed class attributes")
unittest
{
    auto descriptor = descriptorOf!Invoice();
    foreach (name; ["owner", "debtor"])
    {
        const reference = annotationValue!Reference(descriptor.property(name).annotations);
        assert(reference.value == classOf!Account && reference.to == classOf!Account);
    }

    const reference = annotationValue!Reference(descriptor.property("other").annotations);
    assert(reference.value == ClassRef.init && reference.to == ClassRef.init);
}
