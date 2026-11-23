/// The semantic model Flint AOT extracts from the compiler (schema `flint.aot.model/1`, docs/spring/aot-contract.md
/// section 1.1).
///
/// The extraction compile prints one JSON document per module. This module reads those documents into plain
/// structs; the analysis and the emitters never see JSON.
module flint_tool.engine.aot.model;

import std.json : JSONValue;

@safe:

/// An attribute value, as the compiler evaluated it.
struct Value
{
    /// What the value holds.
    enum Kind
    {
        null_,
        boolean,
        integer,
        text,
        array,
        annotation,
        enumMember,
        raw
    }

    /// What the value holds.
    Kind kind;
    /// For `boolean`.
    bool boolean;
    /// For `integer`.
    long integer;
    /// For `text`; the member name for `enumMember`; D source for `raw`.
    string text;
    /// For `array`.
    Value[] items;
    /// For `annotation` (a nested struct value): exactly one element.
    Annotation[] nested;
    /// For `enumMember`: the enum's type name.
    string enumType;
    /// Modules a rendering of the value must import.
    string[] modules;

    /// A value equal to the type's default: null, false, zero, empty text or an empty array.
    bool isEmpty() const
    {
        final switch (kind)
        {
        case Kind.null_:
            return true;
        case Kind.boolean:
            return !boolean;
        case Kind.integer:
            return integer == 0;
        case Kind.text:
            return text.length == 0;
        case Kind.array:
            return items.length == 0;
        case Kind.annotation, Kind.enumMember, Kind.raw:
            return false;
        }
    }

    /// Deep equality; a null string, an empty string and an empty array are equal.
    bool same(const ref Value other) const
    {
        if (isEmpty && other.isEmpty && !scalar)
            return !other.scalar;
        if (kind != other.kind)
            return false;
        switch (kind)
        {
        case Kind.boolean, Kind.integer:
            return boolean == other.boolean && integer == other.integer;
        case Kind.text, Kind.raw, Kind.enumMember:
            return text == other.text && enumType == other.enumType;
        case Kind.array:
            return sameItems(other);
        case Kind.annotation:
            return nested[0].same(other.nested[0]);
        default:
            return true;
        }
    }

    private bool scalar() const
    {
        return kind == Kind.boolean || kind == Kind.integer;
    }

    private bool sameItems(const ref Value other) const
    {
        if (items.length != other.items.length)
            return false;
        foreach (index, ref item; items)
        {
            if (!item.same(other.items[index]))
                return false;
        }
        return true;
    }

    /// The text of a string value, or of the first element of a string array (Java's single-value form).
    string first() const
    {
        if (kind == Kind.text)
            return text;
        if (kind == Kind.array && items.length && items[0].kind == Kind.text)
            return items[0].text;
        return null;
    }

    /// Every string of a string or string-array value.
    string[] strings() const
    {
        if (kind == Kind.text)
            return text.length ? [text] : null;
        // A single ClassRef (`@ConditionalOnSingleCandidate(ClassRef(...))`): its type name.
        if (kind == Kind.annotation && nested.length)
        {
            const name = nested[0].text("name");
            return name.length ? [name] : null;
        }
        string[] result;
        if (kind == Kind.array)
        {
            foreach (ref item; items)
            {
                if (item.kind == Kind.text)
                    result ~= item.text;
                else if (item.kind == Kind.annotation)
                    result ~= item.nested[0].text("name");
            }
        }
        return result;
    }
}

/// One annotation: a UDA struct value.
struct Annotation
{
    /// Fully qualified type name.
    string type;
    /// Modules a rendering must import.
    string[] modules;
    /// Field names in declaration order.
    string[] names;
    /// Field values, parallel to `names`.
    Value[] values;

    /// The value of a field (a copy), or a null value.
    Value get(string name) const
    {
        foreach (index, field; names)
        {
            if (field == name)
                return clone(values[index]);
        }
        return Value.init;
    }

    /// Set a field, adding it when absent.
    void set(string name, Value value)
    {
        foreach (index, field; names)
        {
            if (field == name)
            {
                values[index] = value;
                return;
            }
        }
        names ~= name;
        values ~= value;
    }

