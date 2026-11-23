// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/env/ (PropertySourceLoader.java, PropertiesPropertySourceLoader.java, YamlPropertySourceLoader.java,
// OriginTrackedPropertiesLoader.java, OriginTrackedYamlLoader.java, OriginTrackedMapPropertySource.java).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: resources are passed as a description and their bytes (Flint has no class path),
// YAML is read by Flint's D engine instead of SnakeYAML, and XML properties files are not supported.

/// `org.springframework.boot.env`: loading `application.properties` and `application.yaml` into property sources.
///
/// Each loader turns one resource into one property source per document, named `name` or, for several documents,
/// `name (document #i)`, as Boot does. Values are origin-tracked strings, so a failure can name the file, line and
/// column a value came from.
module flint.boot.env;

import flint.boot.internal.lang : IllegalStateException;
import flint.boot.origin : Origin, OriginTrackedValue, TextResourceOrigin;

@safe:

/// A property source of origin-tracked values in document order.
///
/// Boot's `OriginTrackedMapPropertySource` extends spring-core's `MapPropertySource`; until `flint.core.env`
/// lands it stands alone with the same methods, and Boot adapts it to `ConfigurationPropertySource`.
final class OriginTrackedMapPropertySource
{
    private string name;
    private string[] keys;
    private OriginTrackedValue[string] values;
    private bool immutable_;

    /// A source called `name` holding `keys` (in order) mapped to `values`.
    this(string name, string[] keys, OriginTrackedValue[string] values, bool immutable_ = false) pure nothrow
    {
        this.name = name;
        this.keys = keys;
        this.values = values;
        this.immutable_ = immutable_;
    }

    /// The source's name (`Config resource 'class path resource [application.yaml]' via location ...`).
    string getName() const pure nothrow @nogc
    {
        return name;
    }

    /// The property names, in document order.
    const(string)[] getPropertyNames() const pure nothrow @nogc
    {
        return keys;
    }

    /// Whether `key` is present.
    bool containsProperty(string key) const pure nothrow
    {
        return (key in values) !is null;
    }

    /// The value of `key` as text, or `null`.
    string getProperty(string key) pure nothrow
    {
        if (auto value = key in values)
            return (*value).getValue();
        return null;
    }

    /// The tracked value of `key`, or `null`.
    OriginTrackedValue getTrackedValue(string key) pure nothrow
    {
        if (auto value = key in values)
            return *value;
        return null;
    }

    /// The origin of `key`'s value, or `null`.
    Origin getOrigin(string key)
    {
        auto value = getTrackedValue(key);
        return value is null ? null : value.getOrigin();
    }

    /// Whether the source may not change (Boot's loaded sources are immutable).
    bool isImmutable() const pure nothrow @nogc
    {
        return immutable_;
    }
}

/// Loads a resource into property sources; one implementation per file format.
interface PropertySourceLoader
{
    /// The file extensions the loader reads, without the dot.
    string[] getFileExtensions();

    /// Load `content`, the bytes of the resource described by `resource`, into sources named after `name`.
    OriginTrackedMapPropertySource[] load(string name, string resource, const(ubyte)[] content);
}

/// Loads `.properties` files, including multi-document files separated by `#---` or `!---`.
class PropertiesPropertySourceLoader : PropertySourceLoader
{
    string[] getFileExtensions()
    {
        return ["properties"];
    }

    /// Load `content` as ISO-8859-1 properties.
    OriginTrackedMapPropertySource[] load(string name, string resource, const(ubyte)[] content)
    {
        return load(name, resource, content, null);
    }

    /// Load with an explicit `encoding` (`"UTF-8"`); the default is ISO-8859-1, as for Java properties files.
    OriginTrackedMapPropertySource[] load(string name, string resource, const(ubyte)[] content, string encoding)
    {
        auto documents = new OriginTrackedPropertiesLoader(resource, content).load(encoding);
        return sources(name, documents);
    }
}

/// Loads `.yml` and `.yaml` files, one source per non-empty document.
class YamlPropertySourceLoader : PropertySourceLoader
{
    string[] getFileExtensions()
    {
        return ["yml", "yaml"];
    }

