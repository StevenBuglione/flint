// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/origin/ (Origin.java, OriginProvider.java, OriginTrackedValue.java, TextResourceOrigin.java).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: a resource is described by its name (Flint has no class path), and tracked values
// are strings, the only kind the loaders produce.

/// `org.springframework.boot.origin`: where a configuration value came from, for error messages and failure
/// analysis (`class path resource [application.yaml] - 3:9`).
module flint.boot.origin;

@safe:

/// The origin of an item, such as a property value read from a file.
interface Origin
{
    /// The origin's parent (the file an import came from), or `null`.
    Origin getParent();

    /// A human-readable description of the origin.
    string toString() const;
}

/// Something that knows its origin.
interface OriginProvider
{
    /// The origin, or `null` when it is unknown.
    Origin getOrigin();
}

/// An origin inside a text resource, at a zero-based line and column.
final class TextResourceOrigin : Origin
{
    /// A zero-based position in the text; `toString` shows it one-based, as editors do.
    static struct Location
    {
        private int line;
        private int column;

        /// The location at zero-based `line` and `column`.
        this(int line, int column) pure nothrow @nogc
        {
            this.line = line;
            this.column = column;
        }

        /// The zero-based line.
        int getLine() const pure nothrow @nogc
        {
            return line;
        }

        /// The zero-based column.
        int getColumn() const pure nothrow @nogc
        {
            return column;
        }

        /// `line:column`, both one-based.
        string toString() const pure
        {
            import std.conv : to;

            return (line + 1).to!string ~ ":" ~ (column + 1).to!string;
        }
    }

    private string resource;
    private Location location;
    private bool hasLocation;

    /// The origin at `location` in `resource` (a description such as `class path resource [application.yaml]`).
    this(string resource, Location location) pure nothrow
    {
        this.resource = resource;
        this.location = location;
        this.hasLocation = true;
    }

    /// The resource's description.
    string getResource() const pure nothrow @nogc
    {
        return resource;
    }

    /// The location in the resource.
    Location getLocation() const pure nothrow @nogc
    {
        return location;
    }

    Origin getParent()
    {
        return null;
    }

    override string toString() const pure
    {
        return (resource.length ? resource : "unknown resource [?]") ~ (hasLocation ? " - " ~ location.toString() : "");
    }
}

/// A value and the origin it was read from.
final class OriginTrackedValue : OriginProvider
{
    private string value;
    private Origin origin;

    private this(string value, Origin origin) pure nothrow
    {
        this.value = value;
        this.origin = origin;
    }

    /// `value` tracked to `origin`.
    static OriginTrackedValue of(string value, Origin origin = null) pure nothrow
    {
        return new OriginTrackedValue(value, origin);
    }

    /// The value.
    string getValue() const pure nothrow @nogc
    {
        return value;
    }

    Origin getOrigin()
    {
        return origin;
    }

    override string toString() const pure
    {
        return value;
    }
}