    /// A string field, or its first element.
    string text(string name) const
    {
        return get(name).first;
    }

    /// A boolean field, or `otherwise` when absent.
    bool flag(string name, bool otherwise = false) const
    {
        const value = get(name);
        return value.kind == Value.Kind.boolean ? value.boolean : otherwise;
    }

    /// Deep equality.
    bool same(const ref Annotation other) const
    {
        if (type != other.type || names.length != other.names.length)
            return false;
        foreach (index, name; names)
        {
            const theirs = other.get(name);
            if (!values[index].same(theirs))
                return false;
        }
        return true;
    }
}

/// A type as the compiler spells it.
struct TypeRef
{
    /// D source spelling, valid with `modules` imported statically.
    string name;
    /// Modules declaring the named parts.
    string[] modules;
    /// "class", "interface", "struct", "enum", or empty for built-in types.
    string kind;
    /// Element type of an array: zero or one entries.
    TypeRef[] element;
    /// Template of a template instance, or empty.
    string template_;
    /// Template arguments.
    TypeRef[] arguments;
    /// For a method's return type: the fully qualified names of its base classes and interfaces, so a bean whose
    /// type is declared in a module the extraction did not describe still has its supertypes.
    string[] supertypes;
    /// For a template instance: the runtime's canonical name (`typeNameOf`), when the extraction had the runtime.
    string canonical;
}

/// A function parameter.
struct Parameter
{
    /// Identifier.
    string name;
    /// Type.
    TypeRef type;
    /// Declared UDAs.
    Annotation[] annotations;
    /// Storage classes: "ref", "out", "lazy", "scope", "return".
    string[] storage;
}

/// A method or constructor (`__ctor`).
struct Method
{
    /// Identifier.
    string name;
    /// Source file and line.
    string file;
    /// ditto
    long line;
    /// "public", "protected", "package", "private" or "export".
    string visibility;
    /// Attributes.
    bool static_;
    /// ditto
    bool final_;
    /// ditto
    bool abstract_;
    /// ditto
    bool override_;
    /// Declared in a supertype, not in the type that lists it.
    bool inherited;
    /// Declared UDAs.
    Annotation[] annotations;
    /// Return type.
    TypeRef returns;
    /// Parameters.
    Parameter[] parameters;
    /// Function attributes: "@safe", "nothrow", "const", "ref", ...
    string[] attributes;

    /// Whether `attribute` is among the function attributes.
    bool has(string attribute) const
    {
        foreach (item; attributes)
        {
            if (item == attribute)
                return true;
        }
        return false;
    }
}

/// An instance field.
struct Field
{
    /// Identifier.
    string name;
    /// Position in the declaring type's `tupleof`.
    long index;
    /// Type.
    TypeRef type;
    /// Visibility.
    string visibility;
    /// Declared UDAs.
    Annotation[] annotations;
}

/// A class, interface, struct or enum declared in an extracted module.
struct TypeDecl
{
    /// Identifier.
    string name;
    /// Fully qualified name.
    string fqn;
    /// "class", "interface", "struct" or "enum".
    string kind;
    /// Source file and line.
    string file;
    /// ditto
    long line;
    /// Visibility.
    string visibility;
    /// Declared UDAs.
    Annotation[] annotations;
    /// For classes.
    bool abstract_;
    /// ditto
    bool final_;
    /// Base classes and interfaces, transitively, nearest first.
    TypeRef[] supertypes;
    /// Instance fields.
    Field[] fields;
    /// Methods and constructors declared here.
    Method[] methods;
    /// Enum constants.
    string[] constants;
    /// The declaring module.
    string module_;

    /// Whether `type` is this type or one of its supertypes.
    bool isA(string type) const
    {
        if (fqn == type)
            return true;
        foreach (ref supertype; supertypes)
        {
            if (supertype.name == type || supertype.template_ == type)
                return true;
        }
        return false;
    }

    /// The constructors.
    const(Method)[] constructors() const
    {
        const(Method)[] result;
        foreach (ref method; methods)
        {
            if (method.name == "__ctor")
                result ~= method;
        }
        return result;
    }
}

