// Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/util/unit/DataSize.java and
// DataUnit.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors: ported from spring-framework v7.1.0, spring-core/src/main/java/org/springframework/util/unit.
 */

/++
Spring's `org.springframework.util.unit`: `DataSize`, a size in bytes such as `12MB`, and `DataUnit`, its units.

`DataSize` is an immutable value, so it is a struct (ADR-030 section 5); `DataSize.init` is zero bytes. `DataUnit` is a
D enum with Spring's constants in order, and its static `fromSuffix` is a free function (R20).
+/
module flint.util.unit;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException, IllegalStateException, Long;
import flint.java.lang.math : Math;
import flint.util : StringUtils;

@safe:

private enum long bytesPerKb = 1024;
private enum long bytesPerMb = bytesPerKb * 1024;
private enum long bytesPerGb = bytesPerMb * 1024;
private enum long bytesPerTb = bytesPerGb * 1024;

/// A data size in bytes, such as `12MB`.
struct DataSize
{
    private long bytes;

    private this(long bytes) pure nothrow @nogc
    {
        this.bytes = bytes;
    }

    /// `bytes` bytes.
    static DataSize ofBytes(long bytes) pure nothrow @nogc
    {
        return DataSize(bytes);
    }

    /// `kilobytes` kilobytes. Throws `ArithmeticException` on overflow.
    static DataSize ofKilobytes(long kilobytes)
    {
        return DataSize(Math.multiplyExact(kilobytes, bytesPerKb));
    }

    /// `megabytes` megabytes. Throws `ArithmeticException` on overflow.
    static DataSize ofMegabytes(long megabytes)
    {
        return DataSize(Math.multiplyExact(megabytes, bytesPerMb));
    }

    /// `gigabytes` gigabytes. Throws `ArithmeticException` on overflow.
    static DataSize ofGigabytes(long gigabytes)
    {
        return DataSize(Math.multiplyExact(gigabytes, bytesPerGb));
    }

    /// `terabytes` terabytes. Throws `ArithmeticException` on overflow.
    static DataSize ofTerabytes(long terabytes)
    {
        return DataSize(Math.multiplyExact(terabytes, bytesPerTb));
    }

    /// `amount` of `unit`. Throws `ArithmeticException` on overflow.
    static DataSize of(long amount, DataUnit unit)
    {
        return DataSize(Math.multiplyExact(amount, unitBytes(unit)));
    }

    /// `text`, such as `12MB` or `-5`, in bytes when it has no unit suffix.
    static DataSize parse(string text)
    {
        return parse(text, DataUnit.BYTES);
    }

    /++
    `text`, such as `12MB`, in `defaultUnit` when it has no suffix. Whitespace anywhere is ignored. Anything else
    throws `IllegalArgumentException("'<text>' is not a valid data size")` with the reason as its cause.
    +/
    static DataSize parse(string text, DataUnit defaultUnit)
    {
        try
        {
            const trimmed = StringUtils.trimAllWhitespace(text);
            const digitsEnd = numberEnd(trimmed);
            if (digitsEnd == 0)
                throw new IllegalStateException("'" ~ text ~ "' does not match data size pattern");
            const suffix = trimmed[digitsEnd .. $];
            const unit = suffix.length ? fromSuffix(suffix) : defaultUnit;
            return of(Long.parseLong(trimmed[0 .. digitsEnd]), unit);
        }
        catch (Exception cause)
            throw new IllegalArgumentException("'" ~ text ~ "' is not a valid data size", cause);
    }

    /// Whether this size is negative.
    bool isNegative() const pure nothrow @nogc
    {
        return bytes < 0;
    }

    /// The bytes.
    long toBytes() const pure nothrow @nogc
    {
        return bytes;
    }

    /// Whole kilobytes, truncated toward zero.
    long toKilobytes() const pure nothrow @nogc
    {
        return bytes / bytesPerKb;
    }

    /// Whole megabytes, truncated toward zero.
    long toMegabytes() const pure nothrow @nogc
    {
        return bytes / bytesPerMb;
    }

    /// Whole gigabytes, truncated toward zero.
    long toGigabytes() const pure nothrow @nogc
    {
        return bytes / bytesPerGb;
    }

    /// Whole terabytes, truncated toward zero.
    long toTerabytes() const pure nothrow @nogc
    {
        return bytes / bytesPerTb;
    }

    /// Negative, zero or positive as this size is smaller than, equal to or larger than `other`.
    int compareTo(DataSize other) const pure nothrow @nogc
    {
        return Long.compare(bytes, other.bytes);
    }

    /// `compareTo` for D's relational operators.
    int opCmp(DataSize other) const pure nothrow @nogc
    {
        return compareTo(other);
    }

    /// Whether `other` is the same number of bytes (R11); `==` compares the same way.
    bool equals(DataSize other) const pure nothrow @nogc
    {
        return bytes == other.bytes;
    }

    /// Java's `Long.hashCode(bytes)`.
    int hashCode() const pure nothrow @nogc
    {
        return cast(int)(bytes ^ (cast(ulong) bytes >>> 32));
    }

    /// The bytes followed by `B`, such as `1024B`.
    string toString() const pure nothrow
    {
        return decimal(bytes) ~ "B";
    }
}

/// A unit of data size, with Spring's suffixes `B`, `KB`, `MB`, `GB` and `TB`.
enum DataUnit
{
    /// Bytes, suffix `B`.
    BYTES,
    /// Kilobytes, suffix `KB`.
    KILOBYTES,
    /// Megabytes, suffix `MB`.
    MEGABYTES,
    /// Gigabytes, suffix `GB`.
    GIGABYTES,
    /// Terabytes, suffix `TB`.
    TERABYTES,
}

private static immutable string[5] suffixes = ["B", "KB", "MB", "GB", "TB"];

/// Java's static `DataUnit.fromSuffix` (R20): the unit whose suffix is exactly `suffix`, case-sensitive. Throws
/// `IllegalArgumentException("Unknown data unit suffix '<suffix>'")` otherwise.
DataUnit fromSuffix(string suffix)
{
    foreach (index, candidate; suffixes)
        if (candidate == suffix)
            return cast(DataUnit) index;
    throw new IllegalArgumentException("Unknown data unit suffix '" ~ suffix ~ "'");
}

// One unit in bytes: Java's package-private DataUnit.size().toBytes().
private long unitBytes(DataUnit unit) pure nothrow @nogc
{
    final switch (unit)
    {
    case DataUnit.BYTES:
        return 1;
    case DataUnit.KILOBYTES:
        return bytesPerKb;
    case DataUnit.MEGABYTES:
        return bytesPerMb;
    case DataUnit.GIGABYTES:
        return bytesPerGb;
    case DataUnit.TERABYTES:
        return bytesPerTb;
    }
}

// Spring's pattern ^([+\-]?\d+)([a-zA-Z]{0,2})$: the end of the signed digits, or 0 when `text` doesn't match.
private size_t numberEnd(scope const(char)[] text) pure nothrow @nogc
{
    size_t index = text.length && (text[0] == '+' || text[0] == '-') ? 1 : 0;
    const digitsStart = index;
    while (index < text.length && text[index] >= '0' && text[index] <= '9')
        ++index;
    if (index == digitsStart || text.length - index > 2)
        return 0;
    foreach (c; text[index .. $])
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
            return 0;
    return index;
}
