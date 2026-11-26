/*
 * Ported from Jackson (jackson-core) 3.1.8, https://github.com/FasterXML/jackson-core,
 * tag jackson-core-3.1.8: src/main/java/tools/jackson/core/{JsonToken,JsonTokenId,
 * JacksonException,TokenStreamLocation,TokenStreamContext,JsonPointer,JsonGenerator,JsonParser,
 * PrettyPrinter,ObjectWriteContext,ObjectReadContext,StreamReadFeature,
 * StreamWriteFeature,StreamReadConstraints,StreamWriteConstraints}.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated to D (rulebook v2). The streaming
 * types keep Jackson 3's names and fluent signatures; Java's null token is
 * JsonToken.NOT_AVAILABLE, and BigInteger, BigDecimal, binary, Reader and
 * OutputStream overloads wait for flint.java (see docs/spring/phase1/third-party.md).
 */

/// Jackson's streaming API: tokens, the generator and parser abstractions, and their features.
module flint.jackson.core;

import std.typecons : Nullable;

import flint.engine.aot.any : Any;

@safe:

/**
 * Enumeration for basic token types used for returning results of parsing JSON
 * content.
 *
 * Java returns `null` from `JsonParser.nextToken()` at the end of input and
 * from `currentToken()` before the first token; a D enum has no null, so Flint
 * returns `NOT_AVAILABLE`, which a blocking parser never otherwise reports.
 */
enum JsonToken
{
    /// No token is available: before the first token, at the end of input, or after `close()`.
    NOT_AVAILABLE,
    /// START_OBJECT is returned when encountering '{' which signals starting of an Object value.
    START_OBJECT,
    /// END_OBJECT is returned when encountering '}' which signals ending of an Object value.
    END_OBJECT,
    /// START_ARRAY is returned when encountering '[' which signals starting of an Array value.
    START_ARRAY,
    /// END_ARRAY is returned when encountering ']' which signals ending of an Array value.
    END_ARRAY,
    /// PROPERTY_NAME is returned when a String token is encountered as a property name.
    PROPERTY_NAME,
    /// Placeholder token returned when the input source has a concept of embedded Object values.
    VALUE_EMBEDDED_OBJECT,
    /// VALUE_STRING is returned when a String token is encountered in value context.
    VALUE_STRING,
    /// VALUE_NUMBER_INT is returned when an integer numeric token is encountered in value context.
    VALUE_NUMBER_INT,
    /// VALUE_NUMBER_FLOAT is returned when a numeric token other than integer is encountered.
    VALUE_NUMBER_FLOAT,
    /// VALUE_TRUE is returned when encountering literal "true" in value context.
    VALUE_TRUE,
    /// VALUE_FALSE is returned when encountering literal "false" in value context.
    VALUE_FALSE,
    /// VALUE_NULL is returned when encountering literal "null" in value context.
    VALUE_NULL,
}

/// The `JsonTokenId` constant of a token, as `JsonToken.id()` returns it.
int id(JsonToken token) pure nothrow @nogc
{
    static immutable int[JsonToken.max + 1] ids = [
        JsonTokenId.ID_NOT_AVAILABLE, JsonTokenId.ID_START_OBJECT, JsonTokenId.ID_END_OBJECT,
        JsonTokenId.ID_START_ARRAY, JsonTokenId.ID_END_ARRAY, JsonTokenId.ID_PROPERTY_NAME,
        JsonTokenId.ID_EMBEDDED_OBJECT, JsonTokenId.ID_STRING, JsonTokenId.ID_NUMBER_INT,
        JsonTokenId.ID_NUMBER_FLOAT, JsonTokenId.ID_TRUE, JsonTokenId.ID_FALSE, JsonTokenId.ID_NULL,
    ];
    return ids[token];
}

/// The token's fixed textual representation (`{`, `true`, ...), or null for variable tokens.
string asString(JsonToken token) pure nothrow @nogc
{
    switch (token)
    {
    case JsonToken.START_OBJECT:
        return "{";
    case JsonToken.END_OBJECT:
        return "}";
    case JsonToken.START_ARRAY:
        return "[";
    case JsonToken.END_ARRAY:
        return "]";
    case JsonToken.VALUE_TRUE:
        return "true";
    case JsonToken.VALUE_FALSE:
        return "false";
    case JsonToken.VALUE_NULL:
        return "null";
    default:
        return null;
    }
}

/// Whether the token is `VALUE_NUMBER_INT` or `VALUE_NUMBER_FLOAT`.
bool isNumeric(JsonToken token) pure nothrow @nogc
{
    return token == JsonToken.VALUE_NUMBER_INT || token == JsonToken.VALUE_NUMBER_FLOAT;
}

/// Whether the token starts a structured value (`START_OBJECT` or `START_ARRAY`).
bool isStructStart(JsonToken token) pure nothrow @nogc
{
    return token == JsonToken.START_OBJECT || token == JsonToken.START_ARRAY;
}

/// Whether the token ends a structured value (`END_OBJECT` or `END_ARRAY`).
bool isStructEnd(JsonToken token) pure nothrow @nogc
{
    return token == JsonToken.END_OBJECT || token == JsonToken.END_ARRAY;
}

/// Whether the token is a scalar value: a string, number, boolean, null or embedded object.
bool isScalarValue(JsonToken token) pure nothrow @nogc
{
    return token >= JsonToken.VALUE_EMBEDDED_OBJECT;
}

/// Whether the token is `VALUE_TRUE` or `VALUE_FALSE`.
bool isBoolean(JsonToken token) pure nothrow @nogc
{
    return token == JsonToken.VALUE_TRUE || token == JsonToken.VALUE_FALSE;
}

/// Interface defining constants used by `JsonToken.id()`, for switch statements.
struct JsonTokenId
{
    /// Id used to represent `JsonToken.NOT_AVAILABLE`.
    enum int ID_NOT_AVAILABLE = -1;
    /// Id used to represent the case where no `JsonToken` is available.
    enum int ID_NO_TOKEN = 0;
    /// Id used to represent `JsonToken.START_OBJECT`.
    enum int ID_START_OBJECT = 1;
    /// Id used to represent `JsonToken.END_OBJECT`.
    enum int ID_END_OBJECT = 2;
    /// Id used to represent `JsonToken.START_ARRAY`.
    enum int ID_START_ARRAY = 3;
    /// Id used to represent `JsonToken.END_ARRAY`.
    enum int ID_END_ARRAY = 4;
    /// Id used to represent `JsonToken.PROPERTY_NAME`.
    enum int ID_PROPERTY_NAME = 5;
    /// Id used to represent `JsonToken.VALUE_STRING`.
    enum int ID_STRING = 6;
    /// Id used to represent `JsonToken.VALUE_NUMBER_INT`.
    enum int ID_NUMBER_INT = 7;
    /// Id used to represent `JsonToken.VALUE_NUMBER_FLOAT`.
    enum int ID_NUMBER_FLOAT = 8;
    /// Id used to represent `JsonToken.VALUE_TRUE`.
    enum int ID_TRUE = 9;
    /// Id used to represent `JsonToken.VALUE_FALSE`.
    enum int ID_FALSE = 10;
    /// Id used to represent `JsonToken.VALUE_NULL`.
    enum int ID_NULL = 11;
    /// Id used to represent `JsonToken.VALUE_EMBEDDED_OBJECT`.
    enum int ID_EMBEDDED_OBJECT = 12;
}

