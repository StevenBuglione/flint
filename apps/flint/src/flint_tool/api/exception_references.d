/// Resolve an R8 message-forwarding constructor against the pinned API and its landed D base class.
module flint_tool.api.exception_references;

import flint_tool.api.annotation_references : JavaReferences, identifier, mappedSymbol;
import flint_tool.api.coverage : Classifier;
import flint_tool.api.java : Member, MemberKind, TypeDecl, TypeKind, erasedParameterType;
import flint_tool.api.manifest : ApiType, Manifest;
import std.json : JSONValue;

@safe:

private enum javaBase = "org.springframework.transaction.TransactionUsageException";
private enum dModule = "flint.transaction";
private enum dBase = dModule ~ ".TransactionUsageException";

package bool supportedException(const ref TypeDecl decl)
{
    if (decl.modifiers.length || decl.typeParameters.length || decl.implements_.length
            || decl.permits.length || decl.extends_.length != 1 || decl.members.length != 1)
        return false;
    if (decl.annotations.length && decl.annotations != ["@SuppressWarnings(\"serial\")"]
            && decl.annotations != ["@java.lang.SuppressWarnings(\"serial\")"])
        return false;
    return supportedConstructor(decl.members[0]);
}

private bool supportedConstructor(const ref Member constructor)
{
    if (constructor.parameters.length != 1 || !messageType(erasedParameterType(constructor.parameters[0])))
        return false;
    return constructor.kind == MemberKind.constructor && constructor.name == "<init>"
        && constructor.visibility == "public" && !constructor.implicit_ && !constructor.modifiers.length
        && !constructor.annotations.length && !constructor.typeParameters.length && !constructor.throws_.length;
}

private bool messageType(string type)
{
    return type == "String" || type == "java.lang.String";
}

package string renderException(const ref Manifest manifest, const ref TypeDecl decl,
        const ref Classifier classifier, string module_, const ref JSONValue candidate, out string error)
{
    const ref proof = candidate["exception"];
    const name = candidate["symbol"].str;
    const parameter = proof["parameter"].str;
    const type = proof["parameterType"].str;
    if (!identifier(name) || !identifier(parameter) || !messageType(type) || parameter == "file"
            || parameter == "line" || parameter == "string" || parameter == "size_t"
            || decl.members[0].parameters[0] != type ~ " " ~ parameter || decl.extends_[0] != proof["base"].str)
    {
        error = decl.id ~ ": unsupported exception declaration differs from the pinned manifest";
        return null;
    }
    const references = JavaReferences(manifest.types, decl.package_, candidate["referenceImports"].arrayNoRef);
    if (hasImplicitShadow(references, proof))
    {
        error = decl.id ~ ": unsupported exception with shadowed java.lang types";
        return null;
    }
    const base = references.findType(references.typeId(decl.extends_[0]));
    if (module_ != dModule || !hasMappedBase(base, classifier))
    {
        error = decl.id ~ ": unsupported exception base or destination; expected " ~ dBase;
        return null;
    }
    return "class " ~ name ~ " : TransactionUsageException\n{\n" ~ "    this(string " ~ parameter
        ~ ", string file = __FILE__, size_t line = __LINE__) pure nothrow\n"
        ~ "    {\n        super(" ~ parameter ~ ", null, file, line);\n    }\n}\n";
}

private bool hasImplicitShadow(const ref JavaReferences references, const ref JSONValue proof)
{
    return (proof["implicitString"].boolean && references.findType(references.package_ ~ ".String") !is null)
        || (proof["implicitSuppressWarnings"].boolean
                && references.findType(references.package_ ~ ".SuppressWarnings") !is null);
}

private bool hasMappedBase(const(ApiType)* base, const ref Classifier classifier)
{
    import std.algorithm.searching : any;

    if (base is null || base.decl.id != javaBase || base.decl.kind != TypeKind.class_ || base.decl.visibility
            != "public")
        return false;
    // The landed D constructor combines the Java message-only and message-and-cause overloads.
    if (mappedSymbol(classifier, javaBase) != dBase)
        return false;
    foreach (signature; ["<init>(String)", "<init>(String,Throwable)"])
        if (mappedSymbol(classifier, javaBase ~ "#" ~ signature) != dBase ~ ".this"
                || !base.decl.members.any!(member => member.kind == MemberKind.constructor
                    && member.visibility == "public" && member.signature() == signature))
            return false;
    return true;
}