    /// Load `content`, which must be UTF-8.
    OriginTrackedMapPropertySource[] load(string name, string resource, const(ubyte)[] content)
    {
        auto documents = new OriginTrackedYamlLoader(resource, content).load();
        return sources(name, documents);
    }
}

private OriginTrackedMapPropertySource[] sources(string name, Document[] documents) pure
{
    import std.conv : to;

    OriginTrackedMapPropertySource[] result;
    foreach (index, document; documents)
    {
        const suffix = documents.length != 1 ? " (document #" ~ index.to!string ~ ")" : "";
        result ~= new OriginTrackedMapPropertySource(name ~ suffix, document.keys, document.values, true);
    }
    return result;
}

/// One document's properties, in order.
final class Document
{
    /// The keys, in first-insertion order.
    string[] keys;
    /// The values by key.
    OriginTrackedValue[string] values;

    /// Set `key` to `value`; an empty key is ignored.
    void put(string key, OriginTrackedValue value) pure nothrow
    {
        if (key.length == 0)
            return;
        if ((key in values) is null)
            keys ~= key;
        values[key] = value;
    }

    /// Whether the document holds no properties.
    bool isEmpty() const pure nothrow @nogc
    {
        return keys.length == 0;
    }

    /// The value of `key`, or `null`.
    OriginTrackedValue get(string key) pure nothrow
    {
        if (auto value = key in values)
            return *value;
        return null;
    }
}

/// Reads Java `.properties` syntax, tracking where each value starts, with Boot's extensions: `key[]=a,b`
/// expands to `key[0]` and `key[1]`, and `#---` or `!---` alone on a line separates documents.
final class OriginTrackedPropertiesLoader
{
    private string resource;
    private const(ubyte)[] content;

    /// A loader for `content`, the bytes of the resource described by `resource`.
    this(string resource, const(ubyte)[] content) pure nothrow
    {
        this.resource = resource;
        this.content = content;
    }

    /// Load the documents, decoding with `encoding` (`"UTF-8"`, or ISO-8859-1 when `null`).
    Document[] load(string encoding = null, bool expandLists = true)
    {
        Document[] documents;
        auto document = new Document;
        auto reader = CharacterReader(decode(content, encoding));
        dchar[] buffer;
        while (reader.read())
        {
            if (reader.isCommentPrefixCharacter())
            {
                const prefix = reader.getCharacter();
                if (isNewDocument(reader))
                {
                    if (!document.isEmpty())
                        documents ~= document;
                    document = new Document;
                }
                else
                {
                    if (document.isEmpty() && documents.length)
                    {
                        document = documents[$ - 1];
                        documents = documents[0 .. $ - 1];
                    }
                    reader.lastLineCommentPrefixCharacter = prefix;
                    reader.skipComment();
                }
            }
            else
            {
                reader.lastLineCommentPrefixCharacter = -1;
                loadKeyAndValue(expandLists, document, reader, buffer);
            }
        }
        bool contained;
        foreach (existing; documents)
            contained = contained || existing is document;
        if (!document.isEmpty() && !contained)
            documents ~= document;
        return documents;
    }

    private void loadKeyAndValue(bool expandLists, Document document, ref CharacterReader reader, ref dchar[] buffer)
    {
        import std.conv : to;
        import std.string : strip;

        auto key = loadKey(buffer, reader).strip;
        if (expandLists && key.length >= 2 && key[$ - 2 .. $] == "[]")
        {
            key = key[0 .. $ - 2];
            int index;
            do
            {
                auto value = loadValue(buffer, reader, true);
                document.put(key ~ "[" ~ (index++).to!string ~ "]", value);
                if (!reader.isEndOfLine())
                    reader.read();
            }
            while (!reader.isEndOfLine());
        }
        else
            document.put(key, loadValue(buffer, reader, false));
    }

