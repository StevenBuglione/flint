// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/{ParameterUnitTests,PreferredConstructorDiscovererUnitTests}.java
// ParameterUnitTests: Copyright 2012-present the original author or authors.
// PreferredConstructorDiscovererUnitTests: Copyright 2011-present the original author or authors.
// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/model/PersistentEntityParameterValueProviderUnitTests.java
// PersistentEntityParameterValueProviderUnitTests: Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module parameter_tests;

import flint.beans.factory.annotation : Value;
import flint.data.annotation : PersistenceCreator, Transient;
import flint.data.core : TypeInformation;
import flint.data.mapping : InstanceCreatorMetadata, MappingException, Parameter, PersistentEntity,
    PersistentProperty, PreferredConstructor;
import flint.data.mapping.model : BasicPersistentEntity, ParameterValueProvider,
    PersistentEntityParameterValueProvider, PreferredConstructorDiscoverer, PropertyValueProvider;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, DescriptorTable, MergedAnnotation,
    ParameterDescriptor, descriptorOf;
import flint.java.classref : ClassRef, classOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException, UnsupportedOperationException;
import flint.java.util : List;
import std.algorithm.searching : canFind;
import std.exception : assertThrown, collectException;
import std.typecons : Nullable;

@safe:

private final class Document
{
    long revision;
}

private final class RevisionProperty : PersistentProperty!RevisionProperty
{
    private bool transient_;

    this(bool transient_ = true)
    {
        this.transient_ = transient_;
    }

    override string getName()
    {
        return "revision";
    }

    override ClassRef getType()
    {
        return classOf!long;
    }

    override bool isIdProperty()
    {
        return false;
    }

    override bool isVersionProperty()
    {
        return false;
    }

    override bool isTransient()
    {
        return transient_;
    }

    override bool isAssociation()
    {
        return false;
    }
}

private alias DocumentEntity = PersistentEntity!(Document, RevisionProperty);

private void registerConstructors(DescriptorTable descriptors, ConstructorDescriptor[] constructors)
{
    auto descriptor = descriptorOf!Document();
    descriptor.constructors = constructors;
    descriptors.add(descriptor);
}

private DocumentEntity withConstructors(DescriptorTable descriptors, ConstructorDescriptor[] constructors)
{
    registerConstructors(descriptors, constructors);
    auto entity = new BasicPersistentEntity!(Document, RevisionProperty)(TypeInformation.of!Document(descriptors));
    entity.addPersistentProperty(new RevisionProperty(false));
    return entity;
}

private alias CreatorParameter = Parameter!(Document, RevisionProperty);

private CreatorParameter parameter(Nullable!string name)
{
    return new CreatorParameter(name, TypeInformation.of!long(DescriptorTable.withBuiltins()), null, null);
}

@("twoParametersWithIdenticalSetupEqual")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto left = new CreatorParameter(Nullable!string("revision"), TypeInformation.of!long(descriptors), null, entity);
    auto right = new CreatorParameter(Nullable!string("revision"), TypeInformation.of!long(descriptors), null, entity);
    assert(left == right && left.equals(right));
    assert(left.hashCode() == right.hashCode() && left.toHash() == right.toHash());
}

@("twoParametersWithIdenticalSetupAndNullNameEqual")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto type = TypeInformation.of!long(descriptors);
    auto left = new CreatorParameter(Nullable!string.init, type, null, entity);
    auto right = new CreatorParameter(Nullable!string.init, type, null, entity);
    assert(left.equals(right) && left.hashCode() == right.hashCode());
    assert(!left.equals(new CreatorParameter(Nullable!string(""), type, null, entity)));
}

@("twoParametersWithIdenticalAndNullEntitySetupEqual")
unittest
{
    auto left = parameter(Nullable!string("revision"));
    auto right = parameter(Nullable!string("revision"));
    assert(left.equals(right) && left.hashCode() == right.hashCode());
}

@("twoParametersWithDifferentNameAreNotEqual")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto type = TypeInformation.of!long(descriptors);
    auto left = new CreatorParameter(Nullable!string("first"), type, null, entity);
    auto right = new CreatorParameter(Nullable!string("second"), type, null, entity);
    assert(!left.equals(right));
}

