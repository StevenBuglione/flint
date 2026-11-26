/++
`org.springframework.http.converter`: converting bodies to and from HTTP messages.

Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/http/converter/ (HttpMessageConverter.java,
AbstractHttpMessageConverter.java, StringHttpMessageConverter.java, ByteArrayHttpMessageConverter.java,
ResourceHttpMessageConverter.java,
HttpMessageConversionException.java, HttpMessageNotReadableException.java, HttpMessageNotWritableException.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: `HttpMessageConverter<T>` is erased (ADR-030 section 5). `Class<?>` arguments are
the fully qualified type name (R4), bodies are `Any`. `StringHttpMessageConverter` defaults to UTF-8, as Spring
Boot configures it.
+/
module flint.http.converter;

import flint.core : NestedRuntimeException;
import flint.core.convert : TypeDescriptor;
import flint.core.io : AbstractResource, ByteArrayResource, ClassPathResource, DescriptiveResource,
    FileSystemResource, InputStreamResource, InputStreamSource, Resource;
import flint.core.io.support : ResourceRegion;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.text : decodeUtf8;
import flint.http : HttpHeaders, HttpInputMessage, HttpOutputMessage, MediaType, MediaTypeFactory,
    StreamingHttpOutputMessage, decimal, equalsIgnoreAsciiCase, trimmedAscii;
import flint.java.io : ByteArrayInputStream, FileNotFoundException, IOException, InputStream, OutputStream;
import flint.java.lang : IllegalArgumentException, NullPointerException, UnsupportedOperationException;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.util : RawCollection;

@safe:

/// `HttpMessageConverter`: reads and writes one family of body types.
interface HttpMessageConverter
{
    /// Whether `typeName` can be read as `mediaType` (`null` for any).
    bool canRead(string typeName, scope const(MediaType)* mediaType);

    /// Whether `typeName` can be written as `mediaType` (`null` for any).
    bool canWrite(string typeName, scope const(MediaType)* mediaType);

    /// The media types this converter supports.
    MediaType[] getSupportedMediaTypes();

    /// The media types supported for `typeName`.
    MediaType[] getSupportedMediaTypes(string typeName);

    /// Reads a `typeName` from `inputMessage`.
    Any read(string typeName, HttpInputMessage inputMessage);

    /// Writes `value` with `contentType` (or the converter's default when `null` or not concrete).
    void write(Any value, scope const(MediaType)* contentType, HttpOutputMessage outputMessage);
}

/// `AbstractHttpMessageConverter`: media-type bookkeeping and Spring's default headers.
abstract class AbstractHttpMessageConverter : HttpMessageConverter
{
    private MediaType[] supportedMediaTypes;
    private Charset defaultCharset;
    private bool hasDefaultCharset;

    /// With supported media types.
    protected this(MediaType[] supportedMediaTypes...)
    {
        this.supportedMediaTypes = supportedMediaTypes.dup;
    }

    /// With a default charset and supported media types.
    protected this(Charset defaultCharset, MediaType[] supportedMediaTypes...)
    {
        this.defaultCharset = defaultCharset;
        hasDefaultCharset = true;
        this.supportedMediaTypes = supportedMediaTypes.dup;
    }

    /// Replaces the supported media types.
    void setSupportedMediaTypes(MediaType[] supportedMediaTypes)
    {
        this.supportedMediaTypes = supportedMediaTypes;
    }

    MediaType[] getSupportedMediaTypes()
    {
        return supportedMediaTypes;
    }

    MediaType[] getSupportedMediaTypes(string typeName)
    {
        return canRead(typeName, null) || canWrite(typeName, null) ? getSupportedMediaTypes() : null;
    }

    /// Sets the default charset.
    void setDefaultCharset(Charset defaultCharset)
    {
        this.defaultCharset = defaultCharset;
        hasDefaultCharset = true;
    }

    /// The default charset, or `null`.
    const(Charset)* getDefaultCharset() const return
    {
        return hasDefaultCharset ? &defaultCharset : null;
    }

    /// Whether this converter handles `typeName`.
    protected abstract bool supports(string typeName);

    bool canRead(string typeName, scope const(MediaType)* mediaType)
    {
        return supports(typeName) && canRead(mediaType);
    }

    /// Whether a supported media type includes `mediaType`.
    protected bool canRead(scope const(MediaType)* mediaType)
    {
        if (mediaType is null)
            return true;
        foreach (supported; getSupportedMediaTypes())
            if (supported.includes(*mediaType))
                return true;
        return false;
    }

    bool canWrite(string typeName, scope const(MediaType)* mediaType)
    {
        return supports(typeName) && canWrite(mediaType);
    }

    /// Whether a supported media type is compatible with `mediaType`.
    protected bool canWrite(scope const(MediaType)* mediaType)
    {
        if (mediaType is null || mediaType.equals(MediaType.ALL))
            return true;
        foreach (supported; getSupportedMediaTypes())
            if (supported.isCompatibleWith(*mediaType))
                return true;
        return false;
    }

    Any read(string typeName, HttpInputMessage inputMessage)
    {
        return readInternal(typeName, inputMessage);
    }

    void write(Any value, scope const(MediaType)* contentType, HttpOutputMessage outputMessage)
    {
        auto headers = outputMessage.getHeaders();
        addDefaultHeaders(headers, value, contentType);
        writeInternal(value, outputMessage);
    }

    /// Whether the value can be written more than once.
    bool canWriteRepeatedly(Any value, scope const(MediaType)* contentType)
    {
        return false;
    }

    /// The legacy repeatability hook.
    protected bool supportsRepeatableWrites(Any value)
    {
        return canWriteRepeatedly(value, null);
    }

    /// Spring's `addDefaultHeaders`: a concrete Content-Type with the default charset, and Content-Length when known.
    protected void addDefaultHeaders(HttpHeaders headers, Any value, scope const(MediaType)* contentType)
    {
        if (headers.getContentType() is null)
        {
            MediaType contentTypeToUse;
            bool have;
            if (contentType is null || !contentType.isConcrete())
            {
                if (auto fallback = getDefaultContentType(value))
                {
                    contentTypeToUse = *fallback;
                    have = true;
                }
            }
            else if (contentType.equals(MediaType.APPLICATION_OCTET_STREAM))
            {
                auto fallback = getDefaultContentType(value);
                contentTypeToUse = fallback !is null ? *fallback : *contentType;
                have = true;
            }
            else
            {
                contentTypeToUse = *contentType;
                have = true;
            }
            if (have)
            {
                if (contentTypeToUse.getCharset() is null && hasDefaultCharset)
                    contentTypeToUse = MediaType(contentTypeToUse, defaultCharset);
                headers.setContentType(contentTypeToUse);
            }
        }
        if (headers.getContentLength() < 0 && !headers.containsHeader(HttpHeaders.TRANSFER_ENCODING))
        {
            MediaType written;
            const length = getContentLength(value, headers.readContentType(written) ? &written : null);
            if (length >= 0)
                headers.setContentLength(length);
        }
    }

    /// The first supported media type, used when none was negotiated, or `null`.
    protected MediaType* getDefaultContentType(Any value)
    {
        auto types = getSupportedMediaTypes();
        if (types.length == 0)
            return null;
        auto result = new MediaType;
        *result = types[0];
        return result;
    }

    /// The body length when known before writing, else `-1`.
    protected long getContentLength(Any value, scope const(MediaType)* contentType)
    {
        return -1;
    }

    /// Reads the body.
    protected abstract Any readInternal(string typeName, HttpInputMessage inputMessage);

    /// Writes the body.
    protected abstract void writeInternal(Any value, HttpOutputMessage outputMessage);
}

/// GenericHttpMessageConverter.java, Spring Framework v7.1.0. Modified by the Flint authors.
interface GenericHttpMessageConverter : HttpMessageConverter
{
    alias canRead = HttpMessageConverter.canRead;
    alias canWrite = HttpMessageConverter.canWrite;
    alias read = HttpMessageConverter.read;
    alias write = HttpMessageConverter.write;

    bool canRead(const TypeDescriptor type, string contextClass, scope const(MediaType)* mediaType);
    bool canWrite(const TypeDescriptor type, string typeName, scope const(MediaType)* mediaType);
    Any read(const TypeDescriptor type, string contextClass, HttpInputMessage inputMessage);
    void write(Any value, const TypeDescriptor type, scope const(MediaType)* contentType, HttpOutputMessage output);
}

/// AbstractGenericHttpMessageConverter.java, Spring Framework v7.1.0. Modified by the Flint authors.
abstract class AbstractGenericHttpMessageConverter : AbstractHttpMessageConverter, GenericHttpMessageConverter
{
    alias canRead = AbstractHttpMessageConverter.canRead;
    alias canWrite = AbstractHttpMessageConverter.canWrite;
    alias read = AbstractHttpMessageConverter.read;
    alias write = AbstractHttpMessageConverter.write;
    alias writeInternal = AbstractHttpMessageConverter.writeInternal;

    protected this(MediaType[] mediaTypes...)
    {
        super(mediaTypes);
    }

    protected this(Charset charset, MediaType[] mediaTypes...)
    {
        super(charset, mediaTypes);
    }

    protected override bool supports(string typeName)
    {
        return true;
    }

    override bool canRead(const TypeDescriptor type, string contextClass, scope const(MediaType)* mediaType)
    {
        return type is null || type.getElementTypeDescriptor() !is null
            ? canRead(mediaType) : canRead(type.getName(), mediaType);
    }

    override bool canWrite(const TypeDescriptor type, string typeName, scope const(MediaType)* mediaType)
    {
        return canWrite(typeName, mediaType);
    }

    abstract override Any read(const TypeDescriptor type, string contextClass, HttpInputMessage inputMessage);

    override void write(Any value, scope const(MediaType)* contentType, HttpOutputMessage output)
    {
        write(value, null, contentType, output);
    }

    final override void write(Any value, const TypeDescriptor type,
            scope const(MediaType)* contentType, HttpOutputMessage output)
    {
        auto headers = output.getHeaders();
        addDefaultHeaders(headers, value, contentType);
        if (auto streaming = cast(StreamingHttpOutputMessage) output)
            streaming.setBody(new ConverterStreamingBody(this, headers, value, type, contentType));
        else
            writeInternal(value, type, output);
    }

    protected override void writeInternal(Any value, HttpOutputMessage output)
    {
        writeInternal(value, null, output);
    }

    protected abstract void writeInternal(Any value, const TypeDescriptor type, HttpOutputMessage output);
}

private final class ConverterStreamingBody : StreamingHttpOutputMessage.Body
{
    private AbstractHttpMessageConverter converter;
    private HttpHeaders headers;
    private Any value;
    private const(TypeDescriptor) type;
    private MediaType mediaType;
    private bool hasMediaType;

    this(AbstractHttpMessageConverter converter, HttpHeaders headers, Any value,
            const TypeDescriptor type, scope const(MediaType)* contentType)
    {
        this.converter = converter;
        this.headers = headers;
        this.value = value;
        this.type = type;
        hasMediaType = contentType !is null;
        if (hasMediaType)
            mediaType = *contentType;
    }

    void writeTo(OutputStream output)
    {
        auto message = new StreamHttpOutputMessage(headers, output);
        if (auto generic = cast(AbstractGenericHttpMessageConverter) converter)
            generic.writeInternal(value, type, message);
        else
            converter.writeInternal(value, message);
    }

    bool repeatable()
    {
        return converter.canWriteRepeatedly(value, hasMediaType ? &mediaType : null);
    }
}

private final class StreamHttpOutputMessage : HttpOutputMessage
{
    private HttpHeaders headers;
    private OutputStream output;

    this(HttpHeaders headers, OutputStream output)
    {
        this.headers = headers;
        this.output = output;
    }

    HttpHeaders getHeaders()
    {
        return headers;
    }

    void writeBody(scope const(ubyte)[] bytes)
    {
        output.write(bytes);
    }
}

/// ResourceRegionHttpMessageConverter.java, Spring Framework v7.1.0. Modified by the Flint authors.
class ResourceRegionHttpMessageConverter : AbstractGenericHttpMessageConverter
{
    private TypeDescriptor regionType;
    private TypeDescriptor collectionType;

    this()
    {
        super(MediaType.ALL);
        regionType = TypeDescriptor.valueOf!ResourceRegion();
        collectionType = TypeDescriptor.valueOf!RawCollection();
    }

    override bool canRead(string typeName, scope const(MediaType)* mediaType)
    {
        return false;
    }

    override bool canRead(const TypeDescriptor type, string contextClass, scope const(MediaType)* mediaType)
    {
        return false;
    }

    alias read = AbstractGenericHttpMessageConverter.read;

    override Any read(const TypeDescriptor type, string contextClass, HttpInputMessage inputMessage)
    {
        throw new UnsupportedOperationException();
    }

    protected override Any readInternal(string typeName, HttpInputMessage inputMessage)
    {
        throw new UnsupportedOperationException();
    }

    override bool canWrite(string typeName, scope const(MediaType)* mediaType)
    {
        return typeName == typeNameOf!ResourceRegion;
    }

    override bool canWrite(const TypeDescriptor type, string typeName, scope const(MediaType)* mediaType)
    {
        if (type is null)
            return false;
        if (type.isAssignableTo(regionType))
            return true;
        if (!type.isAssignableTo(collectionType))
            return false;
        auto element = type.getElementTypeDescriptor();
        return element !is null && element.isAssignableTo(regionType);
    }

    override bool canWriteRepeatedly(Any value, scope const(MediaType)* contentType)
    {
        if (auto region = cast(ResourceRegion) value.asObject())
            return repeatable(region);
        foreach (element; regions(value))
            if (!repeatable(regionOf(element)))
                return false;
        return true;
    }

    /// Spring's original repeatable-write hook.
    protected override bool supportsRepeatableWrites(Any value)
    {
        return canWriteRepeatedly(value, null);
    }

    private static bool repeatable(ResourceRegion region)
    {
        return cast(InputStreamResource) region.getResource() is null;
    }

    protected override void writeInternal(Any value, const TypeDescriptor type, HttpOutputMessage output)
    {
        if (auto region = cast(ResourceRegion) value.asObject())
        {
            writeResourceRegion(region, output);
            return;
        }
        auto parts = regions(value);
        if (parts.length == 1)
            writeResourceRegion(regionOf(parts[0]), output);
        else
            writeCollection(parts, output);
    }

    protected override MediaType* getDefaultContentType(Any value)
    {
        auto region = cast(ResourceRegion) value.asObject();
        if (region is null)
        {
            auto parts = regions(value);
            if (parts.length != 0)
                region = regionOf(parts[0]);
        }
        auto mediaType = new MediaType;
        *mediaType = MediaTypeFactory.getMediaType(region is null ? null : region.getResource())
            .orElse(MediaType.APPLICATION_OCTET_STREAM);
        return mediaType;
    }

    /// Writes a single region with Content-Range and Content-Length.
    protected void writeResourceRegion(ResourceRegion region, HttpOutputMessage output)
    {
        if (region is null)
            throw new IllegalArgumentException("ResourceRegion must not be null");
        auto headers = output.getHeaders();
        auto resource = region.getResource();
        const start = region.getPosition();
        const length = resource.contentLength();
        const count = boundedCount(region, length);
        headers.add(HttpHeaders.CONTENT_RANGE, formatRange(start, count, length));
        headers.setContentLength(count);
        auto input = resource.getInputStream();
        scope (exit)
            closeRegion(input);
        copyRegion(input, output, start, count);
    }

    private static Any[] regions(Any value)
    {
        auto collection = cast(RawCollection) value.asObject();
        if (collection is null)
            throw new HttpMessageNotWritableException("Expected a ResourceRegion or a collection of ResourceRegion");
        return collection.toAnyArray();
    }

    private static ResourceRegion regionOf(Any value)
    {
        auto region = cast(ResourceRegion) value.asObject();
        if (region is null)
            throw new HttpMessageNotWritableException("Collection contains a value other than ResourceRegion");
        return region;
    }

    private static void writeCollection(scope Any[] parts, HttpOutputMessage output)
    {
        import std.uuid : randomUUID;

        auto headers = output.getHeaders();
        auto contentType = headers.getContentType();
        const boundary = randomUUID().toString();
        headers.set(HttpHeaders.CONTENT_TYPE, "multipart/byteranges; boundary=" ~ boundary);

        Resource resource;
        InputStream input;
        long offset;
        scope (exit)
            closeRegion(input);
        foreach (part; parts)
        {
            auto region = regionOf(part);
            const start = region.getPosition();
            if (resource !is region.getResource() || start < offset)
            {
                if (input !is null)
                {
                    auto previous = input;
                    input = null;
                    previous.close();
                }
                resource = region.getResource();
                input = resource.getInputStream();
                offset = 0;
            }
            const length = resource.contentLength();
            writeText(output, "\r\n--" ~ boundary ~ "\r\n");
            if (contentType !is null)
                writeText(output, "Content-Type: " ~ contentType.toString() ~ "\r\n");
            writeText(output, "Content-Range: " ~ formatRange(start, region.getCount(), length) ~ "\r\n\r\n");
            const count = boundedCount(region, length);
            copyRegion(input, output, start - offset, count);
            offset = start + count;
        }
        writeText(output, "\r\n--" ~ boundary ~ "--");
    }

    private static long boundedCount(ResourceRegion region, long length)
    {
        const remaining = length - region.getPosition();
        return region.getCount() < remaining ? region.getCount() : remaining;
    }

    private static string formatRange(long start, long count, long length)
    {
        return "bytes " ~ decimal(start) ~ "-" ~ decimal(start + count - 1) ~ "/" ~ decimal(length);
    }

    private static void writeText(HttpOutputMessage output, string text)
    {
        foreach (offset, c; text)
        {
            if (c < 128)
                continue;
            char[] ascii = text[0 .. offset].dup;
            size_t pos = offset;
            while (pos < text.length)
            {
                const point = decodeUtf8(text, pos);
                ascii ~= point < 128 ? cast(char) point : '?';
            }
            output.writeBody(cast(const(ubyte)[]) ascii);
            return;
        }
        output.writeBody(cast(const(ubyte)[]) text);
    }

    private static void closeRegion(InputStream input)
    {
        if (input is null)
            return;
        try
            input.close();
        catch (IOException)
        {
        }
    }

    private static void copyRegion(InputStream input, HttpOutputMessage output, long skip, long count)
    {
        ubyte[4096] chunk;
        while (skip > 0)
        {
            const size = cast(size_t)(skip < chunk.length ? skip : chunk.length);
            const n = input.read(chunk[0 .. size]);
            if (n <= 0)
                throw new IOException("Could not skip to the beginning of the resource range");
            skip -= n;
        }
        while (count > 0)
        {
            const size = cast(size_t)(count < chunk.length ? count : chunk.length);
            const n = input.read(chunk[0 .. size]);
            if (n <= 0)
                break;
            output.writeBody(chunk[0 .. n]);
            count -= n;
        }
    }
}

/// Converts to and from Spring's Resource types.
class ResourceHttpMessageConverter : AbstractHttpMessageConverter
{
    private bool supportsReadStreaming;

    this()
    {
        this(true);
    }

    this(bool supportsReadStreaming)
    {
        super(MediaType.ALL);
        this.supportsReadStreaming = supportsReadStreaming;
    }

    protected override bool supports(string typeName)
    {
        return typeName == typeNameOf!Resource || typeName == typeNameOf!AbstractResource
            || typeName == typeNameOf!ByteArrayResource
            || typeName == typeNameOf!InputStreamResource
            || typeName == typeNameOf!ClassPathResource || typeName == typeNameOf!FileSystemResource
            || typeName == typeNameOf!DescriptiveResource;
    }

    protected override Any readInternal(string typeName, HttpInputMessage inputMessage)
    {
        const bool streaming = supportsReadStreaming && typeName == typeNameOf!InputStreamResource;
        if (!streaming && typeName != typeNameOf!Resource && typeName != typeNameOf!AbstractResource
                && typeName != typeNameOf!ByteArrayResource && typeName != typeNameOf!Object
                && typeName != typeNameOf!InputStreamSource)
            throw new HttpMessageNotReadableException("Unsupported resource class: " ~ typeName, null, inputMessage);

        auto headers = inputMessage.getHeaders();
        const name = dispositionFilename(headers.getFirst(HttpHeaders.CONTENT_DISPOSITION));
        auto bytes = inputMessage.getBody().idup;
        if (streaming)
        {
            const length = headers.getContentLength();
            return Any.of(new UploadedStreamResource(bytes, name, length == -1 ? bytes.length : length));
        }
        return Any.of(new UploadedByteResource(bytes, name));
    }

    override void write(Any value, scope const(MediaType)* contentType, HttpOutputMessage output)
    {
        auto streaming = cast(StreamingHttpOutputMessage) output;
        if (streaming is null)
        {
            super.write(value, contentType, output);
            return;
        }
        auto headers = output.getHeaders();
        super.addDefaultHeaders(headers, value, contentType);
        streaming.setBody(new ConverterStreamingBody(this, headers, value, null, contentType));
    }

    /// Adds the resource's default headers without writing its body.
    void addDefaultHeaders(HttpOutputMessage message, Resource resource, scope const(MediaType)* contentType)
    {
        super.addDefaultHeaders(message.getHeaders(), Any.of(resource), contentType);
    }

    protected override MediaType* getDefaultContentType(Any value)
    {
        auto result = new MediaType;
        *result = MediaTypeFactory.getMediaType(asResource(value)).orElse(MediaType.APPLICATION_OCTET_STREAM);
        return result;
    }

    protected override long getContentLength(Any value, scope const(MediaType)* contentType)
    {
        auto resource = asResource(value);
        if (typeid(cast(Object) resource) is typeid(InputStreamResource))
            return -1;
        const length = resource.contentLength();
        return length < 0 ? -1 : length;
    }

    override bool canWriteRepeatedly(Any value, scope const(MediaType)* contentType)
    {
        return cast(InputStreamResource) asResource(value) is null;
    }

    protected override void writeInternal(Any value, HttpOutputMessage output)
    {
        writeContent(asResource(value), output);
    }

    /// Writes the resource and releases the opened input even when a read fails.
    protected void writeContent(Resource resource, HttpOutputMessage output)
    {
        try
        {
            auto input = resource.getInputStream();
            if (input is null)
                return;
            scope (exit)
                closeResource(input);
            try
            {
                ubyte[4096] chunk;
                for (;;)
                {
                    const count = input.read(chunk[]);
                    if (count <= 0)
                        break;
                    output.writeBody(chunk[0 .. count]);
                }
            }
            catch (NullPointerException)
            {
                // Preserve Spring's handling of streams that throw while reading (SPR-13620).
            }
        }
        catch (FileNotFoundException)
        {
            // The resource may disappear between header preparation and opening it.
        }
    }

    private static Resource asResource(Any value)
    {
        auto resource = cast(Resource) value.asObject();
        if (resource is null)
            throw new HttpMessageNotWritableException("Expected a Resource");
        return resource;
    }

    private static void closeResource(InputStream input)
    {
        try
            input.close();
        catch (Exception)
        {
            // A close failure does not replace the original write outcome (SPR-12999).
        }
    }
}

private final class UploadedByteResource : ByteArrayResource
{
    private string filename;

    this(immutable(ubyte)[] bytes, string filename)
    {
        super(bytes);
        this.filename = filename;
    }

    override string getFilename()
    {
        return filename;
    }
}

private final class UploadedStreamResource : InputStreamResource
{
    private string filename;
    private long length;

    this(immutable(ubyte)[] bytes, string filename, long length)
    {
        super(new ByteArrayInputStream(bytes));
        this.filename = filename;
        this.length = length;
    }

    override string getFilename()
    {
        return filename;
    }

    override long contentLength()
    {
        return length;
    }
}

// The filename subset of ContentDisposition.java. The complete value and builder are a separate port.
private string dispositionFilename(string header)
{
    if (header is null)
        return null;
    size_t offset = indexOfByte(header, ';');
    if (trimmedAscii(header[0 .. offset]).length == 0)
        throw new IllegalArgumentException("Content-Disposition header must not be empty");
    string filename;
    while (offset < header.length)
    {
        const start = ++offset;
        offset = parameterEnd(header, offset);
        const part = trimmedAscii(header[start .. offset]);
        if (part.length == 0)
            continue;
        const split = indexOfByte(part, '=');
        if (split == part.length)
            throw new IllegalArgumentException("Invalid content disposition format");
        const attribute = part[0 .. split];
        auto value = part[split + 1 .. $];
        if (value.length >= 2 && value[0] == '"' && value[$ - 1] == '"')
            value = value[1 .. $ - 1];
        if (equalsIgnoreAsciiCase(attribute, "filename*"))
            filename = decodeExtendedFilename(value);
        else if (filename is null && equalsIgnoreAsciiCase(attribute, "filename"))
            filename = decodeQuotedFilename(value);
    }
    return filename;
}

private size_t parameterEnd(string header, size_t offset) pure nothrow @nogc
{
    bool quoted, escaped;
    for (; offset < header.length; offset++)
    {
        const c = header[offset];
        if (c == ';' && !quoted)
            break;
        if (c == '"' && !escaped)
            quoted = !quoted;
        escaped = c == '\\' && !escaped;
    }
    return offset;
}

private string decodeQuotedFilename(string value)
{
    foreach (offset, c; value)
    {
        if (c != '\\')
            continue;
        char[] name = value[0 .. offset].dup;
        for (; offset < value.length; offset++)
        {
            if (value[offset] == '\\' && offset + 1 < value.length && (value[offset + 1] == '\\'
                    || value[offset + 1] == '"'))
                offset++;
            name ~= value[offset];
        }
        return name.idup;
    }
    return value;
}

private string decodeExtendedFilename(string value)
{
    import std.utf : encode;

    const charset = extractFilenameCharset(value);
    auto bytes = decodeFilenamePercentEscapes(value);
    char[] name;
    if (charset == StandardCharsets.UTF_8)
    {
        size_t pos;
        while (pos < bytes.length)
            encode(name, decodeUtf8(bytes, pos));
    }
    else
        foreach (c; bytes)
            encode(name, charset == StandardCharsets.US_ASCII && c >= 128 ? '\uFFFD' : cast(dchar) c);
    return name.length == 0 ? "" : name.idup;
}

private Charset extractFilenameCharset(ref string value)
{
    const first = indexOfByte(value, '\'');
    if (first == value.length)
        return StandardCharsets.US_ASCII;
    const rest = value[first + 1 .. $];
    const second = indexOfByte(rest, '\'');
    if (second == rest.length)
        return StandardCharsets.US_ASCII;
    const charset = Charset.forName(trimmedAscii(value[0 .. first]));
    if (charset != StandardCharsets.UTF_8 && charset != StandardCharsets.ISO_8859_1)
        throw new IllegalArgumentException("Charset must be UTF-8 or ISO-8859-1");
    value = rest[second + 1 .. $];
    return charset;
}

private char[] decodeFilenamePercentEscapes(string value)
{
    char[] bytes;
    for (size_t i = 0; i < value.length; i++)
    {
        const c = value[i];
        if (c == '%')
        {
            if (value.length - i < 3 || hexDigit(value[i + 1]) < 0 || hexDigit(value[i + 2]) < 0)
                throw new IllegalArgumentException("Invalid RFC 5987 filename");
            bytes ~= cast(char)(hexDigit(value[i + 1]) * 16 + hexDigit(value[i + 2]));
            i += 2;
        }
        else if (isFilenameAttributeChar(c))
            bytes ~= c;
        else
            throw new IllegalArgumentException("Invalid RFC 5987 filename");
    }

    return bytes;
}

private bool isFilenameAttributeChar(char c) pure nothrow @nogc
{
    enum punctuation = "!#$&+-.^_\x60|~";
    const lower = c | 0x20;
    return (lower >= 'a' && lower <= 'z') || (c >= '0' && c <= '9') || indexOfByte(punctuation, c) < punctuation.length;
}

private size_t indexOfByte(string text, char target) pure nothrow @nogc
{
    foreach (offset, c; text)
        if (c == target)
            return offset;
    return text.length;
}

private int hexDigit(char c) pure nothrow @nogc
{
    if (c >= '0' && c <= '9')
        return c - '0';
    const lower = c | 0x20;
    return lower >= 'a' && lower <= 'f' ? lower - 'a' + 10 : -1;
}

/// `StringHttpMessageConverter`: `string` bodies, `text/plain` and `*/*`.
class StringHttpMessageConverter : AbstractHttpMessageConverter
{
    /// UTF-8 by default, as Spring Boot configures it (Spring's own default is ISO-8859-1).
    this()
    {
        this(StandardCharsets.UTF_8);
    }

    /// With `defaultCharset`.
    this(Charset defaultCharset)
    {
        super(defaultCharset, MediaType.TEXT_PLAIN, MediaType.ALL);
    }

    protected override bool supports(string typeName)
    {
        return typeName == "string";
    }

    protected override Any readInternal(string typeName, HttpInputMessage inputMessage)
    {
        return Any.of(cast(string) inputMessage.getBody().idup);
    }

    protected override long getContentLength(Any value, scope const(MediaType)* contentType)
    {
        return cast(long) value.get!string.length;
    }

    protected override void writeInternal(Any value, HttpOutputMessage outputMessage)
    {
        outputMessage.writeBody(cast(const(ubyte)[]) value.get!string);
    }
}

/// `ByteArrayHttpMessageConverter`: `ubyte[]` bodies, `application/octet-stream` and `*/*`.
class ByteArrayHttpMessageConverter : AbstractHttpMessageConverter
{
    ///
    this()
    {
        super(MediaType.APPLICATION_OCTET_STREAM, MediaType.ALL);
    }

    protected override bool supports(string typeName)
    {
        return typeName == "ubyte[]" || typeName == "immutable(ubyte)[]" || typeName == "const(ubyte)[]";
    }

    protected override Any readInternal(string typeName, HttpInputMessage inputMessage)
    {
        return Any.of(inputMessage.getBody().dup);
    }

    protected override long getContentLength(Any value, scope const(MediaType)* contentType)
    {
        return cast(long) value.get!(ubyte[]).length;
    }

    protected override void writeInternal(Any value, HttpOutputMessage outputMessage)
    {
        outputMessage.writeBody(value.get!(ubyte[]));
    }
}

/// `HttpMessageConversionException`.
class HttpMessageConversionException : NestedRuntimeException
{
    ///
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }
}

/// `HttpMessageNotReadableException`: the body could not be read (400).
class HttpMessageNotReadableException : HttpMessageConversionException
{
    private HttpInputMessage httpInputMessage;

    ///
    this(string message, Throwable cause, HttpInputMessage httpInputMessage, string file = __FILE__,
            size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
        this.httpInputMessage = httpInputMessage;
    }

    /// The message that could not be read.
    HttpInputMessage getHttpInputMessage() pure nothrow @nogc
    {
        return httpInputMessage;
    }
}

/// `HttpMessageNotWritableException`: the body could not be written (500).
class HttpMessageNotWritableException : HttpMessageConversionException
{
    ///
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }
}
