module annotation_contracts_test;

import flint.java.classref : ClassRef, classOf;
import flint.java.lang.annotation : PkgDocumented = Documented, PkgElementType = ElementType, PkgInherited = Inherited,
    PkgNative = Native, PkgRepeatable = Repeatable, PkgRetention = Retention,
    PkgRetentionPolicy = RetentionPolicy, PkgTarget = Target;
import flint.java.lang.annotation.documented : Documented;
import flint.java.lang.annotation.elementtype : ElementType;
import flint.java.lang.annotation.inherited : Inherited;
import flint.java.lang.annotation.native : Native;
import flint.java.lang.annotation.repeatable : Repeatable;
import flint.java.lang.annotation.retention : Retention;
import flint.java.lang.annotation.retentionpolicy : RetentionPolicy;
import flint.java.lang.annotation.target : Target;

@safe:

private struct SampleContainer
{
}

@Documented
@Inherited
@Retention(RetentionPolicy.RUNTIME)
@Target([ElementType.TYPE, ElementType.METHOD])
@Repeatable(classOf!SampleContainer)
private struct SampleAnnotation
{
    @Native
    enum int FLAG = 1;
}

@("ElementType matches Java SE 21 constant names and ordinals")
unittest
{
    static assert(is(ElementType == PkgElementType));
    static immutable ElementType[12] ordered = [
        ElementType.TYPE, ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER,
        ElementType.CONSTRUCTOR, ElementType.LOCAL_VARIABLE, ElementType.ANNOTATION_TYPE,
        ElementType.PACKAGE, ElementType.TYPE_PARAMETER, ElementType.TYPE_USE,
        ElementType.MODULE, ElementType.RECORD_COMPONENT,
    ];
    foreach (idx, value; ordered)
        assert(cast(size_t) value == idx);
    assert(ElementType.min == ElementType.TYPE);
    assert(ElementType.max == ElementType.RECORD_COMPONENT);
}

@("RetentionPolicy matches Java SE 21 constant names and ordinals")
unittest
{
    static assert(is(RetentionPolicy == PkgRetentionPolicy));
    static immutable RetentionPolicy[3] ordered = [
        RetentionPolicy.SOURCE, RetentionPolicy.CLASS, RetentionPolicy.RUNTIME,
    ];
    foreach (idx, value; ordered)
        assert(cast(size_t) value == idx);
    assert(RetentionPolicy.min == RetentionPolicy.SOURCE);
    assert(RetentionPolicy.max == RetentionPolicy.RUNTIME);
}

@("R2 meta-annotation UDA structs preserve identity, attributes, and ClassRef")
unittest
{
    static assert(is(Documented == PkgDocumented));
    static assert(is(Inherited == PkgInherited));
    static assert(is(Native == PkgNative));
    static assert(is(Retention == PkgRetention));
    static assert(is(Target == PkgTarget));
    static assert(is(Repeatable == PkgRepeatable));

    alias attrs = __traits(getAttributes, SampleAnnotation);
    static assert(attrs.length == 5);
    static assert(is(attrs[0] == Documented));
    static assert(is(attrs[1] == Inherited));
    static assert(attrs[2] == Retention(RetentionPolicy.RUNTIME));
    static assert(attrs[3].value == [ElementType.TYPE, ElementType.METHOD]);
    static assert(attrs[4] == Repeatable(classOf!SampleContainer));

    alias flagAttrs = __traits(getAttributes, SampleAnnotation.FLAG);
    static assert(flagAttrs.length == 1 && is(flagAttrs[0] == Native));

    const unset = Repeatable(ClassRef.init);
    assert(unset.value.name is null);
    assert(unset.value.toString() == "null");

    const set = Repeatable(classOf!SampleContainer);
    assert(set.value.name.length > 0);
}
