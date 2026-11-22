/// What a packaged executable contains, as SPDX 2.3 and CycloneDX 1.6 SBOMs (ADR-021 section 9, ADR-023).
///
/// The inventory is also what `flint deps audit` checks: every component's origin, version, licence, content hash
/// and linkage.
module flint_tool.engine.sbom;

import flint_tool.home.policy : Home;
import flint_tool.project.manifest : Manifest;
import flint_tool.project.resolve : Resolution;

@safe:

/// One component of the executable.
struct Component
{
    /// Unique reference inside the document.
    string reference;
    /// Name.
    string name;
    /// Version, or empty.
    string version_;
    /// "application", "library" or "file".
    string type = "library";
    /// "project", "flint", "repository", "path", "dub", "native", "toolchain" or "embedded-c".
    string origin;
    /// SPDX licence expression, or empty when unknown.
    string license;
    /// SHA-256 of the content (tree hash, archive hash or file hash), or empty.
    string sha256;
    /// Package URL.
    string purl;
    /// Where the source comes from, or empty.
    string download;
    /// "static", "bundled", "dynamic" (system libraries) or "source".
    string linkage = "static";
    /// References of the components it depends on.
    string[] dependsOn;
    /// An `[unchecked]` waiver reason, when the component skipped the safety checks.
    string waiver;
}

/// Every component of one executable.
struct Inventory
{
    /// The application.
    Component root;
    /// Everything it contains or links.
    Component[] components;
    /// Target, such as linux-x86_64-musl.
    string target;
}

/// Collect the inventory of a project built for `target`. `artifactSha256` is the executable's hash and
/// `cSources` the embedded C as (project-relative path, sha256) pairs.
Inventory collect(const ref Home home, const ref Manifest manifest, const ref Resolution resolution,
        string target, string artifactSha256, scope const string[2][] cSources,
        const ref imported!"flint_tool.project.native".NativeResolution natives)
{
    Inventory inventory;
    inventory.target = target;
    inventory.root = Component(reference("app", manifest.name), manifest.name, manifest.version_,
            "application", "project", manifest.license, artifactSha256,
            "pkg:generic/" ~ manifest.name ~ "@" ~ manifest.version_);
    foreach (direct; resolution.direct)
        inventory.root.dependsOn ~= referenceOf(resolution, direct);
    foreach (ref item; resolution.packages)
    {
        if (item.testOnly)
            continue;
        Component component;
        component.reference = referenceOf(resolution, item.name);
        component.name = item.name;
        component.sha256 = item.contentSha256;
        foreach (dependency; item.dependencies)
            component.dependsOn ~= referenceOf(resolution, dependency);
        describe(home, manifest, item.kind, item.version_, item.commit, item.license, component);
        if (item.kind == "dub")
            component.download = "git+https://" ~ item.declaredPath ~ "@" ~ item.commit;
        inventory.components ~= component;
    }
    foreach (pair; cSources)
    {
        auto file = Component(reference("c", pair[0]), pair[0], manifest.version_, "file",
                "embedded-c", manifest.license, pair[1], null, null, "static");
        inventory.root.dependsOn ~= file.reference;
        inventory.components ~= file;
    }
    foreach (ref native; natives.packages)
    {
        auto component = Component(reference("native", native.name), native.name, native.version_,
                "library", "native", native.license, native.linkage == "system" ? null : native.sourceSha256,
                "pkg:generic/flint-native/" ~ native.name ~ "@" ~ native.version_, null,
                native.linkage == "system" ? "dynamic" : native.linkage);
        foreach (dependency; native.dependencies)
            component.dependsOn ~= reference("native", dependency);
        if (native.direct)
            inventory.root.dependsOn ~= component.reference;
        inventory.components ~= component;
    }
    foreach (runtime; runtimeComponents(home, target))
    {
        inventory.root.dependsOn ~= runtime.reference;
        inventory.components ~= runtime;
    }
    return inventory;
}

private void describe(const ref Home home, const ref Manifest manifest, string kind, string version_,
        string commit, string license, ref Component component)
{
    component.origin = kind == "core" ? "flint" : kind == "remote" ? "repository" : kind == "local" ? "dub" : kind;
    switch (kind)
    {
    case "core":
        component.version_ = home.platform.release;
        component.license = "Apache-2.0";
        component.purl = "pkg:generic/flint/" ~ component.name[6 .. $] ~ "@" ~ home.platform.release;
        break;
    case "remote":
        component.version_ = version_;
        component.license = license;
        component.download = "git+https://" ~ component.name ~ "@" ~ commit;
        component.purl = "pkg:generic/" ~ encode(component.name) ~ "@" ~ version_ ~ "?vcs_url=" ~ encode(
                "git+https://" ~ component.name ~ "@" ~ commit);
        break;
    case "dub":
        component.version_ = version_;
        component.license = license;
        component.purl = "pkg:generic/dub/" ~ encode(component.name[4 .. $]) ~ "@" ~ version_;
        waiverOf(manifest, component);
        break;
    default:
        component.license = license;
        component.purl = "pkg:generic/" ~ encode(component.name);
        waiverOf(manifest, component);
    }
}

