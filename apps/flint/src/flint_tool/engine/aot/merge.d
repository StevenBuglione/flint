/// Merged annotations: meta-annotations and `@AliasFor`, composed at build time the way Spring's
/// `MergedAnnotations` composes them at runtime (docs/spring/aot-contract.md section 2.1).
module flint_tool.engine.aot.merge;

import flint_tool.engine.aot.model : Annotation, AnnotationType, Value, clone;

@safe:

/// The name of `@AliasFor`.
enum aliasForType = "flint.core.annotation.AliasFor";

/// One merged annotation: every attribute filled, aliases applied.
struct Merged
{
    /// The annotation, with all of its attributes.
    Annotation annotation;
    /// 0 when declared on the element, else the meta-annotation depth.
    uint distance;

    /// The annotation's type.
    string type() const
    {
        return annotation.type;
    }
}

/// The merged annotations of one element.
struct MergedSet
{
    /// Nearest first; one entry per type.
    Merged[] items;
    /// Alias conflicts, as messages for FLINT-E1103.
    string[] conflicts;

    /// The merged annotation of `type`, or null.
    const(Annotation)* get(string type) const return
    {
        foreach (ref item; items)
        {
            if (item.annotation.type == type)
                return &item.annotation;
        }
        return null;
    }

    /// Whether `type` is present, declared or as a meta-annotation.
    bool has(string type) const
    {
        return get(type) !is null;
    }

    /// Whether any of `types` is present.
    bool hasAny(const string[] types) const
    {
        foreach (type; types)
        {
            if (has(type))
                return true;
        }
        return false;
    }
}

/// Merge the annotations declared on one element.
MergedSet merge(const Annotation[] declared, const AnnotationType[string] types)
{
    MergedSet result;
    // Breadth-first: the nearest declaration of a type wins, and among equals the first declared.
    Merged[] queue;
    foreach (ref annotation; declared)
    {
        if (annotation.type == aliasForType)
            continue;
        queue ~= Merged(normalized(annotation, types, result.conflicts), 0);
    }
    size_t next;
    while (next < queue.length)
    {
        auto current = queue[next++];
        if (result.has(current.annotation.type))
            continue;
        result.items ~= current;
        const type = current.annotation.type in types;
        if (type is null || current.distance >= 8)
            continue;
        foreach (ref meta; type.meta)
        {
            if (meta.type == aliasForType)
                continue;
            auto overridden = overrideMeta(meta, current.annotation, *type, types, result.conflicts);
            queue ~= Merged(normalized(overridden, types, result.conflicts), current.distance + 1);
        }
    }
    return result;
}

/// The `@AliasFor` on an attribute field, if any.
private const(Annotation)* aliasFor(return ref const AnnotationType type, string field)
{
    const found = type.field(field);
    if (found is null)
        return null;
    foreach (ref annotation; found.annotations)
    {
        if (annotation.type == aliasForType)
            return &annotation;
    }
    return null;
}

/// The attribute an `@AliasFor` names: `attribute` or `value`, else the field's own name.
private string aliasAttribute(const ref Annotation alias_, string field)
{
    const attribute = alias_.text("attribute");
    if (attribute.length)
        return attribute;
    const value = alias_.text("value");
    return value.length ? value : field;
}

/// The annotation an `@AliasFor` targets, or empty for the declaring annotation itself.
private string aliasTarget(const ref Annotation alias_, string self)
{
    const target = alias_.get("annotation");
    if (target.kind == Value.Kind.annotation)
    {
        const name = target.nested[0].text("name");
        return name == self ? null : name;
    }
    return null;
}