/**
 * Object that encapsulates Location information used for reporting parsing (or
 * potentially generation) errors, as well as current location within input
 * streams.
 */
final class TokenStreamLocation
{
    /// Shared immutable "N/A location" that can be returned to indicate that no location information is available.
    static TokenStreamLocation NA() pure nothrow
    {
        return new TokenStreamLocation(-1, -1, -1, -1);
    }

    private long totalBytes;
    private long totalChars;
    private int lineNr;
    private int columnNr;

    ///
    this(long totalBytes, long totalChars, int lineNr, int columnNr) pure nothrow @nogc
    {
        this.totalBytes = totalBytes;
        this.totalChars = totalChars;
        this.lineNr = lineNr;
        this.columnNr = columnNr;
    }

    /// One-based line number, or -1 when unknown.
    int getLineNr() const pure nothrow @nogc
    {
        return lineNr;
    }

    /// One-based column number, or -1 when unknown.
    int getColumnNr() const pure nothrow @nogc
    {
        return columnNr;
    }

    /// Character offset from the start of input, or -1 when unknown.
    long getCharOffset() const pure nothrow @nogc
    {
        return totalChars;
    }

    /// Byte offset from the start of input, or -1 when unknown.
    long getByteOffset() const pure nothrow @nogc
    {
        return totalBytes;
    }

    /// Description of the location: `line: 1, column: 15`.
    string offsetDescription() const pure nothrow
    {
        import flint.engine.aot.text : decimal;

        if (lineNr < 0)
            return "UNKNOWN";
        return "line: " ~ decimal(lineNr) ~ ", column: " ~ decimal(columnNr);
    }

    override string toString() const pure nothrow
    {
        return "[Source: UNKNOWN; " ~ offsetDescription() ~ "]";
    }
}

/**
 * Base class for all Jackson-produced checked exceptions.
 *
 * Jackson 3 makes this unchecked (`RuntimeException`). It derives from D's
 * `Exception` until `flint.java.lang.RuntimeException` lands, which keeps
 * every `catch (Exception)` working across that change.
 */
class JacksonException : Exception
{
    /// Location of the problem, or null.
    protected TokenStreamLocation _location;
    /// Message without the location suffix.
    protected string _originalMessage;

    ///
    this(string msg, TokenStreamLocation loc = null, Throwable rootCause = null,
            string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(loc is null ? msg : msg ~ "\n at " ~ describe(loc), file, line, rootCause);
        _originalMessage = msg;
        _location = loc;
    }

    private static string describe(TokenStreamLocation loc) pure nothrow
    {
        if (loc.getLineNr() < 0)
            return "[Source: UNKNOWN; line: -1, column: -1]";
        return loc.toString();
    }

    /// Accessor for location information related to position within input or output, if available.
    TokenStreamLocation getLocation() pure nothrow @nogc
    {
        return _location;
    }

    /// Method that allows accessing the original "message" argument, without additional decorations.
    string getOriginalMessage() const pure nothrow @nogc
    {
        return _originalMessage;
    }

    /// Accessor for the underlying cause, if any.
    Throwable getCause() pure nothrow @nogc
    {
        return next;
    }
}

/**
 * Shared base class for streaming processing contexts used during reading and
 * writing of token streams using Streaming API. This context is also exposed to
 * applications: context object can be used by applications to get an idea of
 * relative position of the parser/generator within content being processed.
 */
abstract class TokenStreamContext
{
    /// Indicator for an Array context.
    enum int TYPE_ARRAY = 1;
    /// Indicator for an Object context.
    enum int TYPE_OBJECT = 2;
    /// Indicator for the root context (not within an Object or Array).
    enum int TYPE_ROOT = 0;

    /// Type of this context: `TYPE_ROOT`, `TYPE_ARRAY` or `TYPE_OBJECT`.
    protected int _type;
    /// Index of the currently processed entry; starts at -1 for "before first entry".
    protected int _index;
    /// Name of the property of which value is to be handled, or null.
    protected string _currentName;
    /// The value being processed in this context, as the databind layer sets it.
    protected Object _currentValue;

    /// Accessor for finding parent context of this context; will return null for root context.
    TokenStreamContext getParent() pure nothrow @nogc
    {
        return _parent;
    }

    /// Whether this context is an Array.
    final bool inArray() const pure nothrow @nogc
    {
        return _type == TYPE_ARRAY;
    }

    /// Whether this context is the root.
    final bool inRoot() const pure nothrow @nogc
    {
        return _type == TYPE_ROOT;
    }

    /// Whether this context is an Object.
    final bool inObject() const pure nothrow @nogc
    {
        return _type == TYPE_OBJECT;
    }

    /// Simple accessor for the type of this context: "ROOT", "ARRAY" or "OBJECT".
    final string typeDesc() const pure nothrow @nogc
    {
        switch (_type)
        {
        case TYPE_ROOT:
            return "root";
        case TYPE_ARRAY:
            return "Array";
        case TYPE_OBJECT:
            return "Object";
        default:
            return "?";
        }
    }

    /// Number of entries that are complete and started.
    final int getEntryCount() const pure nothrow @nogc
    {
        return _index + 1;
    }

    /// Index of the currently processed entry, if any; -1 before the first.
    final int getCurrentIndex() const pure nothrow @nogc
    {
        return _index < 0 ? 0 : _index;
    }

    /// Whether this context has a current index.
    bool hasCurrentIndex() const pure nothrow @nogc
    {
        return _index >= 0;
    }

    /// Whether this context has a current property name.
    bool hasCurrentName() const pure nothrow @nogc
    {
        return _currentName !is null;
    }

    /// Name of the current property, if any: the name for `PROPERTY_NAME` and its value.
    string currentName() const pure nothrow @nogc
    {
        return _currentName;
    }

    /// The value currently associated with this context, as set by databind.
    Object currentValue() pure nothrow @nogc
    {
        return _currentValue;
    }

    /// Assign the value currently associated with this context.
    void assignCurrentValue(Object v) pure nothrow @nogc
    {
        _currentValue = v;
    }

    /// Whether this object or array context has advanced to a path segment.
    bool hasPathSegment() const pure nothrow @nogc
    {
        if (inObject())
            return hasCurrentName();
        return inArray() && hasCurrentIndex();
    }

    /// The path from the root as a JSON Pointer, for reporting.
    final JsonPointer pathAsPointer()
    {
        return JsonPointer.forPath(this, false);
    }

    /// The path from the root, optionally prefixed by the root value's index.
    final JsonPointer pathAsPointer(bool includeRoot)
    {
        return JsonPointer.forPath(this, includeRoot);
    }

    /// The enclosing context, maintained by subclasses.
    protected TokenStreamContext _parent;
}