@("twoParametersWithDifferenTypeAreNotEqual")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto left = new CreatorParameter(Nullable!string("revision"), TypeInformation.of!long(descriptors), null, entity);
    auto right = new CreatorParameter(Nullable!string("revision"),
            TypeInformation.of!string(descriptors), null, entity);
    assert(!left.equals(right));
}

@("parameter equality uses metadata across template bindings")
unittest
{
    auto name = Nullable!string("revision");
    auto left = parameter(name);
    auto descriptors = DescriptorTable.withBuiltins();
    auto type = TypeInformation.of!long(descriptors);
    auto right = new Parameter!(Object, RevisionProperty)(name, type, null, null);
    assert(left.equals(right) && right.equals(left));
    assert(left.hashCode() == right.hashCode());
    assert(!left.equals(new Object) && !left.equals(null));
}

@("parameter equality includes the expression and owning entity")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto otherEntity = withConstructors(DescriptorTable.withBuiltins(), null);
    auto type = TypeInformation.of!long(descriptors);
    auto name = Nullable!string("revision");
    auto annotations = [MergedAnnotation(classOf!Value.name, Any.of(Value("1")))];
    auto left = new CreatorParameter(name, type, annotations, entity);
    auto right = new CreatorParameter(name, type,
            annotations ~ [MergedAnnotation(classOf!Transient.name, Any.of(Transient.init))], entity);
    assert(left.equals(right) && left.hashCode() == right.hashCode());
    assert(!left.equals(new CreatorParameter(name, type, null, entity)));
    assert(!left.equals(new CreatorParameter(name, type, annotations, otherEntity)));
}

@("getRequiredNameDoesNotThrowExceptionWhenHasName")
unittest
{
    assert(parameter(Nullable!string("someName")).getRequiredName() == "someName");
}

@("getRequiredNameThrowsExceptionWhenHasNoName")
unittest
{
    const error = collectException!IllegalStateException(parameter(Nullable!string.init).getRequiredName());
    assert(error !is null && error.msg == "No name associated with this parameter");
}

@("hasNameReturnsTrueWhenHasName")
unittest
{
    assert(parameter(Nullable!string("someName")).hasName());
    assert(parameter(Nullable!string("")).hasName());
}

@("hasNameReturnsFalseWhenHasNoName")
unittest
{
    auto unnamed = parameter(Nullable!string.init);
    assert(!unnamed.hasName() && unnamed.getName().isNull);
}

@("parameter reads annotation metadata from a constructor descriptor")
unittest
{
    auto recorded = ParameterDescriptor("revision", classOf!long.name, [
        MergedAnnotation(classOf!Value.name, Any.of(Value("${record.revision:1}"))),
        MergedAnnotation(classOf!Transient.name, Any.of(Transient.init)),
    ]);
    auto type = TypeInformation.of!long(DescriptorTable.withBuiltins());
    auto value = new CreatorParameter(Nullable!string(recorded.name), type, recorded.annotations, null);
    assert(value.getType() is type && value.getRawType() == ClassRef(recorded.type));
    assert(value.getAnnotations().isPresent!Value() && value.isTransient());
    assert(value.hasValueExpression() && value.getRequiredValueExpression() == "${record.revision:1}");
    assert(value.getSpelExpression() == value.getValueExpression());
}

@("parameter recognizes only text expressions and the registered transient property")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Document());
    auto entity = new BasicPersistentEntity!(Document, RevisionProperty)(TypeInformation.of!Document(descriptors));
    entity.addPersistentProperty(new RevisionProperty);
    auto type = TypeInformation.of!long(descriptors);
    auto value = new CreatorParameter(Nullable!string("revision"), type,
            [MergedAnnotation(classOf!Value.name, Any.of(Value("\u2003\t")))], entity);
    assert(value.isTransient() && !value.hasValueExpression() && value.getValueExpression().isNull);
    assertThrown!IllegalStateException(value.getRequiredValueExpression());
    assertThrown!IllegalArgumentException(new CreatorParameter(Nullable!string.init, null, null, null));
}

