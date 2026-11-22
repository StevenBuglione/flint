/// `flint package --container`: a `FROM scratch` OCI image around a static executable (ADR-023).
///
/// flint writes the image itself, as an OCI image-layout archive, so no container engine is needed to build it.
/// The single layer holds `/app/<executable>` and the project's config/ and resources/; the image runs the
/// executable from /app as an unprivileged user. `docker load` and `podman load` accept the archive.
module flint_tool.engine.oci;

import flint_tool.support.archive : Entry;

@safe:

/// What the image contains.
struct ImageSpec
{
    /// Repository name, such as "cdemo".
    string name;
    /// Tag, such as "0.1.0".
    string tag;
    /// OCI architecture, such as "amd64".
    string architecture = "amd64";
    /// Executable file name inside /app.
    string executable;
    /// The layer's files, with paths relative to the image root.
    Entry[] files;
    /// Image labels (org.opencontainers.image.*).
    string[string] labels;
    /// Seconds since the epoch recorded as the creation time.
    long created;
}

/// The digests of a written image.
struct ImageResult
{
    /// The OCI archive bytes.
    ubyte[] archive;
    /// sha256:... of the manifest (the image's identity).
    string manifestDigest;
    /// sha256:... of the image configuration.
    string configDigest;
    /// sha256:... of the uncompressed layer.
    string diffId;
}

/// The OCI image-layout archive of `spec`.
ImageResult imageArchive(const ref ImageSpec spec)
{
    import flint_tool.support.archive : gzip, octal644, tarArchive;

    ImageResult result;
    const layer = tarArchive(spec.files, spec.created);
    const compressed = gzip(layer);
    result.diffId = "sha256:" ~ hex(layer);
    const config = imageConfig(spec, result.diffId);
    result.configDigest = "sha256:" ~ hex(cast(const(ubyte)[]) config);
    const manifest = `{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":`
        ~ descriptor("application/vnd.oci.image.config.v1+json", result.configDigest,
                config.length) ~ `,"layers":[` ~ descriptor("application/vnd.oci.image.layer.v1.tar+gzip",
                "sha256:" ~ hex(compressed), compressed.length) ~ `]}`;
    result.manifestDigest = "sha256:" ~ hex(cast(const(ubyte)[]) manifest);
    const reference = spec.name ~ ":" ~ spec.tag;
    const annotations = `,"annotations":{"org.opencontainers.image.ref.name":` ~ jsonString(
            spec.tag) ~ `,"io.containerd.image.name":` ~ jsonString("docker.io/library/" ~ reference) ~ `}`;
    const listed = descriptor("application/vnd.oci.image.manifest.v1+json", result.manifestDigest,
            manifest.length, annotations);
    const index = `{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[`
        ~ listed ~ `]}`;
    Entry[] entries = [
        Entry("oci-layout", cast(const(ubyte)[]) `{"imageLayoutVersion":"1.0.0"}`, octal644),
        Entry("index.json", cast(const(ubyte)[]) index, octal644), Entry("blobs/"),
        Entry("blobs/sha256/"),
        Entry("blobs/sha256/" ~ hex(cast(const(ubyte)[]) config), cast(const(ubyte)[]) config, octal644),
        Entry("blobs/sha256/" ~ hex(compressed), compressed, octal644),
        Entry("blobs/sha256/" ~ hex(cast(const(ubyte)[]) manifest), cast(const(ubyte)[]) manifest, octal644)
    ];
    foreach (ref entry; entries)
    {
        if (entry.path[$ - 1] == '/')
            entry.mode = 493;
    }
    result.archive = tarArchive(entries, spec.created);
    return result;
}

/// The image configuration: entrypoint, working directory, user and the layer's diff ID.
string imageConfig(const ref ImageSpec spec, string diffId)
{
    import std.algorithm.sorting : sort;

    string labels;
    foreach (key; sort(spec.labels.keys.dup))
        labels ~= (labels.length ? "," : "") ~ jsonString(key) ~ ":" ~ jsonString(spec.labels[key]);
    return `{"architecture":` ~ jsonString(
            spec.architecture) ~ `,"os":"linux","created":` ~ jsonString(rfc3339(spec.created))
        ~ `,"config":{"User":"65532:65532","WorkingDir":"/app","Entrypoint":[` ~ jsonString(
                "/app/" ~ spec.executable) ~ `],"Env":["PATH=/app"],"Labels":{` ~ labels
        ~ `}},"rootfs":{"type":"layers","diff_ids":[` ~ jsonString(diffId)
        ~ `]},"history":[{"created":` ~ jsonString(
                rfc3339(spec.created)) ~ `,"created_by":"flint package --container"}]}`;
}

private string descriptor(string mediaType, string digest, size_t size, string extra = null)
{
    import std.conv : to;

    return `{"mediaType":` ~ jsonString(mediaType) ~ `,"digest":` ~ jsonString(
            digest) ~ `,"size":` ~ size.to!string ~ extra ~ `}`;
}

/// Lower-case hexadecimal SHA-256.
string hex(scope const(ubyte)[] data)
{
    import flint_tool.support.files : sha256Hex;

    return sha256Hex(data);
}

/// A JSON string literal.
string jsonString(string value)
{
    import std.format : format;

    string text = "\"";
    foreach (ch; value)
    {
        if (ch == '"' || ch == '\\')
            text ~= '\\';
        if (ch < 0x20)
            text ~= format("\\u%04x", ch);
        else
            text ~= ch;
    }
    return text ~ "\"";
}

/// RFC 3339 UTC time of `seconds` since the epoch.
string rfc3339(long seconds)
{
    import std.datetime.systime : SysTime, unixTimeToStdTime;
    import std.datetime.timezone : UTC;

    const time = SysTime(unixTimeToStdTime(seconds), UTC());
    return time.toISOExtString()[0 .. 19] ~ "Z";
}