/// Fill attributes the declaration left at their default from their intra-annotation alias.
private Annotation normalized(const ref Annotation annotation, const AnnotationType[string] types, ref string[] errors)
{
    Annotation result = clone(annotation);
    const type = annotation.type in types;
    if (type is null)
        return result;
    foreach (ref field; type.fields)
    {
        const alias_ = aliasFor(*type, field.name);
        if (alias_ is null || aliasTarget(*alias_, type.name).length)
            continue;
        const partner = aliasAttribute(*alias_, field.name);
        if (type.field(partner) is null)
        {
            errors ~= "@AliasFor on " ~ type.name ~ "." ~ field.name ~ " names the missing attribute `" ~ partner ~ "`";
            continue;
        }
        auto mine = result.get(field.name);
        auto theirs = result.get(partner);
        const mineSet = !mine.same(field.default_);
        const theirsSet = !theirs.same(type.field(partner).default_);
        if (mineSet && theirsSet && !mine.same(theirs) && field.name < partner)
            errors ~= "@" ~ shortName(
                    type.name) ~ " gives the aliases `" ~ field.name ~ "` and `" ~ partner ~ "` different values";
        else if (mineSet && !theirsSet)
            result.set(partner, mine);
        else if (theirsSet && !mineSet)
            result.set(field.name, theirs);
    }
    return result;
}

/// A meta-annotation with the attributes its declaring annotation overrides through `@AliasFor`.
private Annotation overrideMeta(const ref Annotation meta, const ref Annotation declaring,
        const ref AnnotationType declaringType, const AnnotationType[string] types, ref string[] conflicts)
{
    Annotation result = clone(meta);
    string[] setBy;
    string[] setFrom;
    foreach (ref field; declaringType.fields)
    {
        const alias_ = aliasFor(declaringType, field.name);
        if (alias_ is null || aliasTarget(*alias_, declaringType.name) != meta.type)
            continue;
        const value = declaring.get(field.name);
        if (value.same(field.default_))
            continue;
        const attribute = aliasAttribute(*alias_, field.name);
        const metaType = meta.type in types;
        if (metaType !is null && metaType.field(attribute) is null)
        {
            conflicts ~= "@AliasFor on " ~ declaringType.name ~ "." ~ field.name
                ~ " names the missing attribute `" ~ shortName(meta.type) ~ "." ~ attribute ~ "`";
            continue;
        }
        // Two attributes of one annotation aliasing the same meta-attribute are implicit aliases of each other.
        foreach (index, previous; setBy)
        {
            if (previous == attribute && !declaring.get(setFrom[index]).same(value))
                conflicts ~= "@" ~ shortName(declaringType.name) ~ " gives the implicit aliases `"
                    ~ setFrom[index] ~ "` and `" ~ field.name ~ "` different values";
        }
        setBy ~= attribute;
        setFrom ~= field.name;
        result.set(attribute, clone(value));
        // The overridden attribute's own intra-annotation alias follows it.
        if (metaType !is null)
            setPartner(result, *metaType, attribute, value);
    }
    if (const metaType = meta.type in types)
        fillDefaults(result, *metaType);
    return result;
}

/// Set the intra-annotation alias partner of `attribute`, if it has one.
private void setPartner(ref Annotation result, const ref AnnotationType type, string attribute, const ref Value value)
{
    const partnerAlias = aliasFor(type, attribute);
    if (partnerAlias !is null && aliasTarget(*partnerAlias, type.name).length == 0)
        result.set(aliasAttribute(*partnerAlias, attribute), clone(value));
}

/// Attributes the meta-annotation declaration leaves out take their defaults.
private void fillDefaults(ref Annotation result, const ref AnnotationType type)
{
    foreach (ref field; type.fields)
    {
        bool known;
        foreach (name; result.names)
            known = known || name == field.name;
        if (!known)
            result.set(field.name, clone(field.default_));
    }
}

/// A deep copy of a merged set.
MergedSet clone(const MergedSet merged)
{
    import flint_tool.engine.aot.model : cloneAnnotation = clone;

    MergedSet result;
    foreach (ref item; merged.items)
        result.items ~= Merged(cloneAnnotation(item.annotation), item.distance);
    result.conflicts = merged.conflicts.dup;
    return result;
}

/// The last segment of a qualified name.
string shortName(string name)
{
    import std.string : lastIndexOf;

    const dot = name.lastIndexOf('.');
    return dot < 0 ? name : name[dot + 1 .. $];
}
