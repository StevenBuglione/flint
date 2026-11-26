/// Plans direct field-based Jakarta Persistence mappings from the extracted model.
module flint_tool.engine.aot.jpa;

import flint_tool.engine.aot.merge : MergedSet, merge;
import flint_tool.engine.aot.model : Annotation, Field, Method, Model, TypeDecl, Value;
import std.algorithm.searching : any, canFind, startsWith;
import flint_tool.engine.aot.names : jpaAnnotations, jpaColumn, jpaEntity, jpaEntityListeners,
    jpaId, jpaMappedSuperclass, jpaPostLoad, jpaTable, jpaTransient;

@safe:

/// Supported persistent value types in the first generated mapping slice.
enum JpaFieldKind
{
    integer,
    text,
    date,
}

/// A field in the generated accessor and attribute tables.
struct JpaField
{
    /// D member and SQL column names.
    string name, column;
    /// The transfer representation.
    JpaFieldKind kind;
    /// Column and write flags.
    bool nullable, insertable, updatable;
    /// Declared character length.
    uint length;
}

/// A PostLoad call, with an optional stateless listener to invoke it on.
struct JpaCallback
{
    /// Callback method name.
    string method;
    /// Listener type and its declaring module, or empty for entity methods.
    string listener, module_;
    /// The declared listener parameter type.
    string parameterType;
    /// Modules needed to name that parameter in the generated call.
    string[] parameterModules;
}

/// An entity's full mapping in inherited-first attribute order.
struct JpaMapping
{
    /// D type, JPQL name and primary table name.
    string type, name, table;
    /// Persistent attributes.
    JpaField[] fields;
    /// Simple identifier ordinal.
    uint id;
    /// PostLoad callbacks in invocation order.
    JpaCallback[] postLoad;
}

private alias Report = void delegate(string code, string message, string file, long line) @safe;

/// Checks the narrow generated JPA contract and builds the ordered field and callback plan.
JpaMapping analyzeJpa(const Model model, const ref TypeDecl decl, const ref MergedSet merged, scope Report report)
{
    JpaMapping result;
    result.type = decl.fqn;
    result.name = merged.get(jpaEntity).text("name");
    if (!result.name.length)
        result.name = decl.name;
    result.table = result.name;
    if (const table = merged.get(jpaTable))
    {
        if (table.text("name").length)
            result.table = table.text("name");
        if (table.text("catalog").length || table.text("schema").length)
            report("FLINT-E1142", "qualified Jakarta tables are not supported", decl.file, decl.line);
    }
    if (!constructible(decl))
        report("FLINT-E1140", "Jakarta entity " ~ decl.fqn ~ " needs an accessible no-argument constructor",
                decl.file, decl.line);

    const(TypeDecl)*[] hierarchy;
    foreach_reverse (ref supertype; decl.supertypes)
    {
        if (const base = model.type(supertype.name))
        {
            const annotations = merge(base.annotations, model.annotationTypes);
            if (annotations.has(jpaMappedSuperclass))
                hierarchy ~= base;
            else if (annotations.has(jpaEntity))
                report("FLINT-E1142", "Jakarta entity inheritance requires an inheritance mapping",
                        decl.file, decl.line);
        }
    }
    size_t ids;
    foreach (owner; hierarchy)
        addJpaOwner(result, ids, model, *owner, decl.fqn, report);
    addJpaOwner(result, ids, model, decl, decl.fqn, report);
    if (ids != 1)
        report("FLINT-E1142", "Jakarta entity " ~ decl.fqn ~ " needs exactly one @Id field", decl.file, decl.line);
    foreach (owner; hierarchy)
        addJpaEntityCallback(result, model, *owner, decl, report);
    addJpaEntityCallback(result, model, decl, decl, report);
    return result;
}

private void addJpaOwner(ref JpaMapping mapping, ref size_t ids, const Model model,
        const ref TypeDecl owner, string entityType, scope Report report)
{
    rejectUnsupported(owner.annotations, [
        jpaEntity, jpaTable, jpaMappedSuperclass, jpaEntityListeners
    ], owner, report);
    addJpaFields(mapping, ids, model, owner, report);
    addJpaListeners(mapping, model, owner, entityType, report);
}

private bool accessible(string visibility) pure nothrow @nogc
{
    return visibility == "public" || visibility == "export";
}

private bool constructible(const ref TypeDecl type)
{
    if (type.kind != "class" || type.abstract_ || !accessible(type.visibility))
        return false;
    const constructors = type.constructors();
    if (!constructors.length)
        return true;
    foreach (ref constructor; constructors)
        if (accessible(constructor.visibility) && constructor.parameters.length == 0)
            return true;
    return false;
}

private void rejectUnsupported(scope const(Annotation)[] annotations, scope const(string)[] supported,
        const ref TypeDecl owner, scope Report report)
{
    foreach (ref annotation; annotations)
        if (annotation.type.startsWith(jpaAnnotations) && !supported.canFind(annotation.type))
            report("FLINT-E1142", "unsupported Jakarta mapping annotation " ~ annotation.type ~ " on " ~ owner.fqn,
                    owner.file, owner.line);
}