private void waiverOf(const ref Manifest manifest, ref Component component)
{
    foreach (ref unchecked; manifest.unchecked)
    {
        if (unchecked.name == component.name || "dub:" ~ unchecked.name == component.name)
            component.waiver = unchecked.reason;
    }
}

/// The D runtime and, for musl, the C runtime the static executable contains; for glibc, the system libc.
Component[] runtimeComponents(const ref Home home, string target)
{
    import std.algorithm.searching : canFind;

    const ldc = home.versions.get("ldc", "");
    Component[] found = [
        Component(reference("runtime", "druntime"), "druntime", ldc, "library", "toolchain", "BSL-1.0", null,
                "pkg:generic/ldc/druntime@" ~ ldc, "https://github.com/ldc-developers/ldc/releases/tag/v" ~ ldc),
        Component(reference("runtime", "phobos"), "phobos", ldc, "library", "toolchain", "BSL-1.0", null,
                "pkg:generic/ldc/phobos@" ~ ldc, "https://github.com/ldc-developers/ldc/releases/tag/v" ~ ldc)
    ];
    if (target.canFind("musl"))
    {
        foreach (ref package_; muslPackages(home))
        {
            if (package_[0] != "musl" && package_[0] != "libgcc")
                continue;
            found ~= Component(reference("runtime", package_[0]), package_[0], package_[1],
                    "library", "toolchain", package_[3], package_[2],
                    "pkg:apk/alpine/" ~ package_[0] ~ "@" ~ package_[1] ~ "?arch=x86_64", package_[4]);
        }
    }
    else
        found ~= Component(reference("runtime", "glibc"), "glibc", null, "library", "toolchain",
                "LGPL-2.1-or-later", null, "pkg:generic/glibc", "https://www.gnu.org/software/libc/", "dynamic");
    return found;
}

/// (name, version, sha256, licence, url) of each pinned musl sysroot package in policy/toolchains.json.
string[5][] muslPackages(const ref Home home)
{
    import std.path : buildPath;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import flint_tool.support.files : readIfPresent;

    // The version comes from the file name: the policy's "version" key is a D keyword.
    static struct Package
    {
        string name;
        string url;
        string sha256;
        string license;
    }

    static struct Sysroot
    {
        Package[] packages;
    }

    static struct Lock
    {
        Sysroot musl_sysroot;
    }

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    const text = readIfPresent(buildPath(home.root, "policy", "toolchains.json"));
    const decoded = deserialize!Lock(text.length ? text : "{}", lenient);
    string[5][] found;
    if (!decoded.ok)
        return found;
    foreach (ref item; decoded.value.musl_sysroot.packages)
        found ~= [item.name, versionOf(item.url, item.name), item.sha256, item.license, item.url];
    return found;
}

private string versionOf(string url, string name)
{
    import std.path : baseName;

    const file = baseName(url);
    return file.length > name.length + 5 ? file[name.length + 1 .. $ - 4] : null;
}

private string referenceOf(const ref Resolution resolution, string name)
{
    const item = resolution.find(name);
    return reference(item is null ? "package" : item.kind, name);
}

/// A document-unique reference made of SPDX identifier characters.
string reference(string kind, string name)
{
    string text = kind ~ "-";
    foreach (ch; name)
        text ~= (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
            || ch == '.' || ch == '-' ? ch : '-';
    return text;
}

private string encode(string text)
{
    import std.format : format;

    string encoded;
    foreach (ch; text)
    {
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
                || ch == '.' || ch == '-' || ch == '_' || ch == '~')
            encoded ~= ch;
        else
            encoded ~= format("%%%02X", ch);
    }
    return encoded;
}

/// A name-based (version 5 layout) UUID from a SHA-256 hex digest.
string uuidOf(string digest)
{
    const hex = digest ~ "00000000000000000000000000000000";
    const variant = "89ab"[(hex[16] - '0') & 3];
    const head = hex[0 .. 8] ~ "-" ~ hex[8 .. 12] ~ "-5" ~ hex[13 .. 16];
    return head ~ "-" ~ variant ~ hex[17 .. 20] ~ "-" ~ hex[20 .. 32];
}