@("registered creator metadata preserves parameter order and property membership")
unittest
{
    auto selected = ConstructorDescriptor([
        ParameterDescriptor("revision", classOf!long.name),
        ParameterDescriptor("tag", classOf!string.name, [
            MergedAnnotation(classOf!Value.name, Any.of(Value("registered")))
        ]),
    ], [MergedAnnotation(classOf!PersistenceCreator.name, Any.of(PersistenceCreator.init))]);
    auto canonical = ConstructorDescriptor([ParameterDescriptor("revision", classOf!long.name)], canonical: true);
    auto entity = withConstructors(DescriptorTable.withBuiltins(), [
        ConstructorDescriptor.init, canonical, selected
    ]);
    auto creator = entity.getInstanceCreatorMetadata();
    assert(creator !is null && creator is entity.getInstanceCreatorMetadata());
    assert(creator.hasParameters() && creator.getParameterCount() == 2);
    auto parameters = creator.getParameters();
    assert(parameters.get(0).getRequiredName() == "revision" && parameters.get(0).getRawType() == classOf!long);
    assert(parameters.get(1).getRequiredName() == "tag" && parameters.get(1).getRawType() == classOf!string);
    assert(parameters.get(1).getRequiredValueExpression() == "registered"
            && !creator.isParentParameter(parameters.get(1)));
    assertThrown!UnsupportedOperationException(parameters.clear());
    auto revision = entity.getRequiredPersistentProperty("revision");
    assert(creator.isCreatorParameter(revision) && entity.isCreatorArgument(revision));
    assert(!entity.isCreatorArgument(null) && !entity.isCreatorArgument(new RevisionProperty(false)));
}

@("creator selection distinguishes canonical, default, sole and ambiguous constructors")
unittest
{
    ParameterDescriptor[] revision = [ParameterDescriptor("revision", classOf!long.name)];
    auto canonical = ConstructorDescriptor(revision, canonical: true);
    auto primary = ConstructorDescriptor(revision);
    auto alternative = ConstructorDescriptor([ParameterDescriptor("tag", classOf!string.name)]);
    auto noArguments = ConstructorDescriptor.init;
    auto descriptors = DescriptorTable.withBuiltins();
    assert(withConstructors(descriptors, [noArguments, canonical]).getInstanceCreatorMetadata().hasParameters());
    assert(!withConstructors(descriptors, [primary, noArguments]).getInstanceCreatorMetadata().hasParameters());
    assert(withConstructors(descriptors, [primary]).getInstanceCreatorMetadata().getParameterCount() == 1);
    assert(withConstructors(descriptors, [primary, alternative]).getInstanceCreatorMetadata() is null);
    assert(withConstructors(descriptors, null).getInstanceCreatorMetadata() is null);
}

private final class LateParameterType
{
}

@("creator metadata can be retried after registering a missing parameter type")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors,
            [ConstructorDescriptor([ParameterDescriptor("extra", classOf!LateParameterType.name)])]);
    assertThrown!IllegalStateException(entity.getInstanceCreatorMetadata());
    descriptors.add(descriptorOf!LateParameterType());
    assert(entity.getInstanceCreatorMetadata().getParameters().get(0).getRawType() == classOf!LateParameterType);
}

private alias Discoverer = PreferredConstructorDiscoverer;
private alias DocumentConstructor = PreferredConstructor!(Document, RevisionProperty);

private ConstructorDescriptor revisionConstructor()
{
    return ConstructorDescriptor([ParameterDescriptor("revision", classOf!long.name)]);
}

private ConstructorDescriptor taggedConstructor(bool annotated = false)
{
    return ConstructorDescriptor([ParameterDescriptor("tag", classOf!string.name)], annotated
            ? [MergedAnnotation(classOf!PersistenceCreator.name, Any.of(PersistenceCreator.init))] : null);
}

private ConstructorDescriptor canonicalConstructor()
{
    return ConstructorDescriptor([
        ParameterDescriptor("revision", classOf!long.name),
        ParameterDescriptor("tag", classOf!string.name),
    ], canonical: true);
}

@("findsNoArgConstructorForClassWithoutExplicitConstructor")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Document());
    auto constructor = Discoverer.discover!(Document, RevisionProperty)(descriptors);
    assert(constructor !is null && constructor.isNoArgConstructor());
    assert(!constructor.isExplicitlyAnnotated() && constructor.getConstructor().invoke !is null);
}

@("findsNoArgConstructorForClassWithMultipleConstructorsAndNoArgOne")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, [revisionConstructor(), ConstructorDescriptor.init]);
    auto constructor = Discoverer.discover(entity);
    assert(constructor !is null && constructor.isNoArgConstructor());
    assert(!constructor.isExplicitlyAnnotated() && constructor.getParameters().isEmpty());
}

