/// `flint lsp`: a language server on the pinned compiler and its resident compile server (ADR-021 section 1,
/// ADR-027).
///
/// Diagnostics come from the pinned DMD's semantic check (`-o-`, no code generation) with the dev profile's flags,
/// plus Flint's own policy rules for the file. The resident compile server does not serve `-o-` checks yet, and
/// measured on flint's own modules it saves about 5% of a `-c` compile because it preloads only druntime and Phobos;
/// the plain check is the faster path today (ADR-027). Unsaved buffers are checked through an overlay directory that shadows the project's sources. Hover,
/// go-to-definition and completion answer from the API index of the pinned libraries.
module flint_tool.commands.lsp;

import flint_tool.engine.apiindex : ApiIndex;
import flint_tool.engine.session : Session;

@safe:

/// One LSP diagnostic.
struct LspDiagnostic
{
    /// Zero-based line.
    long line;
    /// Zero-based column.
    long column;
    /// 1 error, 2 warning.
    int severity;
    /// Message.
    string message;
    /// Code, such as FLINT-E0401 or dmd.
    string code;
}

/// Parse `file(line,col): Error: message` lines of DMD output for `file`.
LspDiagnostic[] compilerDiagnostics(string output, string file)
{
    import std.algorithm.searching : startsWith;
    import std.conv : ConvException, to;
    import std.string : indexOf, lineSplitter;

    LspDiagnostic[] found;
    foreach (line; output.lineSplitter)
    {
        if (!line.startsWith(file ~ "("))
            continue;
        const close = line.indexOf("): ");
        if (close < 0)
            continue;
        const position = line[file.length + 1 .. close];
        const comma = position.indexOf(',');
        long row;
        long column;
        try
        {
            row = (comma < 0 ? position : position[0 .. comma]).to!long;
            column = comma < 0 ? 1 : position[comma + 1 .. $].to!long;
        }
        catch (ConvException)
            continue;
        string message = line[close + 3 .. $].idup;
        int severity = 1;
        foreach (kind; ["Error: ", "Warning: ", "Deprecation: "])
        {
            if (message.startsWith(kind))
            {
                severity = kind == "Error: " ? 1 : 2;
                message = message[kind.length .. $];
            }
        }
        found ~= LspDiagnostic(row - 1, column - 1, severity, message, "dmd");
    }
    return found;
}

/// The identifier around a zero-based position, or empty.
string wordAt(string text, long line, long character)
{
    import std.string : lineSplitter;

    long current;
    foreach (content; text.lineSplitter)
    {
        if (current++ != line)
            continue;
        if (character > content.length)
            return null;
        size_t start = cast(size_t) character;
        size_t end = cast(size_t) character;
        while (start > 0 && identifierChar(content[start - 1]))
            start--;
        while (end < content.length && identifierChar(content[end]))
            end++;
        return content[start .. end].idup;
    }
    return null;
}

private bool identifierChar(char ch)
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_';
}

/// A file URI's path.
string uriPath(string uri)
{
    import std.algorithm.searching : startsWith;
    import std.uri : decodeComponent;

    return uri.startsWith("file://") ? decodeComponent(uri["file://".length .. $]) : uri;
}

/// The file URI of a path.
string pathUri(string path)
{
    import std.uri : encode;

    return "file://" ~ encode(path);
}

/// `flint lsp`: serve the Language Server Protocol on stdio until `exit`.
int commandLsp(ref Session session)
{
    Server server;
    server.session = session;
    while (true)
    {
        string message;
        if (!readMessage(message))
            return 0;
        if (!server.handle(message))
            return server.shutdown ? 0 : 1;
    }
}

/// One framed message from standard input: `Content-Length: N` headers, a blank line and N bytes.
private bool readMessage(out string message)
{
    import std.conv : ConvException, to;
    import std.string : strip, toLower;
    import flint_tool.sys.posix : readInput;

    size_t length;
    string header;
    ubyte[1] one;
    while (true)
    {
        if (readInput(one[]) != 1)
            return false;
        header ~= cast(char) one[0];
        if (header.length >= 4 && header[$ - 4 .. $] == "\r\n\r\n")
            break;
    }
    foreach (line; header.strip.toLower.splitLines)
    {
        if (line.length > 15 && line[0 .. 15] == "content-length:")
        {
            try
                length = line[15 .. $].strip.to!size_t;
            catch (ConvException)
                return false;
        }
    }
    auto body = new ubyte[length];
    size_t got;
    while (got < length)
    {
        const read = readInput(body[got .. $]);
        if (read == 0)
            return false;
        got += read;
    }
    message = (cast(const(char)[])
            body).idup;
    return true;
}