private void addJpaFields(ref JpaMapping mapping, ref size_t ids, const Model model,
        const ref TypeDecl owner, scope Report report)
{
    foreach (ref field; owner.fields)
    {
        const annotations = merge(field.annotations, model.annotationTypes);
        if (annotations.has(jpaTransient))
            continue;
        rejectUnsupported(field.annotations, [jpaColumn, jpaId], owner, report);
        auto attribute = jpaField(field, annotations, owner, report);
        foreach (ref prior; mapping.fields)
            if (prior.name == attribute.name || prior.column == attribute.column)
                report("FLINT-E1141", "duplicate Jakarta field or column " ~ owner.fqn ~ "." ~ field.name,
                        owner.file, owner.line);
        if (annotations.has(jpaId))
        {
            ++ids;
            mapping.id = cast(uint) mapping.fields.length;
        }
        mapping.fields ~= attribute;
    }
}

private JpaField jpaField(const ref Field field, const ref MergedSet annotations,
        const ref TypeDecl owner, scope Report report)
{
    JpaField result;
    result.name = field.name;
    result.column = field.name;
    result.nullable = result.insertable = result.updatable = true;
    if (!accessible(field.visibility))
        report("FLINT-E1141", "Jakarta field " ~ owner.fqn ~ "." ~ field.name ~ " is inaccessible to AOT",
                owner.file, owner.line);
    switch (field.type.name)
    {
    case "long":
        result.kind = JpaFieldKind.integer;
        break;
    case "string":
        result.kind = JpaFieldKind.text;
        result.length = 255;
        break;
    case "flint.java.time.LocalDate":
        result.kind = JpaFieldKind.date;
        break;
    default:
        const location = owner.fqn ~ "." ~ field.name;
        report("FLINT-E1141", "unsupported Jakarta field type " ~ field.type.name ~ " for " ~ location,
                owner.file, owner.line);
    }
    if (const column = annotations.get(jpaColumn))
    {
        if (column.text("name").length)
            result.column = column.text("name");
        result.nullable = column.flag("nullable", true);
        result.insertable = column.flag("insertable", true);
        result.updatable = column.flag("updatable", true);
        if (result.kind == JpaFieldKind.text)
        {
            const length = column.get("length");
            if (length.kind == Value.Kind.integer && length.integer >= 0 && length.integer <= uint.max)
                result.length = cast(uint) length.integer;
        }
        if (column.text("table").length)
            report("FLINT-E1142", "secondary Jakarta columns are not supported", owner.file, owner.line);
    }
    return result;
}

private void addJpaListeners(ref JpaMapping mapping, const Model model, const ref TypeDecl owner,
        string entityType, scope Report report)
{
    const annotations = merge(owner.annotations, model.annotationTypes);
    const listeners = annotations.get(jpaEntityListeners);
    if (listeners is null)
        return;
    foreach (name; listeners.get("value").strings())
    {
        const type = model.type(name);
        if (type is null || !constructible(*type))
        {
            report("FLINT-E1143", "Jakarta listener " ~ name ~ " needs an accessible no-argument constructor",
                    owner.file, owner.line);
            continue;
        }
        if (type.fields.length || type.constructors().length
                || type.supertypes.any!(base => base.name != "object.Object"))
        {
            report("FLINT-E1143", "stateful Jakarta listener " ~ name ~ " is not supported yet", type.file, type.line);
            continue;
        }
        if (const method = postLoadMethod(model, *type, entityType, report))
        {
            const parameter = method.parameters[0].type;
            mapping.postLoad ~= JpaCallback(method.name, type.fqn, type.module_, parameter.name,
                    parameter.modules.dup);
        }
    }
}

private void addJpaEntityCallback(ref JpaMapping mapping, const Model model, const ref TypeDecl owner,
        const ref TypeDecl entity, scope Report report)
{
    if (const method = postLoadMethod(model, owner, null, report))
    {
        if (owner.fqn != entity.fqn && entity.methods.any!(candidate => !candidate.inherited
                && candidate.name == method.name && !candidate.parameters.length))
            report("FLINT-E1143", "overridden Jakarta PostLoad callback " ~ owner.fqn ~ "." ~ method.name,
                    method.file, method.line);
        mapping.postLoad ~= JpaCallback(method.name);
    }
}

private const(Method)* postLoadMethod(const Model model, return ref const TypeDecl owner,
        string entityType, scope Report report)
{
    const(Method)* result;
    foreach (ref method; owner.methods)
    {
        if (method.inherited)
            continue;
        rejectUnsupported(method.annotations, [jpaPostLoad], owner, report);
        if (!merge(method.annotations, model.annotationTypes).has(jpaPostLoad))
            continue;
        if (result !is null || !isPostLoadSignature(method, entityType.length != 0))
        {
            report("FLINT-E1143", "unsupported Jakarta PostLoad callback " ~ owner.fqn ~ "." ~ method.name,
                    method.file, method.line);
            continue;
        }
        if (entityType.length && !acceptsListenerParameter(method, model, entityType))
        {
            report("FLINT-E1143", "Jakarta listener parameter must accept " ~ entityType, method.file, method.line);
            continue;
        }
        result = &method;
    }
    return result;
}

private bool isPostLoadSignature(const ref Method method, bool listener)
{
    const arity = listener ? 1 : 0;
    return accessible(method.visibility) && !method.static_ && !method.abstract_
        && method.returns.name == "void" && method.parameters.length == arity;
}

private bool acceptsListenerParameter(const ref Method method, const Model model, string entityType)
{
    const parameter = method.parameters[0];
    const entity = model.type(entityType);
    return entity !is null && !parameter.storage.canFind("ref")
        && !parameter.storage.canFind("out") && entity.isA(parameter.type.name);
}