/// An annotation attribute field, with its default.
struct AnnotationField
{
    /// Identifier.
    string name;
    /// Type.
    TypeRef type;
    /// `T.init`'s value.
    Value default_;
    /// UDAs on the field (`@AliasFor`).
    Annotation[] annotations;
}

/// The declaration of an annotation type.
struct AnnotationType
{
    /// Fully qualified name.
    string name;
    /// Modules a rendering must import.
    string[] modules;
    /// Meta-annotations: the UDAs on the struct.
    Annotation[] meta;
    /// Attribute fields.
    AnnotationField[] fields;

    /// A field by name, or null.
    const(AnnotationField)* field(string name) const return
    {
        foreach (ref item; fields)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }
}

/// One extracted module.
struct ModuleModel
{
    /// Module name.
    string name;
    /// Types declared at module level and nested in them.
    TypeDecl[] types;
    /// Annotation types the module's UDAs reach.
    AnnotationType[] annotationTypes;
    /// The module declares `Descriptor[] flintAotDescriptors()`: it describes its own data types.
    bool exportsDescriptors;
}

/// Every extracted module, with the annotation types and class-presence answers they share.
final class Model
{
    /// Modules, in the order given.
    ModuleModel[] modules;
    /// Annotation types by name.
    AnnotationType[string] annotationTypes;
    /// Class-presence answers by fully qualified class name.
    bool[string] present;

    /// Add a module and its annotation types.
    void add(ModuleModel item)
    {
        foreach (ref type; item.annotationTypes)
        {
            if (type.name !in annotationTypes)
                annotationTypes[type.name] = type;
        }
        modules ~= item;
    }

    /// A type by fully qualified name, or null.
    const(TypeDecl)* type(string fqn) const
    {
        foreach (ref item; modules)
        {
            foreach (ref decl; item.types)
            {
                if (decl.fqn == fqn)
                    return &decl;
            }
        }
        return null;
    }

    /// A module by name, or null.
    const(ModuleModel)* module_(string name) const
    {
        foreach (ref item; modules)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }
}

/// Read one module document. False with `error` set when it is not a `flint.aot.model/1` document.
bool parseModule(string text, out ModuleModel result, out string error)
{
    import std.json : JSONException, JSONType, parseJSON;

    JSONValue root;
    try
        root = parseJSON(text);
    catch (JSONException exception)
    {
        error = exception.msg;
        return false;
    }
    if (root.type != JSONType.object || str(root, "schema") != "flint.aot.model/1")
    {
        error = "not a flint.aot.model/1 document";
        return false;
    }
    result.name = str(root, "module");
    result.exportsDescriptors = flag(root, "exportsDescriptors");
    foreach (ref item; list(root, "types"))
    {
        auto decl = readType(item);
        decl.module_ = result.name;
        result.types ~= decl;
    }
    foreach (ref item; list(root, "annotationTypes"))
        result.annotationTypes ~= readAnnotationType(item);
    return true;
}

/// Read one annotation type's JSON, as the describer prints it.
bool parseAnnotationType(string text, out AnnotationType result, out string error)
{
    import std.json : JSONException, JSONType, parseJSON;

    JSONValue root;
    try
        root = parseJSON(text);
    catch (JSONException exception)
    {
        error = exception.msg;
        return false;
    }
    if (root.type != JSONType.object || str(root, "name").length == 0)
    {
        error = "not an annotation type";
        return false;
    }
    result = readAnnotationType(root);
    return true;
}

private JSONValue member(const ref JSONValue value, string name)
{
    import std.json : JSONType;

    if (value.type != JSONType.object)
        return JSONValue.init;
    if (auto found = name in value.objectNoRef)
        return *found;
    return JSONValue.init;
}

private string str(const ref JSONValue value, string name)
{
    import std.json : JSONType;

    const found = member(value, name);
    return found.type == JSONType.string ? found.str : null;
}

private long integer(const ref JSONValue value, string name)
{
    import std.json : JSONType;

    const found = member(value, name);
    return found.type == JSONType.integer ? found.integer : 0;
}

private bool flag(const ref JSONValue value, string name)
{
    import std.json : JSONType;

    return member(value, name).type == JSONType.true_;
}