// D-JACKSON-8: construct the canonical Java exception when its leaf is available.
private Exception invalidArgument(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
{
    return new Exception(message, file, line);
}

/// A compiled JSON Pointer. Each segment shares the original expression.
class JsonPointer
{
    /// Separates pointer segments.
    enum char SEPARATOR = '/';
    /// Starts an escape sequence.
    enum char ESC = '~';
    /// Encoded slash.
    enum string ESC_SLASH = "~1";
    /// Encoded tilde.
    enum string ESC_TILDE = "~0";

    protected this() pure nothrow @nogc
    {
    }

    /// Compile a pointer expression. An empty expression selects the current node.
    static JsonPointer compile(string expression)
    {
        if (expression.length == 0)
            return empty();
        if (expression[0] != SEPARATOR)
            throw invalidArgument(join("Invalid input: JSON Pointer expression must start with '/': \"",
                    expression, "\""));

        auto result = empty();
        size_t end = expression.length;
        foreach_reverse (offset, marker; expression)
        {
            if (marker != SEPARATOR)
                continue;
            const propertyName = decodePointerProperty(expression[offset + 1 .. end]);
            result = ParsedJsonPointer.create(expression[offset .. $], propertyName,
                    readPointerIndex(propertyName), result);
            end = offset;
        }
        return result;
    }

    /// Compile a pointer from its textual representation.
    static JsonPointer valueOf(string expression)
    {
        return compile(expression);
    }

    /// The shared empty pointer.
    static JsonPointer empty() nothrow @nogc
    {
        import flint.engine.aot.objects : statelessInstance;

        return statelessInstance!EmptyJsonPointer();
    }

    /// A pointer to the current stream position, optionally including the root value's index.
    static JsonPointer forPath(TokenStreamContext context, bool includeRoot)
    {
        if (context is null)
            return empty();
        if (!context.hasPathSegment() && !(includeRoot && context.inRoot() && context.hasCurrentIndex()))
            context = context.getParent();
        return compile(contextExpression(context, includeRoot));
    }

    /// Length of this expression in Java UTF-16 code units (R14).
    int length() pure nothrow @nogc
    {
        int units;
        foreach (value; toString())
        {
            if (value < 0x80 || value >= 0xC0)
                ++units;
            if (value >= 0xF0 && value <= 0xF4)
                ++units;
        }
        return units;
    }

    /// Whether this pointer selects the current node.
    bool matches() pure nothrow @nogc
    {
        return tail() is null;
    }

    /// The current segment's decoded property name, or null for the empty pointer.
    string getMatchingProperty() const pure nothrow @nogc
    {
        return null;
    }

    /// The current segment's array index, or -1 when the segment denotes no array element.
    int getMatchingIndex() const pure nothrow @nogc
    {
        return -1;
    }

    /// Whether the current segment can select an object property.
    bool mayMatchProperty() const pure nothrow @nogc
    {
        return getMatchingProperty() !is null;
    }

    /// Whether the current segment can select an array element.
    bool mayMatchElement() const pure nothrow @nogc
    {
        return getMatchingIndex() >= 0;
    }

    /// Append the suffix, preserving any empty segment at the end of this pointer.
    JsonPointer append(JsonPointer suffix)
    {
        auto emptyPointer = empty();
        if (this is emptyPointer)
            return suffix;
        if (suffix is emptyPointer)
            return this;
        if (suffix is null)
            throw invalidArgument("Cannot append a null JSON Pointer"); // D-JACKSON-8
        return compile(join(toString(), suffix.toString(), null));
    }

    /// Append one property segment, escaping slashes and tildes. A null name leaves this pointer intact.
    JsonPointer appendProperty(string propertyName)
    {
        if (propertyName is null)
            return this;
        return compile(appendEscapedProperty(toString(), propertyName));
    }

    /// Append one nonnegative index segment.
    JsonPointer appendIndex(int index)
    {
        import flint.engine.aot.text : decimal;

        if (index < 0)
            throw invalidArgument("Negative index cannot be appended");
        return compile(join(toString(), "/", decimal(index)));
    }

    /// Whether the current segment selects this property.
    bool matchesProperty(string name) const pure nothrow @nogc
    {
        const propertyName = getMatchingProperty();
        return propertyName !is null && name !is null && propertyName == name;
    }

    /// Whether the current segment selects this index.
    bool matchesElement(int index) const pure nothrow @nogc
    {
        return index >= 0 && getMatchingIndex() == index;
    }

    /// The remaining pointer after a matching property, or null when the property differs.
    JsonPointer matchProperty(string name) pure nothrow @nogc
    {
        return matchesProperty(name) ? tail() : null;
    }

    /// The remaining pointer after a matching array index, or null when the index differs.
    JsonPointer matchElement(int index) pure nothrow @nogc
    {
        return matchesElement(index) ? tail() : null;
    }

    /// The remaining pointer after removing the current segment, or null for the empty pointer.
    JsonPointer tail() pure nothrow @nogc
    {
        return null;
    }

    /// The existing final segment, or null when this pointer is empty.
    JsonPointer last() pure nothrow @nogc
    {
        JsonPointer previous;
        auto current = this;
        while (true)
        {
            auto next = current.tail();
            if (next is null)
                return previous;
            previous = current;
            current = next;
        }
    }

    /// The pointer without its final segment, or null when this pointer is empty.
    JsonPointer head()
    {
        auto leaf = last();
        if (leaf is null)
            return null;
        auto terminator = leaf.tail();
        const suffixLength = leaf.toString().length;
        ParsedJsonPointer prefix;
        ParsedJsonPointer previous;
        for (auto current = this; current !is leaf; current = current.tail())
        {
            const expression = current.toString();
            auto segment = ParsedJsonPointer.create(expression[0 .. $ - suffixLength],
                    current.getMatchingProperty(), current.getMatchingIndex(), terminator);
            if (previous is null)
                prefix = segment;
            else
                previous.remainder = segment;
            previous = segment;
        }
        return prefix is null ? terminator : prefix;
    }

    /// Whether both pointers have the same expression (R11).
    bool equals(Object other) pure nothrow @nogc
    {
        auto pointer = cast(JsonPointer) other;
        return pointer !is null && (pointer is this || toString() == pointer.toString());
    }

    /// Java string hash of the expression, with Jackson's -1 sentinel for zero (R11).
    int hashCode() pure nothrow @nogc
    {
        import flint.engine.aot.text : decodeUtf8;

        const expression = toString();
        uint hash;
        size_t i;
        while (i < expression.length)
        {
            const codePoint = decodeUtf8(expression, i);
            if (codePoint <= 0xFFFF)
                hash = 31 * hash + codePoint;
            else
            {
                const supplementary = codePoint - 0x10000;
                hash = 31 * hash + (0xD800 | (supplementary >> 10));
                hash = 31 * hash + (0xDC00 | (supplementary & 0x3FF));
            }
        }
        return hash == 0 ? -1 : cast(int) hash;
    }

    override bool opEquals(Object other) pure nothrow @nogc
    {
        return equals(other);
    }

    override size_t toHash() pure nothrow @nogc
    {
        return cast(uint) hashCode();
    }

    /// The original spelling of the pointer expression.
    override string toString() pure nothrow @nogc
    {
        return "";
    }
}

private final class EmptyJsonPointer : JsonPointer
{
}

private final class ParsedJsonPointer : JsonPointer
{
    private string expression;
    private string propertyName;
    private int index;
    private JsonPointer remainder;
    private JsonPointer cachedHead;

    static ParsedJsonPointer create(string expression, string propertyName, int index, JsonPointer tail) pure nothrow
    {
        return new ParsedJsonPointer(expression, propertyName, index, tail);
    }

    this(string expression, string propertyName, int index, JsonPointer remainder) pure nothrow @nogc
    {
        this.expression = expression;
        this.propertyName = propertyName;
        this.index = index;
        this.remainder = remainder;
    }

    override string getMatchingProperty() const pure nothrow @nogc
    {
        return propertyName;
    }

    override int getMatchingIndex() const pure nothrow @nogc
    {
        return index;
    }

    override JsonPointer tail() pure nothrow @nogc
    {
        return remainder;
    }

    override JsonPointer head()
    {
        import core.atomic : MemoryOrder, atomicLoad, atomicStore;

        auto prefix = atomicLoad!(MemoryOrder.acq)(cachedHead);
        if (prefix is null)
        {
            // As with Jackson's volatile cache, concurrent callers may build equivalent prefixes.
            prefix = super.head();
            atomicStore!(MemoryOrder.rel)(cachedHead, prefix);
        }
        return prefix;
    }

    override string toString() pure nothrow @nogc
    {
        return expression;
    }
}

private char[] jsonTextBuffer(size_t length) pure nothrow
{
    return new char[length];
}

// A strongly pure builder publishes one immutable diagnostic to its caller.
private char[] join(string first, string second, string third, string fourth = null, string fifth = null) pure nothrow
{
    const string[5] parts = [first, second, third, fourth, fifth];
    auto message = jsonTextBuffer(first.length + second.length + third.length + fourth.length + fifth.length);
    size_t offset;
    foreach (part; parts)
    {
        message[offset .. offset + part.length] = part;
        offset += part.length;
    }
    return message;
}

private char[] appendEscapedProperty(string prefix, string propertyName) pure nothrow
{
    auto expression = jsonTextBuffer(prefix.length + pointerPropertyWidth(propertyName));
    expression[0 .. prefix.length] = prefix;
    size_t end = expression.length;
    writePointerProperty(expression, end, propertyName);
    return expression;
}

private size_t pointerPropertyWidth(string propertyName) pure nothrow @nogc
{
    size_t width = 1 + propertyName.length;
    foreach (value; propertyName)
        if (value == JsonPointer.SEPARATOR || value == JsonPointer.ESC)
            ++width;
    return width;
}

private void writePointerProperty(scope char[] expression, ref size_t end, string propertyName) pure nothrow @nogc
{
    foreach_reverse (value; propertyName)
    {
        if (value == JsonPointer.SEPARATOR || value == JsonPointer.ESC)
        {
            expression[--end] = value == JsonPointer.SEPARATOR ? '1' : '0';
            expression[--end] = JsonPointer.ESC;
        }
        else
            expression[--end] = value;
    }
    expression[--end] = JsonPointer.SEPARATOR;
}

private string contextExpression(TokenStreamContext context, bool includeRoot) pure nothrow
{
    size_t capacity;
    for (auto current = context; current !is null; current = current.getParent())
    {
        if (current.inObject())
            capacity += pointerPropertyWidth(current.currentName());
        else if (current.inArray() || includeRoot)
            capacity += 11; // The separator and up to ten digits of a nonnegative int.
    }
    if (capacity == 0)
        return "";

    auto expression = jsonTextBuffer(capacity);
    size_t end = capacity;
    for (auto current = context; current !is null; current = current.getParent())
    {
        if (current.inObject())
            writePointerProperty(expression, end, current.currentName());
        else if (current.inArray() || includeRoot)
        {
            auto index = cast(uint) current.getCurrentIndex();
            do
            {
                expression[--end] = cast(char)('0' + index % 10);
                index /= 10;
            }
            while (index != 0);
            expression[--end] = JsonPointer.SEPARATOR;
        }
    }
    return expression[end .. $].idup;
}

private int readPointerIndex(string propertyName) pure nothrow @nogc
{
    if (propertyName.length == 0 || propertyName.length > 10)
        return -1;
    if (propertyName.length > 1 && propertyName[0] == '0')
        return -1;

    long index;
    foreach (digit; propertyName)
    {
        if (digit < '0' || digit > '9')
            return -1;
        index = index * 10 + digit - '0';
    }
    return index <= int.max ? cast(int) index : -1;
}

private string decodePointerProperty(string propertyName) pure nothrow
{
    size_t first;
    for (; first + 1 < propertyName.length; ++first)
    {
        const next = propertyName[first + 1];
        if (propertyName[first] == JsonPointer.ESC && (next == '0' || next == '1'))
            break;
    }
    if (first + 1 >= propertyName.length)
        return propertyName;
    return decodeEscapedPointerProperty(propertyName, first);
}

// A strongly pure function returns a fresh buffer that can become an immutable string.
private char[] decodeEscapedPointerProperty(string propertyName, size_t first) pure nothrow
{
    auto decoded = jsonTextBuffer(propertyName.length);
    decoded[0 .. first] = propertyName[0 .. first];
    size_t written = first;
    for (size_t i = first; i < propertyName.length; ++i)
    {
        char value = propertyName[i];
        if (value == JsonPointer.ESC && i + 1 < propertyName.length)
        {
            const escaped = propertyName[i + 1];
            if (escaped == '0' || escaped == '1')
            {
                value = escaped == '0' ? JsonPointer.ESC : JsonPointer.SEPARATOR;
                ++i;
            }
        }
        decoded[written++] = value;
    }
    return decoded[0 .. written];
}

/**
 * Interface for objects that implement pretty printer functionality, such as
 * indentation. Pretty printers are used to add white space in output JSON
 * content, to make results more human-readable. Usually this means things like
 * adding linefeeds and indentation.
 */
interface PrettyPrinter
{
    /// Called after a root-level value has been completely output, and before another value is to be output.
    void writeRootValueSeparator(JsonGenerator g);
    /// Called when an Object value is to be output, before any properties are output.
    void writeStartObject(JsonGenerator g);
    /// Called after an Object value has been completely output (minus closing curly bracket).
    void writeEndObject(JsonGenerator g, int nrOfEntries);
    /// Called after an Object entry (property name + value) has been completely output, and before another entry.
    void writeObjectEntrySeparator(JsonGenerator g);
    /// Called after an Object property name has been output, but before the value is output.
    void writeObjectNameValueSeparator(JsonGenerator g);
    /// Called when an Array value is to be output, before any member/child values are output.
    void writeStartArray(JsonGenerator g);
    /// Called after an Array value has been completely output (minus closing bracket).
    void writeEndArray(JsonGenerator g, int nrOfValues);
    /// Called after an array value has been completely output, and before another value is to be output.
    void writeArrayValueSeparator(JsonGenerator g);
    /// Called after array start marker has been output, and right before the first value is to be output.
    void beforeArrayValues(JsonGenerator g);
    /// Called after object start marker has been output, and right before the Property Name of the first property.
    void beforeObjectEntries(JsonGenerator g);
}

/**
 * Defines API for accessing configuration and state exposed by higher level
 * databind functionality during write (Object to token stream serialization)
 * process. Databind implements it; low-level use has the `empty()` instance.
 */
interface ObjectWriteContext
{
    /// Pretty printer to use for a new generator, or null for compact output.
    PrettyPrinter getPrettyPrinter();

    /// Whether the generator should pretty-print (`getPrettyPrinter() !is null`).
    bool hasPrettyPrinter();

    /// The default write context: compact output and default features.
    static ObjectWriteContext empty() pure nothrow
    {
        return new Base();
    }

    /// Default implementation with no pretty printer, to extend.
    static class Base : ObjectWriteContext
    {
        PrettyPrinter getPrettyPrinter()
        {
            return null;
        }

        /// Whether the generator should pretty-print (`getPrettyPrinter() !is null`).
        bool hasPrettyPrinter()
        {
            return getPrettyPrinter() !is null;
        }
    }
}

/**
 * Defines API for accessing configuration and state exposed by higher level
 * databind functionality during read (token stream to Object deserialization)
 * process.
 */
interface ObjectReadContext
{
    /// Stream read constraints in effect.
    StreamReadConstraints streamReadConstraints();

    /// The default read context.
    static ObjectReadContext empty() pure nothrow
    {
        return new Base();
    }

    /// Default implementation with default constraints, to extend.
    static class Base : ObjectReadContext
    {
        /// The stream read constraints new parsers receive.
        StreamReadConstraints streamReadConstraints()
        {
            return StreamReadConstraints.defaults();
        }
    }
}

/**
 * The constraints to use for streaming reads: used to guard against malicious
 * input by preventing processing of "too big" input constructs (values,
 * structures). Values are Jackson 3.1's defaults.
 */
struct StreamReadConstraints
{
    /// Default setting for maximum depth: 500 levels.
    enum int DEFAULT_MAX_DEPTH = 500;
    /// Default setting for maximum number length: 1000 characters.
    enum int DEFAULT_MAX_NUM_LEN = 1000;
    /// Default setting for maximum string length: 100 million characters.
    enum int DEFAULT_MAX_STRING_LEN = 100_000_000;
    /// Default setting for maximum name length: 50,000 characters.
    enum int DEFAULT_MAX_NAME_LEN = 50_000;

    /// Maximum nesting depth.
    int maxNestingDepth = DEFAULT_MAX_DEPTH;
    /// Maximum number of characters of a number token.
    int maxNumberLength = DEFAULT_MAX_NUM_LEN;
    /// Maximum length of a String value.
    int maxStringLength = DEFAULT_MAX_STRING_LEN;
    /// Maximum length of a property name.
    int maxNameLength = DEFAULT_MAX_NAME_LEN;

    /// The default constraints.
    static StreamReadConstraints defaults() pure nothrow @nogc
    {
        return StreamReadConstraints.init;
    }
}

/**
 * The constraints to use for streaming writes: used to guard against problematic
 * output by preventing processing of "too big" output constructs (currently only
 * the nesting depth, which also stops a cyclic object graph before the stack
 * overflows). Values are Jackson 3.1's defaults.
 *
 * Jackson's process-wide `overrideDefaultStreamWriteConstraints` is not ported:
 * Flint framework packages keep no mutable module-level state; configure a
 * factory with `JsonFactoryBuilder.streamWriteConstraints` instead.
 */
struct StreamWriteConstraints
{
    /// Default setting for maximum depth: 500 levels.
    enum int DEFAULT_MAX_DEPTH = 500;

    private int _maxNestingDepth = DEFAULT_MAX_DEPTH;

    /// Builder for `StreamWriteConstraints`.
    static final class Builder
    {
        private int _maxNestingDepth;

        private this(int maxNestingDepth) pure nothrow @nogc
        {
            _maxNestingDepth = maxNestingDepth;
        }

        /**
         * Sets the maximum nesting depth. The depth is a count of objects and
         * arrays that have not been closed, `{` and `[` respectively.
         *
         * Throws: `Exception` if `maxNestingDepth` is negative (Jackson's
         * `IllegalArgumentException`; jackson-core does not depend on flint.java).
         */
        Builder maxNestingDepth(int maxNestingDepth) pure
        {
            if (maxNestingDepth < 0)
                throw invalidArgument("Cannot set maxNestingDepth to a negative value");
            _maxNestingDepth = maxNestingDepth;
            return this;
        }

        /// The constraints.
        StreamWriteConstraints build() const pure nothrow @nogc
        {
            return StreamWriteConstraints(_maxNestingDepth);
        }
    }

    private this(int maxNestingDepth) pure nothrow @nogc
    {
        _maxNestingDepth = maxNestingDepth;
    }

    /// A builder with the default settings.
    static Builder builder() pure nothrow
    {
        return new Builder(DEFAULT_MAX_DEPTH);
    }

    /// The default constraints.
    static StreamWriteConstraints defaults() pure nothrow @nogc
    {
        return StreamWriteConstraints.init;
    }

    /// A builder initialized with these constraints.
    Builder rebuild() const pure nothrow
    {
        return new Builder(_maxNestingDepth);
    }

    /// Maximum nesting depth allowed.
    int getMaxNestingDepth() const pure nothrow @nogc
    {
        return _maxNestingDepth;
    }

    /**
     * Convenience method that can be used to verify that the nesting depth does
     * not exceed the maximum specified by this constraints object.
     *
     * Throws: `StreamConstraintsException` if `depth` exceeds the maximum.
     */
    void validateNestingDepth(int depth) const pure
    {
        if (depth > _maxNestingDepth)
            throwNestingDepth(depth);
    }

    private void throwNestingDepth(int depth) const pure
    {
        import flint.engine.aot.text : decimal;
        import flint.jackson.core.exc : StreamConstraintsException;

        throw new StreamConstraintsException(join("Document nesting depth (", decimal(depth),
                ") exceeds the maximum allowed (",
                decimal(_maxNestingDepth), ", from `StreamWriteConstraints.getMaxNestingDepth()`)"));
    }
}

/// Token reader (parser) features not-specific to any particular format backend.
enum StreamReadFeature
{
    /// Whether the parser closes the underlying source on `close()`. Default: true.
    AUTO_CLOSE_SOURCE,
    /// Whether the parser skips over unknown content under a format schema. Default: false.
    IGNORE_UNDEFINED,
    /// Whether duplicate property names are detected and reported as errors. Default: false.
    STRICT_DUPLICATE_DETECTION,
    /// Whether the current token is cleared on `close()`. Default: true.
    CLEAR_CURRENT_TOKEN_ON_CLOSE,
    /// Whether source references are included in `TokenStreamLocation`. Default: false.
    INCLUDE_SOURCE_IN_LOCATION,
    /// Whether to use the fast big-number parser. Default: true.
    USE_FAST_BIG_NUMBER_PARSER,
    /// Whether to use the fast double parser. Default: true.
    USE_FAST_DOUBLE_PARSER,
}

/// Whether the read feature is enabled by default (Jackson 3.1.8).
bool enabledByDefault(StreamReadFeature f) pure nothrow @nogc
{
    final switch (f)
    {
    case StreamReadFeature.AUTO_CLOSE_SOURCE:
    case StreamReadFeature.CLEAR_CURRENT_TOKEN_ON_CLOSE:
    case StreamReadFeature.USE_FAST_BIG_NUMBER_PARSER:
    case StreamReadFeature.USE_FAST_DOUBLE_PARSER:
        return true;
    case StreamReadFeature.IGNORE_UNDEFINED:
    case StreamReadFeature.STRICT_DUPLICATE_DETECTION:
    case StreamReadFeature.INCLUDE_SOURCE_IN_LOCATION:
        return false;
    }
}

/// Token writer (generator) features not-specific to any particular format backend.
enum StreamWriteFeature
{
    /// Whether open structures are closed when the generator is closed. Default: true.
    AUTO_CLOSE_CONTENT,
    /// Whether the generator closes the target on `close()`. Default: true.
    AUTO_CLOSE_TARGET,
    /// Whether `flush()` is passed to the target. Default: true.
    FLUSH_PASSED_TO_STREAM,
    /// Whether `BigDecimal` values are written in plain notation. Default: false.
    WRITE_BIGDECIMAL_AS_PLAIN,
    /// Whether properties unknown to a format schema are ignored. Default: false.
    IGNORE_UNKNOWN,
    /// Whether duplicate property names are detected and reported as errors. Default: false.
    STRICT_DUPLICATE_DETECTION,
    /// Whether to use the Schubfach writer instead of `Double.toString`. Default: false (same output on JDK 19+).
    USE_FAST_DOUBLE_WRITER,
}

/// Whether the write feature is enabled by default (Jackson 3.1.8).
bool enabledByDefault(StreamWriteFeature f) pure nothrow @nogc
{
    final switch (f)
    {
    case StreamWriteFeature.AUTO_CLOSE_CONTENT:
    case StreamWriteFeature.AUTO_CLOSE_TARGET:
    case StreamWriteFeature.FLUSH_PASSED_TO_STREAM:
        return true;
    case StreamWriteFeature.WRITE_BIGDECIMAL_AS_PLAIN:
    case StreamWriteFeature.IGNORE_UNKNOWN:
    case StreamWriteFeature.STRICT_DUPLICATE_DETECTION:
    case StreamWriteFeature.USE_FAST_DOUBLE_WRITER:
        return false;
    }
}

/**
 * Base class that defines public API for writing JSON content. Instances are
 * created using factory methods of a `TokenStreamFactory` instance.
 *
 * Every write method returns the generator, as in Jackson 3, so calls chain.
 */
abstract class JsonGenerator
{
    /// Method for writing starting marker of an Object value (`{`).
    abstract JsonGenerator writeStartObject();

    /// Method for writing starting marker of an Object value, with the value it represents.
    JsonGenerator writeStartObject(Object currentValue)
    {
        writeStartObject();
        assignCurrentValue(currentValue);
        return this;
    }

    /// Method for writing closing marker of an Object value (`}`).
    abstract JsonGenerator writeEndObject();

    /// Method for writing starting marker of an Array value (`[`).
    abstract JsonGenerator writeStartArray();

    /// Method for writing starting marker of an Array value, with the value it represents.
    JsonGenerator writeStartArray(Object currentValue)
    {
        writeStartArray();
        assignCurrentValue(currentValue);
        return this;
    }

    /// Method for writing starting marker of an Array value, with the value and its size.
    JsonGenerator writeStartArray(Object currentValue, int)
    {
        return writeStartArray(currentValue);
    }

    /// Method for writing closing marker of a JSON Array value (`]`).
    abstract JsonGenerator writeEndArray();

    /// Method for writing an Object Property name (JSON String surrounded by double quotes).
    abstract JsonGenerator writeName(string name);

    /// Write a numeric property id. The default JSON name is its signed decimal spelling.
    JsonGenerator writePropertyId(long id)
    {
        import flint.jackson.core.io : NumberOutput;

        char[20] digits;
        const length = NumberOutput.writeLong(id, digits);
        writeName(digits[0 .. length].idup);
        return this;
    }

    /// Notify the output format that a property was omitted. JSON needs no placeholder.
    JsonGenerator writeOmittedProperty(string propertyName)
    {
        return this;
    }

    /// Method for outputting a String value.
    abstract JsonGenerator writeString(string value);

    /// Method for outputting a String value from a character buffer.
    JsonGenerator writeString(scope const(char)[] buffer, int offset, int len)
    {
        return writeString(buffer[offset .. offset + len].idup);
    }

    /// Method for outputting given value as JSON number (16-bit).
    JsonGenerator writeNumber(short v)
    {
        return writeNumber(cast(int) v);
    }

    /// Method for outputting given value as JSON number (32-bit).
    abstract JsonGenerator writeNumber(int v);

    /// Method for outputting given value as JSON number (64-bit).
    abstract JsonGenerator writeNumber(long v);

    /// Method for outputting indicate JSON numeric value; `Double.toString`, or a quoted string for NaN and infinities.
    abstract JsonGenerator writeNumber(double v);

    /// Method for outputting indicate JSON numeric value; `Float.toString`, or a quoted string for NaN and infinities.
    abstract JsonGenerator writeNumber(float v);

    /// Write a numeric value already encoded as text, verbatim.
    abstract JsonGenerator writeNumber(string encodedValue);

    /// Method for outputting literal JSON boolean value (one of Strings 'true' and 'false').
    abstract JsonGenerator writeBoolean(bool state);

    /// Method for outputting literal JSON null value.
    abstract JsonGenerator writeNull();

    /// Method that will force generator to copy input text verbatim with no modifications.
    abstract JsonGenerator writeRaw(string text);

    /// Write one raw character.
    abstract JsonGenerator writeRaw(char c);

    /// Copy input text verbatim as a complete value, with separators added as needed.
    abstract JsonGenerator writeRawValue(string text);

    /// Convenience method for outputting a property with a String value.
    final JsonGenerator writeStringProperty(string propertyName, string value)
    {
        writeName(propertyName);
        return writeString(value);
    }

    /// Convenience method for outputting a property with a boolean value.
    final JsonGenerator writeBooleanProperty(string propertyName, bool value)
    {
        writeName(propertyName);
        return writeBoolean(value);
    }

    /// Convenience method for outputting a property with a JSON literal null value.
    final JsonGenerator writeNullProperty(string propertyName)
    {
        writeName(propertyName);
        return writeNull();
    }

    /// Convenience method for outputting a property with a numeric value.
    final JsonGenerator writeNumberProperty(string propertyName, short value)
    {
        writeName(propertyName);
        return writeNumber(value);
    }

    /// ditto
    final JsonGenerator writeNumberProperty(string propertyName, int value)
    {
        writeName(propertyName);
        return writeNumber(value);
    }

    /// ditto
    final JsonGenerator writeNumberProperty(string propertyName, long value)
    {
        writeName(propertyName);
        return writeNumber(value);
    }

    /// ditto
    final JsonGenerator writeNumberProperty(string propertyName, float value)
    {
        writeName(propertyName);
        return writeNumber(value);
    }

    /// ditto
    final JsonGenerator writeNumberProperty(string propertyName, double value)
    {
        writeName(propertyName);
        return writeNumber(value);
    }

    /// Convenience method for outputting a property and the START_ARRAY marker of its value.
    final JsonGenerator writeArrayPropertyStart(string propertyName)
    {
        writeName(propertyName);
        return writeStartArray();
    }

    /// Convenience method for outputting a property and the START_OBJECT marker of its value.
    final JsonGenerator writeObjectPropertyStart(string propertyName)
    {
        writeName(propertyName);
        return writeStartObject();
    }

    /// Write an array of ints as a JSON array.
    JsonGenerator writeArray(scope const(int)[] array, int offset, int length)
    {
        writeStartArray();
        foreach (v; array[offset .. offset + length])
            writeNumber(v);
        return writeEndArray();
    }

    /// Write an array of longs as a JSON array.
    JsonGenerator writeArray(scope const(long)[] array, int offset, int length)
    {
        writeStartArray();
        foreach (v; array[offset .. offset + length])
            writeNumber(v);
        return writeEndArray();
    }

    /// Write an array of doubles as a JSON array.
    JsonGenerator writeArray(scope const(double)[] array, int offset, int length)
    {
        writeStartArray();
        foreach (v; array[offset .. offset + length])
            writeNumber(v);
        return writeEndArray();
    }

    /// Write an array of Strings as a JSON array.
    JsonGenerator writeArray(scope const(string)[] array, int offset, int length)
    {
        writeStartArray();
        foreach (v; array[offset .. offset + length])
            writeString(v);
        return writeEndArray();
    }

    /// Accessor for the context object that tracks Object and Array nesting while writing.
    abstract TokenStreamContext streamWriteContext();

    /// Helper method, usually equivalent to `streamWriteContext().currentValue()`.
    Object currentValue()
    {
        auto ctxt = streamWriteContext();
        return ctxt is null ? null : ctxt.currentValue();
    }

    /// Helper method, usually equivalent to `streamWriteContext().assignCurrentValue(v)`.
    void assignCurrentValue(Object v)
    {
        auto ctxt = streamWriteContext();
        if (ctxt !is null)
            ctxt.assignCurrentValue(v);
    }

    /// Accessor for the pretty printer in use, if any.
    abstract PrettyPrinter getPrettyPrinter();

    /// The constraints this generator enforces (`StreamWriteConstraints.defaults()` unless a subclass says otherwise).
    StreamWriteConstraints streamWriteConstraints()
    {
        return StreamWriteConstraints.defaults();
    }

    /// Whether the given feature is enabled.
    abstract bool isEnabled(StreamWriteFeature f);

    /// The enabled stream features as a bit mask with one bit per feature ordinal.
    int streamWriteFeatures()
    {
        int flags;
        foreach (bit; 0 .. cast(int) StreamWriteFeature.max + 1)
            if (isEnabled(cast(StreamWriteFeature) bit))
                flags |= 1 << bit;
        return flags;
    }

    /// Whether properties may be omitted from the output format.
    bool canOmitProperties()
    {
        return true;
    }

    /// Whether the output format can write native object ids.
    bool canWriteObjectId()
    {
        return false;
    }

    /// Whether the output format can write native type ids.
    bool canWriteTypeId()
    {
        return false;
    }

    /// Write a native object id. Formats without native ids report a stream write error.
    JsonGenerator writeObjectId(Any id)
    {
        return rejectNativeId("No native support for writing Object Ids");
    }

    /// Write a reference to a native object id.
    JsonGenerator writeObjectRef(Any referenced)
    {
        return rejectNativeId("No native support for writing Object Ids");
    }

    /// Write a native type id. Formats without native ids report a stream write error.
    JsonGenerator writeTypeId(Any id)
    {
        return rejectNativeId("No native support for writing Type Ids");
    }

    private JsonGenerator rejectNativeId(string message)
    {
        import flint.jackson.core.exc : StreamWriteException;

        throw new StreamWriteException(this, message);
    }

    /// The write context this generator was created with.
    abstract ObjectWriteContext objectWriteContext();

    /// Method called to flush any buffered content to the underlying target.
    abstract void flush();

    /// Close the generator, closing open structures when `AUTO_CLOSE_CONTENT` is enabled, and flush.
    abstract void close();

    /// Whether `close()` has been called.
    abstract bool isClosed();
}

/**
 * Base class that defines public API for reading JSON content. Instances are
 * created using factory methods of a `JsonFactory` instance.
 */
abstract class JsonParser
{
    /// Enumeration of possible "native" (optimal) types that can be used for numbers.
    enum NumberType
    {
        ///
        INT,
        ///
        LONG,
        ///
        BIG_INTEGER,
        ///
        FLOAT,
        ///
        DOUBLE,
        ///
        BIG_DECIMAL,
    }

    /// Native floating-point representation when the format exposes one.
    enum NumberTypeFP
    {
        /// IEEE-754 binary16.
        FLOAT16,
        /// IEEE-754 binary32.
        FLOAT32,
        /// IEEE-754 binary64.
        DOUBLE64,
        /// Arbitrary-precision decimal.
        BIG_DECIMAL,
        /// The format exposes no single native floating-point representation.
        UNKNOWN,
    }

    /// Main iteration method, which will advance stream enough to determine type of the next token, if any.
    abstract JsonToken nextToken();

    /// Iteration method that will advance stream enough to determine type of the next token that is a value type.
    JsonToken nextValue()
    {
        auto t = nextToken();
        if (t == JsonToken.PROPERTY_NAME)
            t = nextToken();
        return t;
    }

    /// Advance to the next token and return its name when it is a `PROPERTY_NAME`, else null.
    string nextName()
    {
        return nextToken() == JsonToken.PROPERTY_NAME ? currentName() : null;
    }

    /// Advance and return the String value when the next token is `VALUE_STRING`, else null.
    string nextStringValue()
    {
        return nextToken() == JsonToken.VALUE_STRING ? getString() : null;
    }

    /// Advance once and return an integer value, or the default for any other token.
    int nextIntValue(int defaultValue)
    {
        return nextToken() == JsonToken.VALUE_NUMBER_INT ? getIntValue() : defaultValue;
    }

    /// Advance once and return a long integer value, or the default for any other token.
    long nextLongValue(long defaultValue)
    {
        return nextToken() == JsonToken.VALUE_NUMBER_INT ? getLongValue() : defaultValue;
    }

    /// Advance once and return a Boolean, or a null nullable for any other token.
    Nullable!bool nextBooleanValue()
    {
        const token = nextToken();
        if (token != JsonToken.VALUE_TRUE && token != JsonToken.VALUE_FALSE)
            return Nullable!bool.init;
        return Nullable!bool(token == JsonToken.VALUE_TRUE);
    }

    /// Skip the children of the current START_OBJECT or START_ARRAY, leaving the parser on the matching end.
    abstract JsonParser skipChildren();

    /// The token the parser currently points to, or `NOT_AVAILABLE`.
    abstract JsonToken currentToken();

    /// The `JsonTokenId` of the current token, or `ID_NO_TOKEN`.
    int currentTokenId()
    {
        auto t = currentToken();
        return t == JsonToken.NOT_AVAILABLE ? JsonTokenId.ID_NO_TOKEN : t.id();
    }

    /// Whether the parser currently points to a token.
    bool hasCurrentToken()
    {
        return currentToken() != JsonToken.NOT_AVAILABLE;
    }

    /// Whether the current token is the given one.
    bool hasToken(JsonToken t)
    {
        return currentToken() == t;
    }

    /// Whether the current token has the given id.
    bool hasTokenId(int id)
    {
        return currentTokenId() == id;
    }

    /// Specialized accessor that can be used to verify that the current token indicates start array.
    bool isExpectedStartArrayToken()
    {
        return currentToken() == JsonToken.START_ARRAY;
    }

    /// Similar to `isExpectedStartArrayToken()`, but checks whether stream currently points to `START_OBJECT`.
    bool isExpectedStartObjectToken()
    {
        return currentToken() == JsonToken.START_OBJECT;
    }

    /// Whether the current token represents an integer.
    bool isExpectedNumberIntToken()
    {
        return currentToken() == JsonToken.VALUE_NUMBER_INT;
    }

    /// Whether the current token is a JSON null.
    bool isNaN()
    {
        return false;
    }

    /// The name associated with the current token: for `PROPERTY_NAME` the name, for values the property name.
    abstract string currentName();

    /// Textual representation of the current token: string contents, number text, literal or name.
    abstract string getString();

    /// The characters of the current token's text, valid only until the next token: Jackson's
    /// `getStringCharacters`, with the offset and length folded into the slice. A parser over a complete document
    /// returns a slice of it, so a reader that only parses the text (a date, a number) copies nothing. Here: a copy.
    const(char)[] getStringCharacters()
    {
        return getString();
    }

    /// The offset of the text in `getStringCharacters`: always 0, since the slice starts there.
    int getStringOffset()
    {
        return 0;
    }

    /// The length of the text in `getStringCharacters`.
    int getStringLength()
    {
        return cast(int) getStringCharacters().length;
    }

    /// Numeric value of the current number token as a Java int, with Jackson's range check.
    abstract int getIntValue();

    /// Numeric value of the current number token as a Java long.
    abstract long getLongValue();

    /// Numeric value of the current number token as a double.
    abstract double getDoubleValue();

    /// Numeric value of the current number token as a float.
    abstract float getFloatValue();

    /// Numeric value as a short, with Jackson's range check.
    short getShortValue()
    {
        immutable value = getIntValue();
        if (value < short.min || value > short.max)
            throw coercionError(join("Numeric value (", getString(),
                    ") out of range of `short` (-32768 - 32767)"), currentToken());
        return cast(short) value;
    }

    /// Numeric value as a byte (-128 to 255, as Jackson accepts), with its range check.
    byte getByteValue()
    {
        immutable value = getIntValue();
        if (value < byte.min || value > 255)
            throw coercionError(join("Numeric value (", getString(),
                    ") out of range of `byte` (-128 - 255)"), currentToken());
        return cast(byte) value;
    }

    /// The natural number type of the current numeric token.
    abstract NumberType getNumberType();

    /// Native floating-point representation. Textual JSON has no single native representation.
    NumberTypeFP getNumberTypeFP()
    {
        return NumberTypeFP.UNKNOWN;
    }

    /// Boolean value of the current token.
    bool getBooleanValue()
    {
        auto t = currentToken();
        if (t == JsonToken.VALUE_TRUE)
            return true;
        if (t == JsonToken.VALUE_FALSE)
            return false;
        throw coercionError(join("Current token (", tokenName(t), ") not of boolean type"), t);
    }

    /// String value of a scalar token, converting numbers and booleans; null for other tokens.
    string getValueAsString()
    {
        return getValueAsString(null);
    }

    /// ditto, with a default for tokens that have no String representation.
    string getValueAsString(string def)
    {
        auto t = currentToken();
        if (t == JsonToken.VALUE_STRING)
            return getString();
        if (t == JsonToken.PROPERTY_NAME)
            return currentName();
        if (t == JsonToken.NOT_AVAILABLE || t == JsonToken.VALUE_NULL || !t.isScalarValue())
            return def;
        return getString();
    }

    /// Int value of the current token, converting where Jackson does; 0 when impossible.
    int getValueAsInt()
    {
        return getValueAsInt(0);
    }

    /// ditto, with a default.
    abstract int getValueAsInt(int def);

    /// Long value of the current token, converting where Jackson does; 0 when impossible.
    long getValueAsLong()
    {
        return getValueAsLong(0);
    }

    /// ditto, with a default.
    abstract long getValueAsLong(long def);

    /// Double value of the current token, converting where Jackson does; 0.0 when impossible.
    double getValueAsDouble()
    {
        return getValueAsDouble(0.0);
    }

    /// ditto, with a default.
    abstract double getValueAsDouble(double def);

    /// Boolean value of the current token, converting where Jackson does; false when impossible.
    bool getValueAsBoolean()
    {
        return getValueAsBoolean(false);
    }

    /// ditto, with a default.
    abstract bool getValueAsBoolean(bool def);

    /// Whether the input format can read native object ids.
    bool canReadObjectId()
    {
        return false;
    }

    /// Whether the input format can read native type ids.
    bool canReadTypeId()
    {
        return false;
    }

    /// The current token's native object id, or null when absent.
    Any getObjectId()
    {
        return Any.init;
    }

    /// The current token's native type id, or null when absent.
    Any getTypeId()
    {
        return Any.init;
    }

    /// The parsing context: Object, Array or root, with the current name and index.
    abstract TokenStreamContext streamReadContext();

    /// Location of the start of the current token.
    abstract TokenStreamLocation currentTokenLocation();

    /// Location of the last processed input unit.
    abstract TokenStreamLocation currentLocation();

    /// The value being deserialized at this level, as databind sets it.
    Object currentValue()
    {
        auto ctxt = streamReadContext();
        return ctxt is null ? null : ctxt.currentValue();
    }

    /// Assign the value being deserialized at this level.
    void assignCurrentValue(Object v)
    {
        auto ctxt = streamReadContext();
        if (ctxt !is null)
            ctxt.assignCurrentValue(v);
    }

    /// Whether the given feature is enabled.
    abstract bool isEnabled(StreamReadFeature f);

    /// The enabled stream features as a bit mask with one bit per feature ordinal.
    int streamReadFeatures()
    {
        int flags;
        foreach (bit; 0 .. cast(int) StreamReadFeature.max + 1)
            if (isEnabled(cast(StreamReadFeature) bit))
                flags |= 1 << bit;
        return flags;
    }

    /// The read context this parser was created with.
    abstract ObjectReadContext objectReadContext();

    /// Stream read constraints in effect.
    abstract StreamReadConstraints streamReadConstraints();

    /// Closes the parser so that no further iteration or data access can be made.
    abstract void close();

    /// Whether `close()` has been called.
    abstract bool isClosed();

    /// Build a `StreamReadException` for this parser at its current location.
    protected JacksonException readError(string message)
    {
        import flint.jackson.core.exc : StreamReadException;

        return new StreamReadException(this, message, currentLocation());
    }

    /// Build an `InputCoercionException` for a value of `inputType`.
    protected JacksonException coercionError(string message, JsonToken inputType)
    {
        import flint.jackson.core.exc : InputCoercionException;

        return new InputCoercionException(this, message, inputType, currentLocation());
    }
}

/// Jackson's display name of a token, as messages quote it: the constant name, or "null" for none.
string tokenName(JsonToken t) pure nothrow @nogc
{
    static immutable string[JsonToken.max + 1] names = [
        "null", "START_OBJECT", "END_OBJECT", "START_ARRAY", "END_ARRAY", "PROPERTY_NAME",
        "VALUE_EMBEDDED_OBJECT", "VALUE_STRING", "VALUE_NUMBER_INT", "VALUE_NUMBER_FLOAT",
        "VALUE_TRUE", "VALUE_FALSE", "VALUE_NULL",
    ];
    return names[t];
}