    private static string loadKey(ref dchar[] buffer, ref CharacterReader reader)
    {
        import std.conv : to;

        buffer.length = 0;
        bool previousWhitespace;
        while (!reader.isEndOfLine())
        {
            if (reader.isPropertyDelimiter())
            {
                reader.read();
                return buffer.to!string;
            }
            if (!reader.isWhiteSpace() && previousWhitespace)
                return buffer.to!string;
            previousWhitespace = reader.isWhiteSpace();
            buffer ~= reader.getCharacter();
            reader.read();
        }
        return buffer.to!string;
    }

    private OriginTrackedValue loadValue(ref dchar[] buffer, ref CharacterReader reader, bool splitLists)
    {
        import std.conv : to;

        buffer.length = 0;
        while (reader.isWhiteSpace() && !reader.isEndOfLine())
            reader.read();
        const location = reader.getLocation();
        while (!reader.isEndOfLine() && !(splitLists && reader.isListDelimiter()))
        {
            buffer ~= reader.getCharacter();
            reader.read();
        }
        return OriginTrackedValue.of(buffer.to!string, new TextResourceOrigin(resource, location));
    }

    private static bool isNewDocument(ref CharacterReader reader)
    {
        if (reader.isSameLastLineCommentPrefix())
            return false;
        bool result = reader.getLocation().getColumn() == 0;
        foreach (_; 0 .. 3)
        {
            if (!result)
                break;
            reader.read(false);
            result = reader.isHyphenCharacter();
        }
        if (!reader.isEndOfLine())
        {
            reader.read(false);
            while (reader.isWhiteSpace())
                reader.read(false);
        }
        return result && reader.isEndOfLine();
    }

    private static dstring decode(const(ubyte)[] bytes, string encoding)
    {
        import std.conv : to;
        import std.uni : sicmp;
        import std.utf : validate;

        if (encoding.length && (sicmp(encoding, "UTF-8") == 0 || sicmp(encoding, "UTF8") == 0))
        {
            auto text = cast(const(char)[]) bytes;
            validate(text);
            return text.to!dstring;
        }
        // ISO-8859-1: every byte is the code point of the same value.
        auto result = new dchar[bytes.length];
        foreach (index, b; bytes)
            result[index] = cast(dchar) b;
        return result.idup;
    }
}

// Port of OriginTrackedPropertiesLoader.CharacterReader over decoded text, with LineNumberReader's line-ending
// normalization (`\r\n` and `\r` read as `\n`).
private struct CharacterReader
{
    dstring text;
    size_t position;
    int lineNumber;
    int columnNumber = -1;
    bool escaped;
    long character;
    long lastLineCommentPrefixCharacter;

    this(dstring text) pure nothrow @nogc
    {
        this.text = text;
    }

    long next() pure nothrow @nogc
    {
        if (position >= text.length)
            return -1;
        dchar ch = text[position++];
        if (ch == '\r')
        {
            if (position < text.length && text[position] == '\n')
                position++;
            ch = '\n';
        }
        if (ch == '\n')
            lineNumber++;
        return ch;
    }

    bool read(bool readEscaped = true)
    {
        escaped = false;
        character = next();
        columnNumber++;
        if (columnNumber == 0)
            skipWhitespace();
        if (readEscaped && character == '\\')
        {
            escaped = true;
            readEscapedCharacter();
        }
        else if (character == '\n')
            columnNumber = -1;
        return !isEndOfFile();
    }

    void skipWhitespace() pure nothrow @nogc
    {
        while (isWhiteSpace())
        {
            character = next();
            columnNumber++;
        }
    }

    void skipComment() pure nothrow @nogc
    {
        while (character != '\n' && character != -1)
            character = next();
        columnNumber = -1;
    }

    void readEscapedCharacter()
    {
        enum escapes = "trnf";
        enum replacements = "\t\r\n\f";
        character = next();
        foreach (index, escape; escapes)
        {
            if (character == escape)
            {
                character = replacements[index];
                return;
            }
        }
        if (character == '\n')
        {
            columnNumber = -1;
            read();
        }
        else if (character == 'u')
            readUnicode();
    }

