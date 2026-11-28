/*
 * Copyright (c) 1997, 2025, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Ported from openjdk 21.0.13:
//   src/java.base/share/classes/java/util/jar/Manifest.java
//   src/java.base/share/classes/java/util/jar/Attributes.java
// Modified by the Flint authors.

/++
`java.util.jar` manifest reading and writing.

The manifest grammar is OpenJDK's: CR, LF and CRLF line endings, continuation lines introduced by one space,
UTF-8 values, and 72-byte writing with a continuation space. `Attributes` maps Java's `Object` keys and values
to `Any` (R23); public `putValue` and `getValue` use the `String` and `Name` forms. Its key and value views are
D slices (R10), keeping the leaf free of the aggregate `flint.java.util` containers.
+/
module flint.java.util.jar;

import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.java.io : IOException, InputStream, OutputStream;
import flint.java.lang : ClassCastException, IllegalArgumentException, NullPointerException, stringHashCode;

@safe:

// ---------------------------------------------------------------------------------------------------------------
// Attributes

/++
Java's `Attributes`: a manifest section's attribute names and values, in insertion order.

`putValue(String, String)` and the `Name` overloads keep Java's case-insensitive attribute-name rules; any other
key or a non-text value is a `ClassCastException`, as in Java.
+/
class Attributes
{
    /// Java's nested `Attributes.Name`.
    alias Name = .Name;

    /// An entry of `entrySet`.
    struct Entry
    {
        private Any key_;
        private Any value_;
        private Attributes owner_;

        /// The attribute name.
        Any getKey()
        {
            return key_;
        }

        /// The attribute value.
        Any getValue()
        {
            return value_;
        }

        /// Replace the value, in the section too.
        Any setValue(Any value)
        {
            auto previous = value_;
            value_ = value;
            if (owner_ !is null)
                owner_.put(key_, value);
            return previous;
        }
    }

    private NameKey[] keys_;
    private Any[] values_;

    /// An empty section.
    this()
    {
    }

    /// An empty section with room for `size` attributes.
    this(int size)
    {
        if (size < 0)
            throw new IllegalArgumentException("Illegal initial capacity");
        keys_.reserve(size);
        values_.reserve(size);
    }

    /// A section with the same attributes as `attr`.
    this(Attributes attr)
    {
        if (attr !is null)
            foreach (i; 0 .. attr.size())
            {
                keys_ ~= attr.keys_[i];
                values_ ~= attr.values_[i];
            }
    }

    /// The value of `name`, or null.
    Any get(Any name)
    {
        const at = slotOf(NameKey(asName(name)));
        return at < 0 ? Any.init : values_[cast(size_t) at];
    }

    /// The value of `name`, or null.
    Any getOrDefault(Any name, Any defaultValue)
    {
        const at = slotOf(NameKey(asName(name)));
        return at < 0 ? defaultValue : values_[cast(size_t) at];
    }

    /// The value of `name`, or null.
    string getValue(string name)
    {
        return getValue(Name.of(name));
    }

    /// The value of `name`, or null.
    string getValue(const Name name)
    {
        const at = slotOf(NameKey(name));
        return at < 0 ? null : values_[cast(size_t) at].get!string;
    }

    /// Associate `value` with `name`; the previous value or null. Throws `ClassCastException` for a non-`Name`
    /// key or a non-text value.
    Any put(Any name, Any value)
    {
        NameKey key = NameKey(asName(name));
        Any text = asText(value);
        const at = slotOf(key);
        if (at >= 0)
        {
            auto previous = values_[cast(size_t) at];
            values_[cast(size_t) at] = text;
            return previous;
        }
        keys_ ~= key;
        values_ ~= text;
        return Any.init;
    }

    /// Associate `value` with `name`; the previous value or null.
    string putValue(string name, string value)
    {
        return put(Any.of(Name.of(name)), Any.of(value)).get!string;
    }

    /// Associate `value` with `name`; the previous value or null.
    Any putIfAbsent(Any name, Any value)
    {
        const key = NameKey(asName(name));
        const at = slotOf(key);
        if (at >= 0)
            return values_[cast(size_t) at];
        return put(name, value);
    }

    /// Remove `name`; the previous value or null.
    Any remove(Any name)
    {
        const at = slotOf(NameKey(asName(name)));
        if (at < 0)
            return Any.init;
        const position = cast(size_t) at;
        auto previous = values_[position];
        foreach (i; position + 1 .. keys_.length)
        {
            keys_[i - 1] = keys_[i];
            values_[i - 1] = values_[i];
        }
        --keys_.length;
        --values_.length;
        return previous;
    }

    /// Whether some key maps to `value`.
    bool containsValue(Any value)
    {
        foreach (candidate; values_)
            if (candidate == value)
                return true;
        return false;
    }

    /// Whether `name` is mapped.
    bool containsKey(Any name)
    {
        return slotOf(NameKey(asName(name))) >= 0;
    }

    /// Copy every attribute of `attr`.
    void putAll(Attributes attr)
    {
        if (attr is null)
            throw new ClassCastException("Attributes.putAll requires an Attributes");
        foreach (i; 0 .. attr.size())
            put(Any.of(attr.keys_[i].name), attr.values_[i]);
    }

    /// Remove every attribute.
    void clear()
    {
        keys_ = null;
        values_ = null;
    }

    /// The number of attributes.
    int size()
    {
        return cast(int) keys_.length;
    }

    /// Whether there are no attributes.
    bool isEmpty()
    {
        return keys_.length == 0;
    }

    /// The names, in insertion order.
    Name[] keySet()
    {
        auto result = new Name[keys_.length];
        foreach (i, key; keys_)
            result[i] = key.name;
        return result;
    }

    /// The values, in insertion order.
    Any[] values()
    {
        return values_.dup;
    }

    /// The entries, in insertion order.
    Entry[] entrySet()
    {
        auto result = new Entry[keys_.length];
        foreach (i, key; keys_)
            result[i] = Entry(Any.of(key.name), values_[i], this);
        return result;
    }

    /// Call `action` for each attribute in insertion order.
    void forEach(void delegate(Any, Any) @safe action)
    {
        foreach (i, key; keys_)
            action(Any.of(key.name), values_[i]);
    }

    /// `Map.equals`: another section with the same mappings.
    override bool opEquals(Object o)
    {
        return equals(o);
    }

    /// `Map.equals`: another section with the same mappings.
    bool equals(Object o)
    {
        if (o is this)
            return true;
        auto that = cast(Attributes) o;
        if (that is null || that.size() != size())
            return false;
        foreach (i, key; keys_)
        {
            const at = that.slotOf(key);
            if (at < 0 || !(that.values_[cast(size_t) at] == values_[i]))
                return false;
        }
        return true;
    }

    /// Java's `Map.hashCode`: the sum of the entries' hash codes.
    int hashCode()
    {
        int h;
        foreach (i, key; keys_)
            h += keyHash(key) ^ valueHash(values_[i]);
        return h;
    }

    /// Java's `Map.hashCode`.
    override size_t toHash() @safe nothrow
    {
        try
            return cast(uint) hashCode();
        catch (Exception)
            return 0;
    }

    /// `{name=value, ...}`.
    override string toString()
    {
        string result = "{";
        foreach (i, key; keys_)
        {
            if (i)
                result ~= ", ";
            auto name = key.name;
            result ~= (name is null ? "null" : name.toString()) ~ "=" ~ values_[i].toString();
        }
        return result ~ "}";
    }

    /// A copy of the attributes.
    Object clone()
    {
        return new Attributes(this);
    }

    private ptrdiff_t slotOf(const NameKey key) const
    {
        foreach (i, candidate; keys_)
            if (candidate == key)
                return cast(ptrdiff_t) i;
        return -1;
    }

    // Write this section to a manifest stream, followed by its blank line.
    void write(OutputStream sink)
    {
        foreach (i, key; keys_)
        {
            auto name = key.name;
            string keyText = name is null ? "null" : name.toString();
            println72(sink, keyText ~ ": " ~ values_[i].get!string);
        }
        println(sink);
    }

    // Write the main section, with Manifest-Version or Signature-Version first.
    void writeMain(OutputStream sink)
    {
        string vername = Name.MANIFEST_VERSION.toString();
        string versionText = getValue(vername);
        if (versionText is null)
        {
            vername = Name.SIGNATURE_VERSION.toString();
            versionText = getValue(vername);
        }
        if (versionText !is null)
        {
            sink.write(cast(const(ubyte)[])(vername ~ ": " ~ versionText));
            println(sink);
        }
        foreach (i, key; keys_)
        {
            auto name = key.name;
            const nameText = name is null ? "null" : name.toString();
            if (versionText !is null && !equalsIgnoreCase(nameText, vername))
                println72(sink, nameText ~ ": " ~ values_[i].get!string);
        }
        println(sink);
    }

    // Read this section from a manifest stream.
    int read(FastInputStream stream, scope ubyte[] lbuf, int lineNumber)
    {
        string name;
        ubyte[] fullLine;

        int len;
        while ((len = stream.readLine(lbuf)) != -1)
        {
            ++lineNumber;
            len = lineContent(lbuf, len);
            if (len == 0)
                break;
            string value;
            if (lbuf[0] == ' ')
            {
                if (name is null)
                    throw new IOException("misplaced continuation line");
                fullLine ~= lbuf[1 .. len];
                if (stream.peek() == ' ')
                    continue;
                value = cast(string) fullLine.idup;
                fullLine = null;
            }
            else
            {
                const nameEnd = headerNameEnd(lbuf, len);
                name = cast(string) lbuf[0 .. nameEnd].idup;
                if (stream.peek() == ' ')
                {
                    fullLine = null;
                    fullLine ~= lbuf[nameEnd + 2 .. len];
                    continue;
                }
                value = cast(string) lbuf[nameEnd + 2 .. len].idup;
            }
            try
                putValue(name, value);
            catch (IllegalArgumentException)
                throw new IOException("invalid header field name: " ~ name);
        }
        return lineNumber;
    }
}

// The key of an Attributes section: a Name with null-safe, case-insensitive equality.
private struct NameKey
{
    Name name;
    string text;

    this(Name name) pure nothrow @nogc
    {
        this.name = name;
        this.text = name is null ? null : name.toString();
    }

    this(const Name name) pure nothrow @nogc
    {
        this.text = name is null ? null : name.toString();
    }

    bool opEquals(const NameKey other) const
    {
        if (text is null || other.text is null)
            return text is other.text;
        return equalsIgnoreCase(text, other.text);
    }

    size_t toHash() const nothrow @safe
    {
        return text is null ? 0 : cast(size_t) cast(uint) stringHashCode(text);
    }
}

private int keyHash(NameKey key) nothrow
{
    return cast(int) key.toHash();
}

private int valueHash(Any value)
{
    if (value.isNull())
        return 0;
    if (value.holds!string)
        return stringHashCode(value.get!string);
    return cast(int) value.toHash();
}

private Name asName(Any value)
{
    if (!value.holds!Name)
        throw new ClassCastException("Attributes keys must be Attributes.Name");
    return value.get!Name;
}

private Any asText(Any value)
{
    if (!value.holds!string)
        throw new ClassCastException("Attributes values must be String");
    return value;
}

// The content length of a manifest line, without its CRLF, LF or CR.
private int lineContent(scope ubyte[] lbuf, int len)
{
    if (len <= 0)
        throw new IOException("empty manifest line");
    ubyte c = lbuf[--len];
    if (c != '\n' && c != '\r')
        throw new IOException("line too long");
    if (len > 0 && lbuf[len - 1] == '\r')
        --len;
    return len;
}

// The end of the attribute name in a header line, before ": ".
private int headerNameEnd(scope ubyte[] lbuf, int len)
{
    int i;
    while (i < len && lbuf[i] != ':')
        ++i;
    if (i >= len || i + 1 >= len || lbuf[i + 1] != ' ')
        throw new IOException("invalid header field");
    return i;
}

// ---------------------------------------------------------------------------------------------------------------
// Name

/// Java's `Attributes.Name`: a validated, case-insensitive manifest attribute name.
class Name
{
    private string name_;
    private int hashCode_;

    /// `Manifest-Version`.
    static immutable Name MANIFEST_VERSION = new immutable Name("Manifest-Version");
    /// `Signature-Version`.
    static immutable Name SIGNATURE_VERSION = new immutable Name("Signature-Version");
    /// `Content-Type`.
    static immutable Name CONTENT_TYPE = new immutable Name("Content-Type");
    /// `Class-Path`.
    static immutable Name CLASS_PATH = new immutable Name("Class-Path");
    /// `Main-Class`.
    static immutable Name MAIN_CLASS = new immutable Name("Main-Class");
    /// `Sealed`.
    static immutable Name SEALED = new immutable Name("Sealed");
    /// `Extension-List`.
    static immutable Name EXTENSION_LIST = new immutable Name("Extension-List");
    /// `Extension-Name`.
    static immutable Name EXTENSION_NAME = new immutable Name("Extension-Name");
    /// `Extension-Installation`.
    static immutable Name EXTENSION_INSTALLATION = new immutable Name("Extension-Installation");
    /// `Implementation-Title`.
    static immutable Name IMPLEMENTATION_TITLE = new immutable Name("Implementation-Title");
    /// `Implementation-Version`.
    static immutable Name IMPLEMENTATION_VERSION = new immutable Name("Implementation-Version");
    /// `Implementation-Vendor`.
    static immutable Name IMPLEMENTATION_VENDOR = new immutable Name("Implementation-Vendor");
    /// `Implementation-Vendor-Id`.
    static immutable Name IMPLEMENTATION_VENDOR_ID = new immutable Name("Implementation-Vendor-Id");
    /// `Implementation-URL`.
    static immutable Name IMPLEMENTATION_URL = new immutable Name("Implementation-URL");
    /// `Specification-Title`.
    static immutable Name SPECIFICATION_TITLE = new immutable Name("Specification-Title");
    /// `Specification-Version`.
    static immutable Name SPECIFICATION_VERSION = new immutable Name("Specification-Version");
    /// `Specification-Vendor`.
    static immutable Name SPECIFICATION_VENDOR = new immutable Name("Specification-Vendor");
    /// `Multi-Release`.
    static immutable Name MULTI_RELEASE = new immutable Name("Multi-Release");

    /// A name from `name`, validated like Java.
    this(string name)
    {
        name_ = name;
        hashCode_ = validate(name);
    }

    /// Java's `Name` constants are immutable; this form also constructs them in `.rodata`.
    this(string name) immutable
    {
        name_ = name;
        hashCode_ = validate(name);
    }

    private static int validate(string name)
    {
        if (name is null)
            throw new NullPointerException("name");
        if (name.length == 0 || name.length > 70)
            throw new IllegalArgumentException(name);
        int h;
        foreach (char c; name)
        {
            if (c >= 'a' && c <= 'z')
                h = h * 31 + (c - 0x20);
            else if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-')
                h = h * 31 + c;
            else
                throw new IllegalArgumentException(name);
        }
        return h;
    }

    /// A new name for `name`.
    static Name of(string name)
    {
        return new Name(name);
    }

    /// Whether `other` is a `Name` with this name, ignoring ASCII case.
    bool equals(const Name other) const
    {
        return other !is null && equalsIgnoreCase(name_, other.name_);
    }

    /// Java's `equals(Object)`.
    bool equals(Object other) const
    {
        auto that = cast(const Name) other;
        return that !is null && equals(that);
    }

    /// `==` through `Object` calls `equals`.
    override bool opEquals(Object other) const
    {
        return equals(other);
    }

    /// The name's hash, case-insensitively.
    int hashCode() const
    {
        return hashCode_;
    }

    /// The name's hash, case-insensitively.
    override size_t toHash() const @safe nothrow
    {
        return cast(size_t) cast(uint) hashCode_;
    }

    /// The name as originally given.
    override string toString() const pure nothrow @nogc
    {
        return name_;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Manifest entries

/++
Java's `Map<String, Attributes>` for `Manifest.getEntries()`, as an insertion-ordered D facade (R10). It is kept
in this module so the leaf never links the aggregate `flint.java.util` containers.
+/
class Entries
{
    private string[] keys_;
    private Attributes[] values_;

    /// An empty entry map.
    this()
    {
    }

    /// The attributes for `name`, or null.
    Attributes get(string name)
    {
        const at = slotOf(name);
        return at < 0 ? null : values_[cast(size_t) at];
    }

    /// Map `name` to `attrs`; the previous value or null.
    Attributes put(string name, Attributes attrs)
    {
        const at = slotOf(name);
        if (at >= 0)
        {
            auto previous = values_[cast(size_t) at];
            values_[cast(size_t) at] = attrs;
            return previous;
        }
        keys_ ~= name;
        values_ ~= attrs;
        return null;
    }

    /// Remove `name`; the previous value or null.
    Attributes remove(string name)
    {
        const at = slotOf(name);
        if (at < 0)
            return null;
        const position = cast(size_t) at;
        auto previous = values_[position];
        foreach (i; position + 1 .. keys_.length)
        {
            keys_[i - 1] = keys_[i];
            values_[i - 1] = values_[i];
        }
        --keys_.length;
        --values_.length;
        return previous;
    }

    /// Whether `name` is mapped.
    bool containsKey(string name) const
    {
        return slotOf(name) >= 0;
    }

    /// Remove every entry.
    void clear()
    {
        keys_ = null;
        values_ = null;
    }

    /// The number of entries.
    int size() const
    {
        return cast(int) keys_.length;
    }

    /// Whether there are no entries.
    bool isEmpty() const
    {
        return keys_.length == 0;
    }

    /// The entry names, in insertion order.
    string[] keySet() const
    {
        return keys_.dup;
    }

    /// Call `action` for each entry in insertion order.
    void forEach(void delegate(string, Attributes) @safe action)
    {
        foreach (i, key; keys_)
            action(key, values_[i]);
    }

    /// Another map with the same entries.
    override bool opEquals(Object o)
    {
        return equals(o);
    }

    /// Another map with the same entries.
    bool equals(Object o)
    {
        auto that = cast(Entries) o;
        if (that is null || that.size() != size())
            return false;
        foreach (i, key; keys_)
        {
            const at = that.slotOf(key);
            if (at < 0 || !values_[i].equals(that.values_[cast(size_t) at]))
                return false;
        }
        return true;
    }

    /// Java's `Map.hashCode`.
    int hashCode()
    {
        int h;
        foreach (i, key; keys_)
            h += stringHashCode(key) ^ values_[i].hashCode();
        return h;
    }

    /// Java's `Map.hashCode`.
    override size_t toHash() @safe nothrow
    {
        try
            return cast(uint) hashCode();
        catch (Exception)
            return 0;
    }

    /// `{name=attrs, ...}`.
    override string toString()
    {
        string result = "{";
        foreach (i, key; keys_)
        {
            if (i)
                result ~= ", ";
            result ~= key ~ "=" ~ values_[i].toString();
        }
        return result ~ "}";
    }

    private ptrdiff_t slotOf(string name) const
    {
        foreach (i, candidate; keys_)
            if (candidate == name)
                return cast(ptrdiff_t) i;
        return -1;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Manifest

/// Java's `Manifest`: main attributes, per-entry attributes, and their stream form.
class Manifest
{
    private Attributes attr_ = new Attributes();
    private Entries entries_ = new Entries();

    /// An empty manifest.
    this()
    {
    }

    /// A manifest read from `stream`.
    this(InputStream stream)
    {
        read(stream);
    }

    /// A copy of `man`.
    this(Manifest man)
    {
        attr_ = new Attributes(man.getMainAttributes());
        man.getEntries().forEach((string name, Attributes value) { entries_.put(name, value); });
    }

    /// The main attributes.
    Attributes getMainAttributes()
    {
        return attr_;
    }

    /// The per-entry attributes, keyed by entry name.
    Entries getEntries()
    {
        return entries_;
    }

    /// The attributes for `name`, or null.
    Attributes getAttributes(string name)
    {
        return entries_.get(name);
    }

    /// Remove every main and per-entry attribute.
    void clear()
    {
        attr_.clear();
        entries_.clear();
    }

    /// Write the manifest to `sink`.
    void write(OutputStream sink)
    {
        attr_.writeMain(sink);
        entries_.forEach((string name, Attributes attrs) {
            if (name is null)
                return;
            println72(sink, "Name: " ~ name);
            attrs.write(sink);
        });
        sink.flush();
    }

    /// Read additional attributes from `stream`, merging them with the current ones.
    void read(InputStream stream)
    {
        auto fis = new FastInputStream(stream);
        ubyte[512] lbuf;
        int lineNumber = attr_.read(fis, lbuf[], 0);
        int ecount, acount;
        int asize = 2;
        string name;
        bool skipEmptyLines = true;
        ubyte[] lastline;

        int len;
        while ((len = fis.readLine(lbuf[])) != -1)
        {
            ubyte c = lbuf[--len];
            ++lineNumber;

            if (c != '\n' && c != '\r')
                throw new IOException("manifest line too long");
            if (len > 0 && lbuf[len - 1] == '\r')
                --len;
            if (len == 0 && skipEmptyLines)
                continue;
            skipEmptyLines = false;

            if (name is null)
            {
                name = parseName(lbuf[], len);
                if (name is null)
                    throw new IOException("invalid manifest format");
                if (fis.peek() == ' ')
                {
                    lastline = lbuf[6 .. len].dup;
                    continue;
                }
            }
            else
            {
                auto buf = new ubyte[lastline.length + len - 1];
                buf[0 .. lastline.length] = lastline[];
                buf[lastline.length .. $] = lbuf[1 .. len];
                if (fis.peek() == ' ')
                {
                    lastline = buf;
                    continue;
                }
                name = cast(string) buf.idup;
                lastline = null;
            }
            auto section = getAttributes(name);
            if (section is null)
            {
                section = new Attributes(asize);
                entries_.put(name, section);
            }
            lineNumber = section.read(fis, lbuf[], lineNumber);
            ++ecount;
            acount += section.size();
            asize = acount / ecount > 2 ? acount / ecount : 2;
            name = null;
            skipEmptyLines = true;
        }
    }

    private string parseName(scope ubyte[] lbuf, int len)
    {
        if (len >= 6 && toLower(lbuf[0]) == 'n' && toLower(lbuf[1]) == 'a' && toLower(lbuf[2]) == 'm'
                && toLower(lbuf[3]) == 'e' && lbuf[4] == ':' && lbuf[5] == ' ')
            return cast(string) lbuf[6 .. len].idup;
        return null;
    }

    /// Another `Manifest` with equal main and entry attributes.
    override bool opEquals(Object o)
    {
        return equals(o);
    }

    /// Another `Manifest` with equal main and entry attributes.
    bool equals(Object o)
    {
        auto that = cast(Manifest) o;
        return that !is null && attr_.equals(that.attr_) && entries_.equals(that.entries_);
    }

    /// Java's `Manifest.hashCode`.
    int hashCode()
    {
        return attr_.hashCode() + entries_.hashCode();
    }

    /// Java's `Manifest.hashCode`.
    override size_t toHash() @safe nothrow
    {
        try
            return cast(uint) hashCode();
        catch (Exception)
            return 0;
    }

    /// A shallow copy of the manifest.
    Object clone()
    {
        return new Manifest(this);
    }

    /// `{main=..., entries=...}`.
    override string toString()
    {
        return "{main=" ~ attr_.toString() ~ ", entries=" ~ entries_.toString() ~ "}";
    }
}

private int toLower(int c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? 'a' + (c - 'A') : c;
}

private bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    if (a.length != b.length)
        return false;
    foreach (i; 0 .. a.length)
        if (toLower(a[i]) != toLower(b[i]))
            return false;
    return true;
}

private void println72(OutputStream sink, string line)
{
    if (line.length)
    {
        auto bytes = cast(const(ubyte)[]) line;
        sink.write(bytes[0 .. 1]);
        size_t pos = 1;
        while (bytes.length - pos > 71)
        {
            sink.write(bytes[pos .. pos + 71]);
            pos += 71;
            println(sink);
            sink.write(' ');
        }
        sink.write(bytes[pos .. $]);
    }
    println(sink);
}

private void println(OutputStream sink)
{
    sink.write('\r');
    sink.write('\n');
}

// Java's Manifest.FastInputStream: a buffered input with manifest line endings.
private final class FastInputStream
{
    private InputStream in_;
    private ubyte[] buf_;
    private int count_;
    private int pos_;

    this(InputStream in_)
    {
        this.in_ = in_;
        buf_ = new ubyte[8192];
    }

    int read()
    {
        if (pos_ >= count_)
        {
            fill();
            if (pos_ >= count_)
                return -1;
        }
        return buf_[pos_++];
    }

    int peek()
    {
        if (pos_ == count_)
            fill();
        return pos_ == count_ ? -1 : buf_[pos_];
    }

    int readLine(scope ubyte[] b)
    {
        int total;
        while (total < b.length)
        {
            const c = read();
            if (c < 0)
                return -1;
            b[total++] = cast(ubyte) c;
            if (c == '\n')
                break;
            if (c == '\r')
            {
                if (peek() == '\n')
                {
                    read();
                    if (total < b.length)
                        b[total++] = cast(ubyte) '\n';
                    else
                    {
                        --total;
                        b[total] = cast(ubyte) '\n';
                        ++total;
                    }
                }
                break;
            }
        }
        return total;
    }

    private void fill()
    {
        count_ = 0;
        pos_ = 0;
        const n = in_.read(buf_[], 0, cast(int) buf_.length);
        if (n > 0)
            count_ = n;
    }
}