private string[] splitLines(string text)
{
    import std.array : split;

    return text.split("\r\n");
}

private void send(string json)
{
    import std.conv : to;
    import flint_tool.sys.posix : writeOutput;

    writeOutput("Content-Length: " ~ json.length.to!string ~ "\r\n\r\n" ~ json);
}

/// The server state: the workspace, open buffers and the API index.
private struct Server
{
    Session session;
    string root;
    string[string] documents;
    bool shutdown;
    bool indexLoaded;
    ApiIndex index;
    string overlay;

    /// Handle one message; false to stop.
    bool handle(string message)
    {
        import flint_tool.home.policy : member, objectMembers;

        string failure;
        const members = objectMembers(message, failure);
        if (failure.length)
            return true;
        const method = unquote(member(members, "method"));
        const id = member(members, "id");
        const params = member(members, "params");
        if (method == "exit")
            return false;
        if (notification(method, params))
            return true;
        const result = answer(method, params);
        if (result !is null)
            reply(id, result);
        else if (id.length)
            send(`{"jsonrpc":"2.0","id":` ~ id ~ `,"error":{"code":-32601,"message":"method not found"}}`);
        return true;
    }

    /// Handle a document notification; false when `method` is not one.
    private bool notification(string method, string params)
    {
        switch (method)
        {
        case "textDocument/didOpen":
        case "textDocument/didChange":
        case "textDocument/didSave":
            update(method, params);
            return true;
        case "textDocument/didClose":
            documents.remove(documentUri(params));
            return true;
        default:
            return false;
        }
    }

    /// The JSON result of a request, or null when `method` is not one.
    private string answer(string method, string params)
    {
        switch (method)
        {
        case "initialize":
            initialize(params);
            const release = quote(session.home.platform.release);
            return `{"capabilities":{"textDocumentSync":1,"hoverProvider":true,"definitionProvider":true,`
                ~ `"completionProvider":{"triggerCharacters":["."]}},"serverInfo":{"name":"flint","version":`
                ~ release ~ `}}`;
        case "textDocument/hover":
            return hover(params);
        case "textDocument/definition":
            return definition(params);
        case "textDocument/completion":
            return completion(params);
        case "shutdown":
            shutdown = true;
            return "null";
        default:
            return null;
        }
    }

    private void initialize(string params)
    {
        import std.file : getcwd;
        import flint_tool.home.policy : member, objectMembers;

        string failure;
        const members = objectMembers(params, failure);
        const rootUri = unquote(member(members, "rootUri"));
        root = rootUri.length ? uriPath(rootUri) : getcwd();
    }

    private void reply(string id, string result)
    {
        send(`{"jsonrpc":"2.0","id":` ~ (id.length ? id : "null") ~ `,"result":` ~ result ~ `}`);
    }

    private void update(string method, string params)
    {
        import flint_tool.home.policy : member, objectMembers;

        string failure;
        const members = objectMembers(params, failure);
        const document = objectMembers(member(members, "textDocument"), failure);
        const uri = unquote(member(document, "uri"));
        if (method == "textDocument/didOpen")
            documents[uri] = unquote(member(document, "text"));
        else if (method == "textDocument/didChange")
        {
            // Full synchronisation: the last change carries the whole text.
            const changes = member(members, "contentChanges");
            const text = lastText(changes);
            if (text !is null)
                documents[uri] = text;
        }
        if (uri in documents)
            publish(uri);
    }

    private string documentUri(string params)
    {
        import flint_tool.home.policy : member, objectMembers;

        string failure;
        return unquote(member(objectMembers(member(objectMembers(params, failure), "textDocument"), failure), "uri"));
    }

    /// Check one buffer and publish its diagnostics.
    private void publish(string uri)
    {
        import std.conv : to;

        string items;
        foreach (ref item; check(uri))
            items ~= (items.length ? "," : "") ~ `{"range":{"start":{"line":` ~ item.line.to!string
                ~ `,"character":` ~ item.column.to!string ~ `},"end":{"line":`
                ~ item.line.to!string ~ `,"character":` ~ (item.column + 1)
                    .to!string ~ `}},"severity":` ~ item.severity.to!string ~ `,"code":` ~ quote(
                            item.code) ~ `,"source":"flint","message":` ~ quote(item.message) ~ `}`;
        send(`{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":` ~ quote(
                uri) ~ `,"diagnostics":[` ~ items ~ `]}}`);
    }