@("doesNotThrowExceptionForMultipleConstructorsAndNoNoArgConstructorWithoutAnnotation")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, [revisionConstructor(), taggedConstructor()]);
    assert(Discoverer.discover!(Document, RevisionProperty)(descriptors) is null);
    assert(entity.getInstanceCreatorMetadata() is null);
}

@("usesConstructorWithAnnotationOverEveryOther")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto annotated = revisionConstructor();
    annotated.annotations = [
        MergedAnnotation(classOf!PersistenceCreator.name, Any.of(PersistenceCreator.init))
    ];
    auto entity = withConstructors(descriptors, [
        ConstructorDescriptor.init, taggedConstructor(), annotated
    ]);
    auto constructor = Discoverer.discover(entity);
    assert(constructor !is null && !constructor.isNoArgConstructor() && constructor.isExplicitlyAnnotated());
    assert(constructor.getParameters().size() == 1 && constructor.getParameters().get(0).getRawType() == classOf!long);
    assert(constructor.isCreatorParameter(entity.getRequiredPersistentProperty("revision")));
    auto cached = cast(DocumentConstructor) entity.getInstanceCreatorMetadata();
    assert(cached !is null && cached is entity.getInstanceCreatorMetadata());
    assert(cached.getParameters().get(0).equals(constructor.getParameters().get(0)));
}

@("detectsCanonicalRecordConstructorWhenRecordHasSingleArgConstructor")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    registerConstructors(descriptors, [revisionConstructor(), canonicalConstructor()]);
    auto constructor = Discoverer.discover!(Document, RevisionProperty)(descriptors);
    assert(constructor !is null && constructor.getConstructor().canonical);
    auto parameters = constructor.getParameters();
    assert(parameters.size() == 2);
    assert(parameters.get(0).getRawType() == classOf!long && parameters.get(1).getRawType() == classOf!string);
}

@("detectsMetaAnnotatedValueAnnotation")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto recorded = ParameterDescriptor("revision", classOf!long.name,
            [MergedAnnotation(classOf!Value.name, Any.of(Value("${hello-world}")), distance: 1),]);
    registerConstructors(descriptors, [ConstructorDescriptor([recorded])]);
    auto constructor = Discoverer.discover!(Document, RevisionProperty)(descriptors);
    assert(constructor !is null && constructor.getParameterCount() == 1);
    auto param = constructor.getParameters().get(0);
    assert(param.getRequiredValueExpression() == "${hello-world}" && param.getAnnotations().isPresent!Value());
}

@("detectsCanonicalRecordConstructorWhenRecordHasNoArgConstructor")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    registerConstructors(descriptors, [ConstructorDescriptor.init, canonicalConstructor()]);
    auto constructor = Discoverer.discover!(Document, RevisionProperty)(descriptors);
    assert(constructor !is null && !constructor.isNoArgConstructor() && constructor.getConstructor().canonical);
    assert(constructor.getParameterCount() == 2);
}

@("detectsAnnotatedRecordConstructor")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    registerConstructors(descriptors, [canonicalConstructor(), taggedConstructor(true)]);
    auto constructor = Discoverer.discover!(Document, RevisionProperty)(descriptors);
    assert(constructor !is null && constructor.isExplicitlyAnnotated() && !constructor.getConstructor().canonical);
    assert(constructor.getParameterCount() == 1 && constructor.getParameters().get(0).getRawType() == classOf!string);
}

@("preferred constructor accepts typed parameters and exposes a read-only list")
unittest
{
    auto revision = parameter(Nullable!string("revision"));
    auto constructor = new DocumentConstructor(revisionConstructor(), revision);
    assert(constructor.getConstructor().parameters[0].name == "revision");
    assert(constructor.getParameters().get(0) is revision);
    assertThrown!UnsupportedOperationException(constructor.getParameters().clear());
    assertThrown!IllegalArgumentException(Discoverer.discover(cast(DocumentEntity) null));
}

private alias DocumentParameterProvider = ParameterValueProvider!(Document, RevisionProperty);
private alias DocumentValueProvider = PersistentEntityParameterValueProvider!(Document, RevisionProperty);

private final class RevisionValues : PropertyValueProvider!RevisionProperty
{
    private RevisionProperty received;

