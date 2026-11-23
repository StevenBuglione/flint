/// `flint api diff`: the API elements added, removed or changed between two manifests (ADR-030, API manifests).
///
/// Elements are keyed by id, so moving a member within a file is no change. A type changes when its kind,
/// visibility, modifiers, annotations, type parameters or supertypes change, or when it moves to another module; a
/// member changes when anything recorded about it except its parameter names changes.
module flint_tool.api.diff;

import flint_tool.api.manifest : Manifest;

@safe:

/// What happened to an element.
enum Change : string
{
    added = "added",
    removed = "removed",
    changed = "changed"
}

/// One difference.
struct Difference
{
    /// What happened.
    Change change;
    /// Element kind: a type kind or a member kind.
    string kind;
    /// Element id.
    string id;
    /// For a change: which properties differ, `property: old -> new`.
    string[] details;
}

/// Compare two manifests; differences sorted by id, then change.
Difference[] diffManifests(const ref Manifest older, const ref Manifest newer)
{
    import std.algorithm.sorting : sort;

    Element[string] before = elements(older);
    Element[string] after = elements(newer);
    Difference[] differences;
    foreach (id, ref element; before)
    {
        if (auto other = id in after)
        {
            auto details = compare(element, *other);
            if (details.length)
                differences ~= Difference(Change.changed, other.kind, id, details);
        }
        else
            differences ~= Difference(Change.removed, element.kind, id);
    }
    foreach (id, ref element; after)
    {
        if ((id in before) is null)
            differences ~= Difference(Change.added, element.kind, id);
    }
    sort!((a, b) => a.id < b.id || (a.id == b.id && a.change < b.change))(differences);
    return differences;
}

/// The flattened, comparable properties of one element.
private struct Element
{
    string kind;
    string[2][] properties;
}

private Element[string] elements(const ref Manifest manifest)
{
    import std.array : join;
    import flint_tool.api.java : erasedParameterType;
    import flint_tool.api.manifest : memberId;

    Element[string] table;
    foreach (ref type; manifest.types)
    {
        const decl = &type.decl;
        table[decl.id] = Element(cast(string) decl.kind, [
            ["module", type.module_], ["visibility", decl.visibility],
            ["modifiers", decl.modifiers.join(" ")], ["annotations", decl.annotations.join(" ")],
            ["typeParameters", decl.typeParameters.join(", ")], [
                "extends", decl.extends_.join(", ")
            ], ["implements", decl.implements_.join(", ")], ["permits", decl.permits.join(", ")]
        ]);
        foreach (ref member; decl.members)
        {
            // Parameter names are not API; their types and annotations are.
            string[] parameterTypes;
            foreach (parameter; member.parameters)
                parameterTypes ~= parameterType(parameter);
            table[memberId(*decl, member)] = Element(cast(string) member.kind, [
                ["visibility", member.visibility], ["modifiers", member.modifiers.join(" ")],
                ["annotations", member.annotations.join(" ")],
                ["typeParameters", member.typeParameters.join(", ")], ["type", member.type],
                ["parameters", parameterTypes.join(", ")], ["throws", member.throws_.join(", ")],
                ["default", member.defaultValue]
            ]);
        }
    }
    return table;
}

/// A rendered parameter without its name: `@Nullable Object... args` → `@Nullable Object...`.
string parameterType(string parameter)
{
    size_t end = parameter.length;
    while (end > 0 && parameter[end - 1] != ' ')
        end--;
    return end ? parameter[0 .. end - 1] : parameter;
}

private string[] compare(const ref Element older, const ref Element newer)
{
    string[] details;
    if (older.kind != newer.kind)
        details ~= "kind: " ~ older.kind ~ " -> " ~ newer.kind;
    foreach (index, property; older.properties)
    {
        const other = newer.properties[index];
        if (property[1] != other[1])
            details ~= property[0] ~ ": " ~ shown(property[1]) ~ " -> " ~ shown(other[1]);
    }
    return details;
}

private string shown(string value)
{
    return value.length ? value : "(none)";
}
