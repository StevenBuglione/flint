/// `flint api checklist`: per-module Markdown checklists of a porting slice, generated from the manifests, with
/// each element's status read from the repo's mapping (ADR-030 section 8).
///
/// A slice file (`flint.api-slice/1`) names the checklists:
///
/// ---
/// {"schema": "flint.api-slice/1", "title": "Phase 1",
///  "checklists": [
///    {"name": "spring-core", "upstream": "spring-framework@v7.1.0", "module": "spring-core",
///     "packages": ["org.springframework.core", "org.springframework.core.convert.**"]},
///    {"name": "spring-beans", "upstream": "spring-framework@v7.1.0", "module": "spring-beans"}]}
/// ---
///
/// `packages` narrows a module to packages matching the patterns (`*` within a name, `**` across names); without
/// it the whole module is listed. The checklists are views: elements are classified in the mapping, never by
/// editing the Markdown, and regenerating shows the progress.
module flint_tool.api.checklist;

import flint_tool.api.coverage : Classifier, MappingEntry;
import flint_tool.api.java : Member, MemberKind, TypeDecl, TypeKind;
import flint_tool.api.manifest : ApiType, Manifest;

@safe:

/// Schema of a slice file.
enum sliceSchema = "flint.api-slice/1";

/// One checklist of a slice.
struct SliceEntry
{
    /// File name without `.md`.
    string name;
    /// `project@version` of the manifest.
    string upstream;
    /// Module of the manifest.
    string module_;
    /// Package patterns; empty means the whole module.
    string[] packages;
}

/// A slice.
struct Slice
{
    /// Title, such as `Phase 1`.
    string title;
    /// Checklists, in file order.
    SliceEntry[] checklists;
}

/// Counts of one checklist.
struct ChecklistCounts
{
    /// Types.
    size_t types;
    /// Elements: types and members.
    size_t elements;
    /// Ported.
    size_t ported;
    /// Adapted.
    size_t adapted;
    /// Excluded.
    size_t excluded;

    /// Elements still unclassified.
    size_t open() const
    {
        return elements - ported - adapted - excluded;
    }
}

/// Parse a slice file.
bool parseSlice(string text, out Slice slice, out string error)
{
    import std.json : JSONException, JSONType, parseJSON;

    try
    {
        auto root = parseJSON(text);
        if (root.type != JSONType.object || "schema" !in root || root["schema"].str != sliceSchema)
        {
            error = "not a " ~ sliceSchema ~ " document";
            return false;
        }
        slice.title = "title" in root ? root["title"].str : "Slice";
        foreach (ref item; root["checklists"].arrayNoRef)
        {
            SliceEntry entry;
            entry.name = item["name"].str;
            entry.upstream = item["upstream"].str;
            entry.module_ = item["module"].str;
            if ("packages" in item)
                foreach (ref value; item["packages"].arrayNoRef)
                    entry.packages ~= value.str;
            if (!validName(entry.name))
            {
                error = "checklist name `" ~ entry.name ~ "` must be lower-case letters, digits and hyphens";
                return false;
            }
            slice.checklists ~= entry;
        }
    }
    catch (JSONException failure)
    {
        error = "malformed slice: " ~ failure.msg;
        return false;
    }
    return true;
}

private bool validName(string name)
{
    if (name.length == 0)
        return false;
    foreach (c; name)
    {
        if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '-' && c != '.')
            return false;
    }
    return true;
}

/// Whether a type belongs to the checklist.
bool selected(const ref SliceEntry entry, const ref ApiType type)
{
    import flint_tool.api.coverage : matches;

    if (type.module_ != entry.module_)
        return false;
    if (entry.packages.length == 0)
        return true;
    foreach (pattern; entry.packages)
    {
        if (matches(pattern, type.decl.package_))
            return true;
    }
    return false;
}

