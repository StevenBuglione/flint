/// Resolve the parent of an R3 marker interface against the pinned API and the landed D mapping.
module flint_tool.api.interface_references;

import flint_tool.api.annotation_references : JavaReferences, identifier;
import flint_tool.api.coverage : Classifier, Status;
import flint_tool.api.java : TypeDecl, TypeKind;
import flint_tool.api.manifest : Manifest;
import std.json : JSONValue;

@safe:

private enum javaOrdered = "org.springframework.core.Ordered";
private enum dModule = "flint.core";
private enum dOrdered = dModule ~ ".Ordered";

package bool supportedMarkerInterface(const ref TypeDecl decl)
{
    return identifier(decl.name) && decl.extends_.length == 1 && !decl.modifiers.length
        && !decl.annotations.length && !decl.typeParameters.length && !decl.implements_.length
        && !decl.permits.length && !decl.members.length;
}

package string renderMarkerInterface(const ref Manifest manifest, const ref TypeDecl decl,
        const ref Classifier classifier, string module_, const ref JSONValue candidate, out string error)
{
    const name = candidate["symbol"].str;
    const base = candidate["interfaceParent"].str;
    if (!identifier(name) || base != decl.extends_[0])
    {
        error = decl.id ~ ": unsupported marker interface declaration differs from the pinned manifest";
        return null;
    }
    const references = JavaReferences(manifest.types, decl.package_, candidate["referenceImports"].arrayNoRef);
    const parent = references.findType(references.typeId(base));
    if (parent is null || parent.decl.kind != TypeKind.interface_ || parent.decl.visibility != "public"
            || parent.decl.typeParameters.length || parent.decl.id != javaOrdered || decl.id == javaOrdered)
    {
        error = decl.id ~ ": unsupported marker interface parent in the pinned manifest: " ~ base;
        return null;
    }
    // The golden confirms this exact mapped symbol is a D interface.
    const mapping = classifier.classify(javaOrdered);
    if (module_ == dModule && name != "Ordered" && mapping !is null && mapping.match == javaOrdered
            && mapping.status == Status.ported && mapping.symbol == dOrdered)
    {
        return "interface " ~ name ~ " : Ordered\n{\n}\n";
    }
    error = decl.id ~ ": marker interface parent requires an exact ported mapping to " ~ dOrdered;
    return null;
}