    /// The compiler's and the policy rules' findings for one buffer.
    private LspDiagnostic[] check(string uri)
    {
        import std.algorithm.searching : startsWith;
        import std.file : mkdirRecurse, tempDir, write;
        import std.path : buildPath, dirName;
        import std.process : thisProcessID;
        import std.conv : to;
        import flint_tool.check.rules : SourceScan, checkAnnotations, checkDefault, scanSource;
        import flint_tool.diagnostics.report : Report;
        import flint_tool.support.process : Launch, capture;

        const path = uriPath(uri);
        const text = documents[uri];
        LspDiagnostic[] found;
        Report policy;
        SourceScan scan;
        if (scanSource(path, text, scan, policy))
        {
            checkDefault(scan, path.canFindSegment("ffi") || path.canFindSegment("sys"), policy);
            checkAnnotations(scan, path.canFindSegment("ffi") || path.canFindSegment("sys"),
                    session.home.safety.maxTrustedLines, policy);
        }
        foreach (item; policy.items)
            found ~= LspDiagnostic(item.line > 0 ? item.line - 1 : 0, 0, 1, item.message, item.code);
        // Unsaved buffers shadow the project's sources through an overlay that comes first on the import path.
        if (overlay.length == 0)
            overlay = buildPath(tempDir(), "flint-lsp-" ~ thisProcessID.to!string);
        string[] imports = ["-I" ~ buildPath(overlay, "src")];
        string target = path;
        foreach (open, content; documents)
        {
            const file = uriPath(open);
            const source = buildPath(root, "src");
            if (!file.startsWith(source ~ "/"))
                continue;
            const shadow = buildPath(overlay, "src", file[source.length + 1 .. $]);
            mkdirRecurse(dirName(shadow));
            write(shadow, content);
            if (open == uri)
                target = shadow;
        }
        imports ~= importPaths();
        imports ~= "-I" ~ buildPath(root, "src");
        imports ~= "-I" ~ buildPath(root, "test");
        Launch launch;
        launch.directory = root;
        const dmd = compiler();
        const result = capture([dmd, "-o-", "-c"] ~ devFlags() ~ imports ~ [target], launch);
        foreach (ref item; compilerDiagnostics(result.combined(), target))
            found ~= item;
        return found;
    }

    private string compiler()
    {
        import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;

        return componentPath(session.home, toolchainDirectory(session.home), "dmd");
    }

    private string[] devFlags()
    {
        import flint_tool.home.policy : ProfileSpec;

        ProfileSpec spec;
        session.home.profile("dev", spec);
        return spec.dflags.dup;
    }

    /// Import paths of the project's dependencies, from its resolution.
    private string[] importPaths()
    {
        import std.path : buildPath;
        import flint_tool.diagnostics.report : Report;
        import flint_tool.project.manifest : Manifest, parseManifest;
        import flint_tool.project.resolve : Resolution, resolve;

        Manifest manifest;
        Resolution resolution;
        Report report;
        if (!parseManifest(root, session.home, manifest, report) || !resolve(session.home,
                manifest, resolution, report))
            return null;
        string[] paths;
        foreach (ref item; resolution.packages)
        {
            if (item.kind == "core")
                paths ~= "-I" ~ buildPath(item.directory, "source");
            else if (item.kind == "dub" || item.kind == "local")
                paths ~= [
                "-I" ~ buildPath(item.directory, "source"), "-I" ~ buildPath(item.directory, "src")
            ];
            else
                paths ~= "-I" ~ buildPath(item.directory, "src");
        }
        return paths;
    }

    private bool loadIndex()
    {
        import flint_tool.diagnostics.report : Report;
        import flint_tool.engine.apiindex : load = loadIndex;

        if (indexLoaded)
            return true;
        Report report;
        const quiet = session.json;
        session.json = true;
        indexLoaded = load(session, index, report);
        session.json = quiet;
        return indexLoaded;
    }

    /// The best symbol for the word at the request's position, or size_t.max.
    private size_t symbolAt(string params)
    {
        import flint_tool.engine.apiindex : search;
        import flint_tool.home.policy : member, objectMembers;
        import std.conv : ConvException, to;

        string failure;
        const members = objectMembers(params, failure);
        const uri = unquote(member(objectMembers(member(members, "textDocument"), failure), "uri"));
        const position = objectMembers(member(members, "position"), failure);
        const text = uri in documents;
        if (text is null || !loadIndex())
            return size_t.max;
        long line;
        long character;
        try
        {
            line = member(position, "line").to!long;
            character = member(position, "character").to!long;
        }
        catch (ConvException)
            return size_t.max;
        const word = wordAt(*text, line, character);
        if (word.length == 0)
            return size_t.max;
        foreach (hit; search(index, word, 20))
        {
            if (index.symbols[hit.index].name == word)
                return hit.index;
        }
        return size_t.max;
    }