private JSONValue[] list(const ref JSONValue value, string name)
{
    return items(member(value, name));
}

private JSONValue[] items(const JSONValue value)
{
    import std.json : JSONType;

    return value.type == JSONType.array ? value.arrayNoRef.dup : null;
}

private string[] strings(const ref JSONValue value, string name)
{
    import std.json : JSONType;

    string[] result;
    foreach (ref item; list(value, name))
    {
        if (item.type == JSONType.string)
            result ~= item.str;
    }
    return result;
}

private TypeRef readTypeRef(const JSONValue value)
{
    TypeRef result;
    result.name = str(value, "name");
    result.modules = strings(value, "modules");
    result.kind = str(value, "kind");
    result.template_ = str(value, "template");
    result.canonical = str(value, "canonical");
    const element = member(value, "element");
    if (str(element, "name").length)
        result.element = [readTypeRef(element)];
    foreach (ref item; list(value, "arguments"))
        result.arguments ~= readTypeRef(item);
    return result;
}

private Value readValue(const JSONValue value)
{
    import std.json : JSONType;

    Value result;
    switch (value.type)
    {
    case JSONType.true_, JSONType.false_:
        result.kind = Value.Kind.boolean;
        result.boolean = value.type == JSONType.true_;
        break;
    case JSONType.integer:
        result.kind = Value.Kind.integer;
        result.integer = value.integer;
        break;
    case JSONType.uinteger:
        result.kind = Value.Kind.integer;
        result.integer = cast(long) value.uinteger;
        break;
    case JSONType.string:
        result.kind = Value.Kind.text;
        result.text = value.str;
        break;
    case JSONType.array:
        result.kind = Value.Kind.array;
        foreach (ref item; items(value))
            result.items ~= readValue(item);
        break;
    case JSONType.object:
        readObjectValue(value, result);
        break;
    default:
        break;
    }
    return result;
}

private void readObjectValue(const JSONValue value, ref Value result)
{
    import std.conv : to;

    if (str(value, "enum").length)
    {
        result.kind = Value.Kind.enumMember;
        result.enumType = str(value, "enum");
        result.text = str(value, "name");
        result.modules = strings(value, "modules");
    }
    else if (str(value, "type").length)
    {
        result.kind = Value.Kind.annotation;
        result.nested = [readAnnotation(value)];
        result.modules = result.nested[0].modules;
    }
    else if (str(value, "float").length)
    {
        result.kind = Value.Kind.raw;
        result.text = str(value, "float");
    }
    else
    {
        result.kind = Value.Kind.raw;
        result.text = "cast(dchar) " ~ integer(value, "char").to!string;
    }
}

private Annotation readAnnotation(const JSONValue value)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONType;

    Annotation result;
    result.type = str(value, "type");
    result.modules = strings(value, "modules");
    const values = member(value, "values");
    if (values.type != JSONType.object)
        return result;
    // The describer writes fields in declaration order, but JSON objects are unordered once parsed; the order
    // only matters for display, so keep the fields sorted for stable output.
    auto names = values.objectNoRef.keys;
    sort(names);
    foreach (name; names)
        result.set(name, readValue(values.objectNoRef[name]));
    return result;
}

private Annotation[] readAnnotations(const ref JSONValue value, string name)
{
    Annotation[] result;
    foreach (ref item; list(value, name))
    {
        if (str(item, "type").length)
            result ~= readAnnotation(item);
    }
    return result;
}

private Method readMethod(const JSONValue value)
{
    Method result;
    result.name = str(value, "name");
    result.file = str(value, "file");
    result.line = integer(value, "line");
    result.visibility = str(value, "visibility");
    result.static_ = flag(value, "static");
    result.final_ = flag(value, "final");
    result.abstract_ = flag(value, "abstract");
    result.override_ = flag(value, "override");
    result.inherited = flag(value, "inherited");
    result.annotations = readAnnotations(value, "annotations");
    result.returns = readTypeRef(member(value, "returns"));
    result.returns.supertypes = strings(value, "returnSupertypes");
    foreach (ref item; list(value, "parameters"))
        result.parameters ~= Parameter(str(item, "name"), readTypeRef(member(item, "type")),
                readAnnotations(item, "annotations"), strings(item, "storage"));
    result.attributes = strings(value, "attributes");
    return result;
}