    void readUnicode()
    {
        character = 0;
        foreach (_; 0 .. 4)
        {
            const digit = next();
            if (digit >= '0' && digit <= '9')
                character = (character << 4) + digit - '0';
            else if (digit >= 'a' && digit <= 'f')
                character = (character << 4) + digit - 'a' + 10;
            else if (digit >= 'A' && digit <= 'F')
                character = (character << 4) + digit - 'A' + 10;
            else
                throw new IllegalStateException("Malformed \\uxxxx encoding.");
        }
    }

    bool isWhiteSpace() const pure nothrow @nogc
    {
        return !escaped && (character == ' ' || character == '\t' || character == '\f');
    }

    bool isEndOfFile() const pure nothrow @nogc
    {
        return character == -1;
    }

    bool isEndOfLine() const pure nothrow @nogc
    {
        return character == -1 || (!escaped && character == '\n');
    }

    bool isListDelimiter() const pure nothrow @nogc
    {
        return !escaped && character == ',';
    }

    bool isPropertyDelimiter() const pure nothrow @nogc
    {
        return !escaped && (character == '=' || character == ':');
    }

    dchar getCharacter() const pure nothrow @nogc
    {
        return cast(dchar) character;
    }

    TextResourceOrigin.Location getLocation() const pure nothrow @nogc
    {
        // LineNumberReader has counted the newline that ends a line when the current character is that newline.
        return TextResourceOrigin.Location(lineNumber, columnNumber);
    }

    bool isSameLastLineCommentPrefix() const pure nothrow @nogc
    {
        return lastLineCommentPrefixCharacter == character;
    }

    bool isCommentPrefixCharacter() const pure nothrow @nogc
    {
        return !escaped && (character == '#' || character == '!');
    }

    bool isHyphenCharacter() const pure nothrow @nogc
    {
        return character == '-';
    }
}

/// Reads YAML documents into flattened, origin-tracked properties, as Boot's `OriginTrackedYamlLoader` with
/// spring-beans' `YamlProcessor` flattening: nested keys join with `.`, list items take `[i]`, keys written as
/// `[a.b]` keep their dots, and empty or `null` values, empty lists and empty maps all read as `""`.
final class OriginTrackedYamlLoader
{
    import flint.boot.internal.yaml : YamlNode, parseYaml;

    private string resource;
    private const(ubyte)[] content;

    /// A loader for `content`, the bytes of the resource described by `resource`.
    this(string resource, const(ubyte)[] content) pure nothrow
    {
        this.resource = resource;
        this.content = content;
    }

    /// The non-empty documents, in order.
    Document[] load()
    {
        import std.utf : validate;

        auto text = cast(const(char)[]) content;
        validate(text);
        Document[] documents;
        foreach (node; parseYaml(text.idup))
        {
            if (node is null)
                continue;
            auto document = new Document;
            flatten(document, "", node);
            if (!document.isEmpty())
                documents ~= document;
        }
        return documents;
    }

    private void flatten(Document document, string path, YamlNode node)
    {
        import std.conv : to;

        final switch (node.kind)
        {
        case YamlNode.Kind.mapping:
            if (node.keys.length == 0 && path.length)
            {
                document.put(path, tracked("", node));
                return;
            }
            foreach (index, key; node.keys)
            {
                string child;
                if (path.length == 0)
                    child = key;
                else if (key.length && key[0] == '[')
                    child = path ~ key;
                else
                    child = path ~ "." ~ key;
                flatten(document, child, node.items[index]);
            }
            return;
        case YamlNode.Kind.sequence:
            if (node.items.length == 0)
            {
                document.put(path, tracked("", node));
                return;
            }
            foreach (index, item; node.items)
                flatten(document, path ~ "[" ~ index.to!string ~ "]", item);
            return;
        case YamlNode.Kind.scalar:
            document.put(path, tracked(node.value, node));
            return;
        case YamlNode.Kind.empty:
            document.put(path, tracked("", node));
            return;
        }
    }

    private OriginTrackedValue tracked(string value, YamlNode node) pure
    {
        return OriginTrackedValue.of(value, new TextResourceOrigin(resource,
                TextResourceOrigin.Location(node.line, node.column)));
    }
}