    private string hover(string params)
    {
        const found = symbolAt(params);
        if (found == size_t.max)
            return "null";
        const symbol = index.symbols[found];
        const markdown = "```d\n" ~ symbol.signature ~ "\n```\n" ~ symbol.comment ~ "\n`" ~ symbol.qualified ~ "`";
        return `{"contents":{"kind":"markdown","value":` ~ quote(markdown) ~ `}}`;
    }

    private string definition(string params)
    {
        import std.conv : to;
        import std.path : buildPath;

        const found = symbolAt(params);
        if (found == size_t.max)
            return "null";
        const symbol = index.symbols[found];
        const line = (symbol.line > 0 ? symbol.line - 1 : 0).to!string;
        return `{"uri":` ~ quote(pathUri(buildPath(session.home.root, symbol.file)))
            ~ `,"range":{"start":{"line":` ~ line ~ `,"character":0},"end":{"line":` ~ line ~ `,"character":0}}}`;
    }

    private string completion(string params)
    {
        import std.algorithm.searching : startsWith;
        import std.conv : ConvException, to;
        import flint_tool.home.policy : member, objectMembers;

        string failure;
        const members = objectMembers(params, failure);
        const uri = unquote(member(objectMembers(member(members, "textDocument"), failure), "uri"));
        const position = objectMembers(member(members, "position"), failure);
        const text = uri in documents;
        if (text is null || !loadIndex())
            return `{"isIncomplete":false,"items":[]}`;
        long line;
        long character;
        try
        {
            line = member(position, "line").to!long;
            character = member(position, "character").to!long;
        }
        catch (ConvException)
            return `{"isIncomplete":false,"items":[]}`;
        const prefix = wordBefore(*text, line, character);
        string items;
        bool[string] seen;
        size_t count;
        foreach (ref symbol; index.symbols)
        {
            if (count == 50 || prefix.length == 0)
                break;
            if (!symbol.name.startsWith(prefix) || symbol.name in seen)
                continue;
            seen[symbol.name] = true;
            count++;
            items ~= (items.length ? "," : "") ~ `{"label":` ~ quote(symbol.name) ~ `,"kind":` ~ completionKind(
                    symbol.kind) ~ `,"detail":` ~ quote(symbol.signature) ~ `,"documentation":` ~ quote(
                    symbol.comment) ~ `}`;
        }
        return `{"isIncomplete":` ~ (count == 50 ? "true" : "false") ~ `,"items":[` ~ items ~ `]}`;
    }
}

/// The identifier that ends at a zero-based position (what the user is typing).
string wordBefore(string text, long line, long character)
{
    import std.string : lineSplitter;

    long current;
    foreach (content; text.lineSplitter)
    {
        if (current++ != line)
            continue;
        size_t end = character > content.length ? content.length : cast(size_t) character;
        size_t start = end;
        while (start > 0 && identifierChar(content[start - 1]))
            start--;
        return content[start .. end].idup;
    }
    return null;
}

private string completionKind(string kind)
{
    switch (kind)
    {
    case "function":
        return "3";
    case "struct":
        return "22";
    case "class":
        return "7";
    case "interface":
        return "8";
    case "enum":
        return "13";
    case "enum member":
        return "20";
    case "variable":
        return "6";
    default:
        return "1";
    }
}

private bool canFindSegment(string path, string segment)
{
    import std.algorithm.searching : canFind;

    return path.canFind("/" ~ segment ~ "/");
}

/// The text of the last content change of a didChange notification.
private string lastText(string changes)
{
    import flint_tool.home.policy : member, objectMembers;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;

    static struct Change
    {
        string text;
    }

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    lenient.maxBytes = 64 << 20;
    const decoded = deserialize!(Change[])(changes, lenient);
    return decoded.ok && decoded.value.length ? decoded.value[$ - 1].text : null;
}

/// A JSON string's decoded value, or empty for anything else.
private string unquote(string json)
{
    import flint.serde : DecodeOptions;
    import flint.serde.owned : deserialize;

    if (json.length < 2 || json[0] != '"')
        return null;
    DecodeOptions options;
    options.maxBytes = 64 << 20;
    const decoded = deserialize!string(json, options);
    return decoded.ok ? decoded.value : null;
}

private string quote(string value)
{
    import flint_tool.engine.oci : jsonString;

    return jsonString(value);
}