    override Any getPropertyValue(RevisionProperty property)
    {
        received = property;
        return Any.of(23L);
    }
}

@("rejectsPropertyIfNameDoesNotMatch")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, [taggedConstructor()]);
    auto values = new RevisionValues;
    DocumentParameterProvider provider = new DocumentValueProvider(entity, values, Any.init);
    auto argument = entity.getInstanceCreatorMetadata().getParameters().get(0);
    const error = collectException!MappingException(provider.getParameterValue(argument));
    assert(error !is null && error.msg.canFind("tag") && error.msg.canFind(classOf!Document.name));
    assert(values.received is null);
}

@("parameter provider requests the registered property and reports an absent name")
unittest
{
    auto entity = withConstructors(DescriptorTable.withBuiltins(), [revisionConstructor()]);
    auto values = new RevisionValues;
    DocumentParameterProvider provider = new DocumentValueProvider(entity, values, Any.init);
    auto argument = entity.getInstanceCreatorMetadata().getParameters().get(0);
    assert(provider.getParameterValue(argument).get!long == 23L);
    assert(values.received is entity.getRequiredPersistentProperty("revision"));

    const error = collectException!MappingException(provider.getParameterValue(parameter(Nullable!string.init)));
    assert(error !is null && error.msg.canFind("does not have a name"));
}

@("transient parameters receive typed primitive defaults or an absent reference")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    auto entity = withConstructors(descriptors, null);
    auto provider = new DocumentValueProvider(entity, (RevisionProperty) => Any.of(42L), Any.init);
    auto annotations = [MergedAnnotation(classOf!Transient.name, Any.of(Transient.init))];
    auto number = new CreatorParameter(Nullable!string.init,
            TypeInformation.of!double(descriptors), annotations, entity);
    auto reference = new CreatorParameter(Nullable!string.init,
            TypeInformation.of!string(descriptors), annotations, entity);
    assert(provider.getParameterValue(number).get!double == 0.0);
    assert(provider.getParameterValue(reference).isNull());
    assert(DocumentParameterProvider.getDefaultValue(classOf!char).get!char == '\0');
    assert(!DocumentParameterProvider.getDefaultValue(classOf!bool).get!bool);
}

private alias DocumentCreator = InstanceCreatorMetadata!(Document, RevisionProperty);

private class DefaultingCreator : DocumentCreator
{
    private List!CreatorParameter parameters;

    this(CreatorParameter[] parameters...)
    {
        this.parameters = List!CreatorParameter.of(parameters);
    }

    mixin DocumentCreator.Defaults;

    override bool isCreatorParameter(PersistentProperty!())
    {
        return false;
    }

    override List!CreatorParameter getParameters()
    {
        return parameters;
    }
}

private final class ParentCreator : DefaultingCreator
{
    this(CreatorParameter parentParameter)
    {
        super(parentParameter);
    }

    override bool isParentParameter(CreatorParameter parameter)
    {
        return getParameters().get(0) is parameter;
    }
}

@("creator defaults work in a concrete implementation outside their source module")
unittest
{
    auto argument = parameter(Nullable!string("revision"));
    DocumentCreator creator = new DefaultingCreator(argument);
    assert(creator.hasParameters() && creator.getParameterCount() == 1);
    assert(!creator.isParentParameter(argument));

    DocumentCreator empty = new DefaultingCreator();
    assert(!empty.hasParameters() && empty.getParameterCount() == 0);
}

private final class ParentDocumentEntity : BasicPersistentEntity!(Document, RevisionProperty)
{
    private DocumentCreator creator;

    this(TypeInformation type, CreatorParameter parentParameter)
    {
        super(type);
        creator = new ParentCreator(parentParameter);
    }

    override DocumentCreator getInstanceCreatorMetadata()
    {
        return creator;
    }
}

@("parameter provider preserves the parent supplied by the creator metadata")
unittest
{
    auto descriptors = DescriptorTable.withBuiltins();
    descriptors.add(descriptorOf!Document());
    auto argument = parameter(Nullable!string.init);
    auto entity = new ParentDocumentEntity(TypeInformation.of!Document(descriptors), argument);
    auto values = new RevisionValues;
    auto parent = new Object;
    auto provider = new DocumentValueProvider(entity, values, Any.of(parent));
    assert(provider.getParameterValue(argument).get!Object is parent);
    assert(values.received is null);
}
