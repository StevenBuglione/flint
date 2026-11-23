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
    bool[string] checked;
    // Breadth-first: the nearest declaration of a type wins, and among equals the first declared.
    Pending[] queue;
    foreach (ref annotation; declared)
    {
        if (annotation.type == aliasForType)
            continue;
        auto normal = normalized(annotation, types, result.conflicts);
        queue ~= Pending(Merged(normal, 0), explicitAliases(normal, 0, types));
    }
    size_t next;
    while (next < queue.length)
    {
        auto current = queue[next++];
        if (result.has(current.merged.annotation.type))
            continue;
        result.items ~= current.merged;
        const type = current.merged.annotation.type in types;
        if (type is null || current.merged.distance >= 8)
            continue;
        if (type.name !in checked)
        {
            checked[type.name] = true;
            validate(*type, types, result.conflicts);
        }
        foreach (ref meta; type.meta)
        {
            if (meta.type == aliasForType)
                continue;
            const distance = current.merged.distance + 1;
            auto overridden = overrideMeta(meta, current.overrides, types, result.conflicts);
            auto normal = normalized(overridden, types, result.conflicts);
            queue ~= Pending(Merged(normal, distance), current.overrides ~ explicitAliases(normal, distance, types));
        }
    }
    return result;
}

/// A queued annotation and the explicit aliases of every annotation on its path from the element, which may
/// target any annotation further up its meta-annotations (an alias to a meta-meta-annotation).
private struct Pending
{
    Merged merged;
    Override[] overrides;
}

/// One attribute's explicit `@AliasFor(annotation: ...)`.
private struct Override
{
    /// The targeted annotation type and attribute.
    string type;
    /// ditto
    string attribute;
    /// The aliasing attribute's value, and whether it differs from that attribute's default.
    Value value;
    /// ditto
    bool set;
    /// Distance of the declaring annotation: the nearest declaration wins.
    uint distance;
    /// The aliasing annotation and attribute, for messages.
    string from;
}