private TypeDecl readType(const JSONValue value)
{
    TypeDecl result;
    result.name = str(value, "name");
    result.fqn = str(value, "fqn");
    result.kind = str(value, "kind");
    result.file = str(value, "file");
    result.line = integer(value, "line");
    result.visibility = str(value, "visibility");
    result.annotations = readAnnotations(value, "annotations");
    result.abstract_ = flag(value, "abstract");
    result.final_ = flag(value, "final");
    foreach (ref item; list(value, "supertypes"))
        result.supertypes ~= readTypeRef(item);
    foreach (ref item; list(value, "fields"))
        result.fields ~= Field(str(item, "name"), integer(item, "index"), readTypeRef(member(item,
                "type")), str(item, "visibility"), readAnnotations(item, "annotations"));
    foreach (ref item; list(value, "methods"))
        result.methods ~= readMethod(item);
    result.constants = strings(value, "constants");
    return result;
}

private AnnotationType readAnnotationType(const JSONValue value)
{
    AnnotationType result;
    result.name = str(value, "name");
    result.modules = strings(value, "modules");
    result.meta = readAnnotations(value, "meta");
    foreach (ref item; list(value, "fields"))
        result.fields ~= AnnotationField(str(item, "name"), readTypeRef(member(item, "type")),
                readValue(member(item, "default")), readAnnotations(item, "annotations"));
    return result;
}

/// A deep copy of an annotation.
Annotation clone(const ref Annotation annotation)
{
    Annotation result;
    result.type = annotation.type;
    result.modules = annotation.modules.dup;
    result.names = annotation.names.dup;
    foreach (ref value; annotation.values)
        result.values ~= clone(value);
    return result;
}

/// A deep copy of a value.
Value clone(const ref Value value)
{
    Value result;
    result.kind = value.kind;
    result.boolean = value.boolean;
    result.integer = value.integer;
    result.text = value.text;
    result.enumType = value.enumType;
    result.modules = value.modules.dup;
    foreach (ref item; value.items)
        result.items ~= clone(item);
    foreach (ref item; value.nested)
        result.nested ~= clone(item);
    return result;
}

/// A deep copy of a type reference.
TypeRef clone(const ref TypeRef type)
{
    TypeRef result;
    result.name = type.name;
    result.modules = type.modules.dup;
    result.kind = type.kind;
    result.template_ = type.template_;
    result.canonical = type.canonical;
    result.supertypes = type.supertypes.dup;
    foreach (ref item; type.element)
        result.element ~= clone(item);
    foreach (ref item; type.arguments)
        result.arguments ~= clone(item);
    return result;
}

/// A deep copy of a parameter.
Parameter clone(const ref Parameter parameter)
{
    Parameter result;
    result.name = parameter.name;
    result.type = clone(parameter.type);
    foreach (ref item; parameter.annotations)
        result.annotations ~= clone(item);
    result.storage = parameter.storage.dup;
    return result;
}

/// A deep copy of a method.
Method clone(const ref Method method)
{
    Method result;
    result.name = method.name;
    result.file = method.file;
    result.line = method.line;
    result.visibility = method.visibility;
    result.static_ = method.static_;
    result.final_ = method.final_;
    result.abstract_ = method.abstract_;
    result.override_ = method.override_;
    result.inherited = method.inherited;
    foreach (ref item; method.annotations)
        result.annotations ~= clone(item);
    result.returns = clone(method.returns);
    foreach (ref item; method.parameters)
        result.parameters ~= clone(item);
    result.attributes = method.attributes.dup;
    return result;
}

/// Deep copies of methods.
Method[] clone(const(Method)[] methods)
{
    Method[] result;
    foreach (ref method; methods)
        result ~= clone(method);
    return result;
}

/// Deep copies of parameters.
Parameter[] clone(const(Parameter)[] parameters)
{
    Parameter[] result;
    foreach (ref parameter; parameters)
        result ~= clone(parameter);
    return result;
}