/// Render one checklist; `counts` receives its totals.
string renderChecklist(const ref SliceEntry entry, string sliceTitle, const ref Manifest manifest,
        string manifestPath, const ref Classifier classifier, string mappingPath, out ChecklistCounts counts)
{
    import std.array : appender, join;
    import flint_tool.api.manifest : memberId;

    auto body = appender!string;
    string currentPackage;
    foreach (ref type; manifest.types)
    {
        if (!selected(entry, type))
            continue;
        if (type.decl.package_ != currentPackage)
        {
            currentPackage = type.decl.package_;
            body ~= "\n## `" ~ currentPackage ~ "`\n";
        }
        counts.types++;
        body ~= "\n### " ~ cast(string) type.decl.kind ~ " `" ~ type.decl.name ~ "`\n\n";
        body ~= "| Status | Element | Id |\n| --- | --- | --- |\n";
        body ~= row(status(classifier, type.decl.id, counts), declaration(type.decl), type.decl.id);
        foreach (ref member; type.decl.members)
            body ~= row(status(classifier, memberId(type.decl, member), counts),
                    declaration(member, simpleName(type.decl.name)), "#" ~ member.signature);
    }
    auto text = appender!string;
    text ~= "# " ~ entry.name ~ ": " ~ sliceTitle ~ " checklist\n\n";
    text ~= "Generated by `flint api checklist` from `" ~ manifestPath ~ "` (" ~ manifest.project
        ~ " " ~ manifest.version_ ~ ", module `" ~ entry.module_ ~ "`)";
    text ~= entry.packages.length ? ", packages `" ~ entry.packages.join("`, `") ~ "`.\n\n" : ".\n\n";
    text ~= "Do not edit this file. Classify elements in `" ~ mappingPath ~ "` (docs/spring/api-mapping.md), "
        ~ "then regenerate it. A status reads `ported`, `adapted` with its rules, or `excluded` with its "
        ~ "category, and is empty while the element is open. The Id column is the key for the mapping: a type's "
        ~ "id, or `#signature` after its type's id.\n\n";
    text ~= summaryLine(counts) ~ "\n";
    text ~= body[];
    return text[];
}

/// `N types, M elements: p ported, a adapted, e excluded, o open.`
string summaryLine(const ref ChecklistCounts counts)
{
    import std.format : format;

    return format("%d types, %d elements: %d ported, %d adapted, %d excluded, %d open.",
            counts.types, counts.elements, counts.ported, counts.adapted, counts.excluded, counts.open);
}

private string row(string statusText, string element, string id)
{
    return "| " ~ statusText ~ " | `" ~ cell(element) ~ "` | `" ~ cell(id) ~ "` |\n";
}

/// Make text safe inside a Markdown table cell wrapped in backticks.
string cell(string text)
{
    string safe;
    foreach (c; text)
    {
        if (c == '|')
            safe ~= "\\|";
        else if (c == '`')
            safe ~= '\'';
        else if (c == '\n')
            safe ~= ' ';
        else
            safe ~= c;
    }
    return safe;
}

private string status(const ref Classifier classifier, string id, ref ChecklistCounts counts)
{
    import std.array : join;
    import flint_tool.api.coverage : Status;

    counts.elements++;
    const entry = classifier.classify(id);
    if (entry is null)
        return "";
    final switch (entry.status)
    {
    case Status.ported:
        counts.ported++;
        return "ported `" ~ entry.symbol ~ "`";
    case Status.adapted:
        counts.adapted++;
        return "adapted " ~ entry.rules.join(", ") ~ (entry.symbol.length ? " `" ~ entry.symbol ~ "`" : "");
    case Status.excluded:
        counts.excluded++;
        return "excluded: " ~ entry.category ~ (entry.phase.length ? " (phase " ~ entry.phase ~ ")" : "");
    case Status.unclassified:
        return "";
    }
}