/// The SPDX 2.3 JSON document.
string renderSpdx(const ref Inventory inventory, string toolVersion, string created)
{
    import flint_tool.engine.oci : jsonString;

    string packages = spdxPackage(inventory.root);
    string relationships = `{"spdxElementId":"SPDXRef-DOCUMENT","relationshipType":"DESCRIBES","relatedSpdxElement":`
        ~ jsonString("SPDXRef-" ~ inventory.root.reference) ~ `}`;
    foreach (ref component; inventory.components)
        packages ~= "," ~ spdxPackage(component);
    foreach (ref component; [inventory.root] ~ inventory.components)
    {
        foreach (dependency; component.dependsOn)
            relationships ~= `,{"spdxElementId":` ~ jsonString("SPDXRef-" ~ component.reference)
                ~ `,"relationshipType":"DEPENDS_ON","relatedSpdxElement":` ~ jsonString("SPDXRef-" ~ dependency) ~ `}`;
    }
    const namespace = "https://flint.invalid/spdx/" ~ inventory.root.name ~ "-"
        ~ inventory.root.version_ ~ "-" ~ inventory.target ~ "-" ~ inventory.root.sha256;
    return `{"spdxVersion":"SPDX-2.3","dataLicense":"CC0-1.0","SPDXID":"SPDXRef-DOCUMENT","name":` ~ jsonString(
            inventory.root.name ~ "-" ~ inventory.root.version_ ~ "-" ~ inventory.target)
        ~ `,"documentNamespace":` ~ jsonString(namespace) ~ `,"creationInfo":{"created":` ~ jsonString(
                created) ~ `,"creators":["Tool: flint-`
        ~ toolVersion ~ `"]},"packages":[` ~ packages ~ `],"relationships":[` ~ relationships ~ "]}\n";
}

private string spdxPackage(const ref Component component)
{
    import flint_tool.engine.oci : jsonString;

    string text = `{"name":` ~ jsonString(component.name) ~ `,"SPDXID":` ~ jsonString("SPDXRef-" ~ component.reference);
    if (component.version_.length)
        text ~= `,"versionInfo":` ~ jsonString(component.version_);
    text ~= `,"primaryPackagePurpose":` ~ jsonString(component.type == "application"
            ? "APPLICATION" : component.type == "file" ? "SOURCE" : "LIBRARY");
    text ~= `,"downloadLocation":` ~ jsonString(component.download.length ? component.download
            : "NOASSERTION") ~ `,"filesAnalyzed":false,"licenseConcluded":"NOASSERTION","licenseDeclared":`
        ~ jsonString(component.license.length ? component.license : "NOASSERTION") ~ `,"copyrightText":"NOASSERTION"`;
    if (component.sha256.length)
        text ~= `,"checksums":[{"algorithm":"SHA256","checksumValue":` ~ jsonString(component.sha256) ~ `}]`;
    if (component.purl.length)
        text ~= `,"externalRefs":[{"referenceCategory":"PACKAGE-MANAGER","referenceType":"purl","referenceLocator":`
            ~ jsonString(component.purl) ~ `}]`;
    string comment = "flint origin " ~ component.origin ~ ", linkage " ~ component.linkage;
    if (component.waiver.length)
        comment ~= "; [unchecked] waiver: " ~ component.waiver;
    return text ~ `,"comment":` ~ jsonString(comment) ~ "}";
}

/// The CycloneDX 1.6 JSON document.
string renderCycloneDx(const ref Inventory inventory, string toolVersion, string created)
{
    import flint_tool.engine.oci : jsonString;

    string components;
    string dependencies;
    foreach (ref component; inventory.components)
        components ~= (components.length ? "," : "") ~ cdxComponent(component);
    foreach (ref component; [inventory.root] ~ inventory.components)
    {
        string list;
        foreach (dependency; component.dependsOn)
            list ~= (list.length ? "," : "") ~ jsonString(dependency);
        dependencies ~= (dependencies.length ? "," : "") ~ `{"ref":` ~ jsonString(
                component.reference) ~ `,"dependsOn":[` ~ list ~ "]}";
    }
    return `{"bomFormat":"CycloneDX","specVersion":"1.6","serialNumber":` ~ jsonString(
            "urn:uuid:" ~ uuidOf(inventory.root.sha256)) ~ `,"version":1,"metadata":{"timestamp":` ~ jsonString(
            created) ~ `,"tools":{"components":[{"type":"application","name":"flint","version":` ~ jsonString(
            toolVersion) ~ `}]},"component":` ~ cdxComponent(
            inventory.root) ~ `,"properties":[{"name":"flint:target","value":` ~ jsonString(
            inventory.target) ~ `}]},"components":[` ~ components ~ `],"dependencies":[` ~ dependencies ~ "]}\n";
}

private string cdxComponent(const ref Component component)
{
    import flint_tool.engine.oci : jsonString;

    string text = `{"type":` ~ jsonString(component.type) ~ `,"bom-ref":` ~ jsonString(
            component.reference) ~ `,"name":` ~ jsonString(component.name);
    if (component.version_.length)
        text ~= `,"version":` ~ jsonString(component.version_);
    if (component.sha256.length)
        text ~= `,"hashes":[{"alg":"SHA-256","content":` ~ jsonString(component.sha256) ~ `}]`;
    if (component.license.length)
        text ~= `,"licenses":[{"expression":` ~ jsonString(component.license) ~ `}]`;
    if (component.purl.length)
        text ~= `,"purl":` ~ jsonString(component.purl);
    text ~= `,"properties":[{"name":"flint:origin","value":` ~ jsonString(
            component.origin) ~ `},{"name":"flint:linkage","value":` ~ jsonString(component.linkage) ~ `}`;
    if (component.waiver.length)
        text ~= `,{"name":"flint:unchecked-waiver","value":` ~ jsonString(component.waiver) ~ `}`;
    return text ~ "]}";
}