/// The explicit aliases an annotation's attributes declare to other annotations' attributes.
private Override[] explicitAliases(const ref Annotation annotation, uint distance, const AnnotationType[string] types)
{
    Override[] result;
    const type = annotation.type in types;
    if (type is null)
        return result;
    foreach (ref field; type.fields)
    {
        const alias_ = aliasFor(*type, field.name);
        if (alias_ is null)
            continue;
        const target = aliasTarget(*alias_, type.name);
        if (target.length == 0)
            continue;
        const value = annotation.get(field.name);
        result ~= Override(target, aliasAttribute(*alias_, field.name), clone(value),
                !value.same(field.default_), distance, shortName(type.name) ~ "." ~ field.name);
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

/// Fill attributes the declaration left at their default from their aliases: intra-annotation aliases, and
/// implicit aliases (attributes aliasing the same meta-annotation attribute).
private Annotation normalized(const ref Annotation annotation, const AnnotationType[string] types, ref string[] errors)
{
    Annotation result = clone(annotation);
    const type = annotation.type in types;
    if (type is null)
        return result;
    foreach (ref field; type.fields)
    {
        const alias_ = aliasFor(*type, field.name);
        if (alias_ is null)
            continue;
        const target = aliasTarget(*alias_, type.name);
        const partner = aliasAttribute(*alias_, field.name);
        if (target.length == 0 && type.field(partner) is null)
        {
            errors ~= "@AliasFor on " ~ type.name ~ "." ~ field.name ~ " names the missing attribute `" ~ partner ~ "`";
            continue;
        }
        foreach (ref other; type.fields)
        {
            if (other.name == field.name || !aliased(*type, other.name, target, partner))
                continue;
            mirror(result, *type, field.name, other.name, target.length != 0, errors);
        }
    }
    foreach (ref value; result.values)
        normalizeNested(value, types, errors);
    return result;
}

/// Resolve the aliases of annotations nested in attribute values (`@ComponentScan(excludeFilters:
/// [Filter(...)])`), as Spring synthesizes nested annotations.
private void normalizeNested(ref Value value, const AnnotationType[string] types, ref string[] errors)
{
    if (value.kind == Value.Kind.annotation && value.nested.length)
        value.nested[0] = normalized(value.nested[0], types, errors);
    else if (value.kind == Value.Kind.array)
    {
        foreach (ref item; value.items)
            normalizeNested(item, types, errors);
    }
}

/// Whether `field` aliases `partner` (an intra-annotation alias when `target` is empty), or, for an explicit
/// alias, the same `target` attribute.
private bool aliased(const ref AnnotationType type, string field, string target, string partner)
{
    if (target.length == 0)
        return field == partner;
    const alias_ = aliasFor(type, field);
    return alias_ !is null && aliasTarget(*alias_, type.name) == target && aliasAttribute(*alias_, field) == partner;
}

/// Make two aliased attributes agree: the one set (not at its default) wins; two different set values conflict.
private void mirror(ref Annotation result, const ref AnnotationType type, string field, string partner,
        bool implicit, ref string[] errors)
{
    auto mine = result.get(field);
    auto theirs = result.get(partner);
    const mineSet = !mine.same(type.field(field).default_);
    const theirsSet = !theirs.same(type.field(partner).default_);
    if (mineSet && theirsSet && !mine.same(theirs) && field < partner)
        errors ~= "@" ~ shortName(type.name) ~ " gives the " ~ (implicit
                ? "implicit " : "") ~ "aliases `" ~ field ~ "` and `" ~ partner ~ "` different values";
    else if (mineSet && !theirsSet)
        result.set(partner, mine);
    else if (theirsSet && !mineSet)
        result.set(field, theirs);
}

/// A meta-annotation with the attributes the annotations below it override through `@AliasFor`. For each
/// attribute the nearest declaring annotation wins, even with its attribute at its default (Spring maps the
/// attribute through the alias either way); among implicit aliases of one annotation, a set value wins.
private Annotation overrideMeta(const ref Annotation meta, const Override[] overrides,
        const AnnotationType[string] types, ref string[] conflicts)
{
    Annotation result = clone(meta);
    const metaType = meta.type in types;
    bool[string] done;
    foreach (ref candidate; overrides)
    {
        if (candidate.type != meta.type || candidate.attribute in done)
            continue;
        done[candidate.attribute] = true;
        const target = metaType is null ? null : metaType.field(candidate.attribute);
        if (metaType !is null && target is null)
        {
            conflicts ~= "@AliasFor on " ~ candidate.from ~ " names the missing attribute `" ~ shortName(
                    meta.type) ~ "." ~ candidate.attribute ~ "`";
            continue;
        }
        Value value = chosen(overrides, candidate);
        if (target !is null && isArray(target.type.name) && value.kind != Value.Kind.array)
            value = arrayOf(value);
        result.set(candidate.attribute, clone(value));
        // A set value replaces its intra-annotation partner too; a default one leaves the pair to `normalized`,
        // where the set member of the mirror pair wins (GetMapping's `value` and `path` both alias RequestMapping).
        if (metaType !is null && !value.same(target.default_))
            setPartner(result, *metaType, candidate.attribute, value);
    }
    if (metaType !is null)
        fillDefaults(result, *metaType);
    return result;
}

/// The value for an overridden attribute: among the nearest annotation's aliases of it, a set one, else the first.
private Value chosen(const Override[] overrides, const ref Override first)
{
    uint nearest = first.distance;
    foreach (ref item; overrides)
    {
        if (item.type == first.type && item.attribute == first.attribute && item.distance < nearest)
            nearest = item.distance;
    }
    const(Override)* pick;
    foreach (ref item; overrides)
    {
        if (item.type != first.type || item.attribute != first.attribute || item.distance != nearest)
            continue;
        if (pick is null || (item.set && !pick.set))
            pick = &item;
    }
    return clone(pick.value);
}

private bool isArray(string typeName)
{
    return typeName.length > 2 && typeName[$ - 2 .. $] == "[]";
}

/// A single value as a one-element array (`string pkg` aliasing `string[] basePackages`); empty stays empty.
private Value arrayOf(const ref Value single)
{
    Value result;
    result.kind = Value.Kind.array;
    if (!single.isEmpty || single.kind == Value.Kind.boolean || single.kind == Value.Kind.integer)
        result.items = [clone(single)];
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

/// Spring's `AnnotationTypeMapping` checks, which throw `AnnotationConfigurationException` there and are
/// FLINT-E1103 here: an intra-annotation alias is declared on both attributes, aliases have the same type and
/// default, and an explicit alias targets an attribute of a meta-annotation of the declaring annotation.
private void validate(const ref AnnotationType type, const AnnotationType[string] types, ref string[] conflicts)
{
    foreach (ref field; type.fields)
    {
        const alias_ = aliasFor(type, field.name);
        if (alias_ is null)
            continue;
        const target = aliasTarget(*alias_, type.name);
        const attribute = aliasAttribute(*alias_, field.name);
        const where = "@AliasFor on " ~ type.name ~ "." ~ field.name;
        if (target.length == 0)
        {
            const partner = type.field(attribute);
            if (partner is null)
                continue; // reported by normalized
            const back = aliasFor(type, attribute);
            if (attribute == field.name)
                conflicts ~= where ~ " points at itself";
            else if (back is null || aliasTarget(*back, type.name).length || aliasAttribute(*back,
                    attribute) != field.name)
                conflicts ~= where ~ ": `" ~ attribute ~ "` must be declared as an @AliasFor `" ~ field.name ~ "`";
            else if (partner.type.name != field.type.name)
                conflicts ~= where ~ ": `" ~ field.name ~ "` and `" ~ attribute ~ "` must have the same type";
            else if (!partner.default_.same(field.default_))
                conflicts ~= where ~ ": `" ~ field.name ~ "` and `" ~ attribute ~ "` must have the same default";
            continue;
        }
        if (!metaPresent(type, target, types))
        {
            conflicts ~= where ~ " targets " ~ target ~ ", which is not a meta-annotation of " ~ type.name;
            continue;
        }
        const targetType = target in types;
        const targetField = targetType is null ? null : targetType.field(attribute);
        if (targetField !is null && targetField.type.name != field.type.name
                && targetField.type.name != field.type.name ~ "[]")
            conflicts ~= where ~ ": its type " ~ field.type.name ~ " does not match " ~ shortName(
                    target) ~ "." ~ attribute ~ "'s " ~ targetField.type.name;
    }
}

/// Whether `target` is a meta-annotation of `type`, at any depth.
private bool metaPresent(const ref AnnotationType type, string target, const AnnotationType[string] types)
{
    string[] pending = [type.name];
    bool[string] seen;
    while (pending.length)
    {
        const name = pending[$ - 1];
        pending = pending[0 .. $ - 1];
        if (name in seen)
            continue;
        seen[name] = true;
        const current = name in types;
        if (current is null)
            continue;
        foreach (ref meta; current.meta)
        {
            if (meta.type == target)
                return true;
            pending ~= meta.type;
        }
    }
    return false;
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
