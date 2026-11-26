/// Check an R1 constant-holder candidate against its pinned class and public fields.
module flint_tool.api.constant_holder;

import flint_tool.api.annotation_references : JavaReferences, identifier;
import flint_tool.api.java : Member, MemberKind, TypeDecl;
import flint_tool.api.manifest : Manifest;
import std.json : JSONValue;

@safe:

package bool supportedConstantHolder(const ref TypeDecl decl)
{
    import std.algorithm.searching : all;

    return identifier(decl.name) && decl.modifiers == ["final"] && !decl.annotations.length
        && !decl.extends_.length && !decl.implements_.length && !decl.permits.length
        && !decl.typeParameters.length && decl.members.length != 0 && decl.members.all!stringConstant;
}

private bool stringConstant(const ref Member field)
{
    const staticFinal = field.modifiers == ["static", "final"] || field.modifiers == [
        "final", "static"
    ];
    const stringType = field.type == "String" || field.type == "java.lang.String";
    return field.kind == MemberKind.field && field.visibility == "public"
        && !field.annotations.length && staticFinal && stringType;
}

package string renderConstantHolder(const ref Manifest manifest, const ref TypeDecl decl,
        const ref JSONValue candidate, out string error)
{
    import std.array : appender;

    const name = candidate["symbol"].str;
    const fields = candidate["members"].arrayNoRef;
    if (!candidate["staticHolder"].boolean || !identifier(name) || name == "string"
            || fields.length != decl.members.length)
    {
        error = decl.id ~ ": unsupported constant holder declaration differs from the pinned manifest";
        return null;
    }
    const references = JavaReferences(manifest.types, decl.package_, null);
    if (candidate["implicitString"].boolean && references.findType(decl.package_ ~ ".String") !is null)
    {
        error = decl.id ~ ": unsupported constant holder with a shadowed java.lang.String";
        return null;
    }
    auto result = appender!string;
    result.put("final class " ~ name ~ "\n{\n    @disable this();\n\n");
    bool[string] symbols;
    symbols[name] = true;
    symbols["string"] = true;
    foreach (index, ref field; fields)
    {
        const symbol = field["symbol"].str;
        const ref member = decl.members[index];
        if (field["name"].str != member.name || field["stringType"].str != member.type
                || !identifier(symbol) || symbol in symbols)
        {
            error = decl.id ~ ": unsupported constant holder field: " ~ member.name;
            return null;
        }
        symbols[symbol] = true;
        result.put("    enum string " ~ symbol ~ " = " ~ field["literal"].str ~ ";\n");
    }
    result.put("}\n");
    return result.data;
}