/// A type's declaration line: `@FunctionalInterface public interface Supplier<T> extends Base`.
string declaration(const ref TypeDecl decl)
{
    import std.array : join;

    string[] parts = decl.annotations.dup ~ decl.visibility ~ decl.modifiers.dup;
    const keyword = decl.kind == TypeKind.annotation ? "@interface" : cast(string) decl.kind;
    parts ~= keyword;
    const simple = simpleName(decl.name);
    parts ~= decl.typeParameters.length ? simple ~ "<" ~ decl.typeParameters.join(", ") ~ ">" : simple;
    if (decl.extends_.length)
        parts ~= "extends " ~ decl.extends_.join(", ");
    if (decl.implements_.length)
        parts ~= "implements " ~ decl.implements_.join(", ");
    if (decl.permits.length)
        parts ~= "permits " ~ decl.permits.join(", ");
    return parts.join(" ");
}

/// A member's declaration line, as Java would write it; constructors take `typeName`.
string declaration(const ref Member member, string typeName)
{
    import std.array : join;

    string[] parts = member.annotations.dup ~ member.visibility ~ member.modifiers.dup;
    if (member.typeParameters.length)
        parts ~= "<" ~ member.typeParameters.join(", ") ~ ">";
    final switch (member.kind)
    {
    case MemberKind.constructor:
        parts ~= typeName ~ "(" ~ member.parameters.join(", ") ~ ")";
        break;
    case MemberKind.method:
        parts ~= member.type ~ " " ~ member.name ~ "(" ~ member.parameters.join(", ") ~ ")";
        break;
    case MemberKind.attribute:
        parts ~= member.type ~ " " ~ member.name ~ "()" ~ (member.defaultValue.length
                ? " default " ~ member.defaultValue : "");
        break;
    case MemberKind.field:
    case MemberKind.component:
        parts ~= member.type ~ " " ~ member.name;
        break;
    case MemberKind.constant:
        parts ~= member.name;
        break;
    }
    if (member.throws_.length)
        parts ~= "throws " ~ member.throws_.join(", ");
    if (member.implicit_)
        parts ~= "(implicit)";
    return parts.join(" ");
}

/// The last name of a dotted name: `Outer.Inner` → `Inner`.
string simpleName(string name)
{
    foreach_reverse (index, c; name)
    {
        if (c == '.')
            return name[index + 1 .. $];
    }
    return name;
}

/// One row of the slice index.
struct IndexRow
{
    /// Checklist name.
    string name;
    /// Upstream.
    string upstream;
    /// Module.
    string module_;
    /// Totals.
    ChecklistCounts counts;
}

/// The README of a checklist directory: one row per checklist.
string renderIndex(string sliceTitle, string slicePath, const(IndexRow)[] rows)
{
    import std.format : format;

    string text = "# " ~ sliceTitle ~ " checklists\n\n";
    text ~= "Generated by `flint api checklist --slice " ~ slicePath ~ "`. Each checklist lists every public "
        ~ "and protected element of its module, with the status its repo's `api/<repo>/mapping.json` gives it. "
        ~ "Do not edit the checklists: classify in the mapping, then regenerate.\n\n";
    text ~= "| Checklist | Upstream | Module | Types | Elements | Ported | Adapted | Excluded | Open |\n";
    text ~= "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n";
    ChecklistCounts total;
    foreach (ref item; rows)
    {
        text ~= format("| [%s](%s.md) | %s | `%s` | %d | %d | %d | %d | %d | %d |\n", item.name,
                item.name, item.upstream, item.module_, item.counts.types, item.counts.elements,
                item.counts.ported, item.counts.adapted, item.counts.excluded, item.counts.open);
        total.types += item.counts.types;
        total.elements += item.counts.elements;
        total.ported += item.counts.ported;
        total.adapted += item.counts.adapted;
        total.excluded += item.counts.excluded;
    }
    text ~= format("| **total** | | | %d | %d | %d | %d | %d | %d |\n", total.types,
            total.elements, total.ported, total.adapted, total.excluded, total.open);
    return text;
}
