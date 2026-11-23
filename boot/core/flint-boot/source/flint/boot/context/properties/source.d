// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/context/properties/source/
// (ConfigurationPropertyName.java, ConfigurationPropertySource.java, ConfigurationProperty.java,
// ConfigurationPropertyState.java, InvalidConfigurationPropertyNameException.java,
// MapConfigurationPropertySource.java, IterableConfigurationPropertySource.java,
// DefaultPropertyMapper.java, SystemEnvironmentPropertyMapper.java).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java's CharSequence offsets become D strings, each element keeps its own
// resolved text, and `Object` property values are strings (Flint AOT binds typed values from text).

/// `org.springframework.boot.context.properties.source`: configuration property names with relaxed binding, and
/// the sources that supply their values.
///
/// A `ConfigurationPropertyName` is the canonical form (`flint.datasource.hikari.maximum-pool-size`). Sources
/// adapt their own spellings to it: `.properties`/YAML keys in camel case, kebab case or underscore notation
/// (`maximumPoolSize`, `maximum-pool-size`, `maximum_pool_size`), and environment variables in upper case with
/// underscores (`FLINT_DATASOURCE_HIKARI_MAXIMUMPOOLSIZE`). Two names are equal when their elements match ignoring
/// case and every non-alphanumeric character, which is Spring Boot's relaxed binding.
module flint.boot.context.properties.source;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, RuntimeException;

@safe:

/// A configuration property name made of dot-separated elements, where `[...]` marks an indexed element
/// (`server.ports[0]`, `my.map[key.with.dots]`).
final class ConfigurationPropertyName
{
    /// The name with no elements.
    static immutable ConfigurationPropertyName EMPTY = new immutable ConfigurationPropertyName(null, null);

    /// The forms in which an element can be read.
    enum Form
    {
        /// The element as written, with only invalid characters removed for adapted names.
        ORIGINAL,
        /// Lower case, keeping dashes.
        DASHED,
        /// Lower case alphanumerics only, the form used for comparison.
        UNIFORM
    }

    private enum ElementType
    {
        EMPTY,
        UNIFORM,
        DASHED,
        NON_UNIFORM,
        INDEXED,
        NUMERICALLY_INDEXED
    }

    private const(string)[] elements;
    private const(ElementType)[] types;

    private this(const(string)[] elements, const(ElementType)[] types) pure nothrow immutable
    {
        this.elements = elements.idup;
        this.types = types.idup;
    }

    private this(const(string)[] elements, const(ElementType)[] types) pure nothrow
    {
        this.elements = elements;
        this.types = types;
    }

    /// The empty name, as a mutable reference for APIs that return `ConfigurationPropertyName`.
    static ConfigurationPropertyName empty() pure nothrow
    {
        return new ConfigurationPropertyName(null, null);
    }

    /// Whether the name has no elements.
    bool isEmpty() const pure nothrow @nogc
    {
        return elements.length == 0;
    }

    /// Whether the last element is indexed (`foo[0]`, `foo[bar]`).
    bool isLastElementIndexed() const pure nothrow @nogc
    {
        return elements.length > 0 && isIndexed(cast(int) elements.length - 1);
    }

    /// Whether any element is indexed.
    bool hasIndexedElement() const pure nothrow @nogc
    {
        foreach (index; 0 .. cast(int) elements.length)
        {
            if (isIndexed(index))
                return true;
        }
        return false;
    }

    /// Whether the element at `elementIndex` is indexed.
    bool isIndexed(int elementIndex) const pure nothrow @nogc
    {
        return indexedType(types[elementIndex]);
    }

    /// Whether the element at `elementIndex` is a numeric index (`[0]`).
    bool isNumericIndex(int elementIndex) const pure nothrow @nogc
    {
        return types[elementIndex] == ElementType.NUMERICALLY_INDEXED;
    }

    /// The last element in `form`, or `""` for the empty name.
    string getLastElement(Form form) const pure
    {
        return elements.length ? getElement(cast(int) elements.length - 1, form) : "";
    }

    /// The element at `elementIndex` in `form`. Indexed elements are returned as written.
    string getElement(int elementIndex, Form form) const pure
    {
        const element = elements[elementIndex];
        const type = types[elementIndex];
        if (indexedType(type))
            return element;
        final switch (form)
        {
        case Form.ORIGINAL:
            if (type != ElementType.NON_UNIFORM)
                return element;
            return convert(element, false, (ch, i) => ch == '_' || validChar(lower(ch), i));
        case Form.DASHED:
            if (type == ElementType.UNIFORM || type == ElementType.DASHED)
                return element;
            return convert(element, true, (ch, i) => validChar(ch, i));
        case Form.UNIFORM:
            if (type == ElementType.UNIFORM)
                return element;
            return convert(element, true, (ch, i) => alphaNumeric(ch));
        }
    }

    /// The number of elements.
    int getNumberOfElements() const pure nothrow @nogc
    {
        return cast(int) elements.length;
    }

    /// This name followed by `suffix`, which may hold several elements (`"bar.baz"`, `"[0]"`). Returns this
    /// name when `suffix` is empty. Throws `InvalidConfigurationPropertyNameException` for an invalid suffix.
    ConfigurationPropertyName append(string suffix) pure
    {
        if (suffix.length == 0)
            return this;
        auto additional = elementsOf(suffix, false);
        return new ConfigurationPropertyName(elements ~ additional.elements, types ~ additional.types);
    }

    /// This name followed by the elements of `suffix`; returns this name when `suffix` is `null`.
    ConfigurationPropertyName append(const ConfigurationPropertyName suffix) pure
    {
        if (suffix is null)
            return this;
        return new ConfigurationPropertyName(elements ~ suffix.elements, types ~ suffix.types);
    }

    /// The name without its last element; the empty name for a name of one element or none.
    ConfigurationPropertyName getParent() pure
    {
        return elements.length <= 1 ? empty() : chop(cast(int) elements.length - 1);
    }

    /// The first `size` elements; this name when `size` is at least its length.
    ConfigurationPropertyName chop(int size) pure
    {
        if (size >= elements.length)
            return this;
        return new ConfigurationPropertyName(elements[0 .. size], types[0 .. size]);
    }

    /// The elements from `offset` on. Throws `IndexOutOfBoundsException` when `offset` is out of range.
    ConfigurationPropertyName subName(int offset) pure
    {
        import std.conv : to;

        if (offset == 0)
            return this;
        if (offset == elements.length)
            return empty();
        if (offset < 0 || offset > elements.length)
            throw new IndexOutOfBoundsException(
                    "Offset: " ~ offset.to!string ~ ", NumberOfElements: " ~ elements.length.to!string);
        return new ConfigurationPropertyName(elements[offset .. $], types[offset .. $]);
    }

    /// Whether this name is the direct parent of `name`.
    bool isParentOf(const ConfigurationPropertyName name) const pure
    {
        notNull(name);
        if (elements.length + 1 != name.elements.length)
            return false;
        return isAncestorOf(name);
    }

    /// Whether this name is a parent, grandparent or further ancestor of `name`.
    bool isAncestorOf(const ConfigurationPropertyName name) const pure
    {
        notNull(name);
        if (elements.length >= name.elements.length)
            return false;
        return endsWithElementsEqualTo(name);
    }

    /// Orders names element by element: shorter names and indexed elements first, numeric indexes numerically.
    int compareTo(const ConfigurationPropertyName other) const pure
    {
        import std.conv : to;

        const l1 = elements.length;
        const l2 = other.elements.length;
        size_t i1, i2;
        while (i1 < l1 || i2 < l2)
        {
            if (i1 >= l1)
                return -1;
            if (i2 >= l2)
                return 1;
            const type1 = types[i1];
            const type2 = other.types[i2];
            const e1 = getElement(cast(int) i1++, Form.UNIFORM);
            const e2 = other.getElement(cast(int) i2++, Form.UNIFORM);
            const indexed1 = indexedType(type1), indexed2 = indexedType(type2);
            if (indexed1 != indexed2)
                return indexed1 ? -1 : 1;
            int result;
            if (type1 == ElementType.NUMERICALLY_INDEXED && type2 == ElementType.NUMERICALLY_INDEXED)
            {
                const v1 = e1.to!long, v2 = e2.to!long;
                result = v1 < v2 ? -1 : (v1 > v2 ? 1 : 0);
            }
            else
                result = e1 < e2 ? -1 : (e1 > e2 ? 1 : 0);
            if (result != 0)
                return result;
        }
        return 0;
    }

    /// D's ordering, from `compareTo`.
    override int opCmp(Object other) const
    {
        auto name = cast(const ConfigurationPropertyName) other;
        return name is null ? 1 : compareTo(name);
    }

    /// Relaxed equality: elements match ignoring case, dashes and other non-alphanumeric characters; indexed
    /// elements match exactly.
    bool equals(const ConfigurationPropertyName other) const pure
    {
        if (other is this)
            return true;
        if (other is null || elements.length != other.elements.length)
            return false;
        if (hashCode() != other.hashCode())
            return false;
        return endsWithElementsEqualTo(other);
    }

    /// `equals`, as D's `==`.
    override bool opEquals(Object other) const
    {
        auto name = cast(const ConfigurationPropertyName) other;
        return name !is null && equals(name);
    }

    /// A hash consistent with `equals`: lower-cased alphanumerics of each element.
    int hashCode() const pure nothrow @nogc
    {
        int hash;
        foreach (index, element; elements)
        {
            const indexed = indexedType(types[index]);
            int elementHash;
            foreach (char ch; element)
            {
                const c = indexed ? ch : lower(ch);
                if (alphaNumeric(c))
                    elementHash = 31 * elementHash + c;
            }
            hash = 31 * hash + elementHash;
        }
        return hash;
    }

    /// `hashCode`, as D's `toHash`.
    override size_t toHash() const nothrow
    {
        return cast(size_t) hashCode();
    }

    /// The canonical form: lower-case dashed elements joined by `.`, indexed elements in `[...]`.
    override string toString() const pure
    {
        string result;
        foreach (index; 0 .. cast(int) elements.length)
        {
            const indexed = isIndexed(index);
            if (result.length && !indexed)
                result ~= '.';
            if (indexed)
                result ~= "[" ~ getElement(index, Form.ORIGINAL) ~ "]";
            else
                result ~= getElement(index, Form.DASHED);
        }
        return result;
    }

    /// The name as an environment variable: upper-case uniform elements joined by `_` (`FLINT_MAIN_BANNERMODE`).
    string toSystemEnvironmentString(bool upperCase = true) const pure
    {
        import std.uni : toUpper;

        string result;
        foreach (index; 0 .. cast(int) elements.length)
        {
            if (result.length)
                result ~= '_';
            result ~= getElement(index, Form.UNIFORM);
        }
        return upperCase ? result.toUpper : result;
    }

    /// The legacy environment variable form, which keeps dashes as underscores (`FLINT_MAIN_BANNER_MODE`).
    string toLegacySystemEnvironmentString() const pure
    {
        import std.array : replace;
        import std.uni : toUpper;

        string result;
        foreach (index; 0 .. cast(int) elements.length)
        {
            if (result.length)
                result ~= '_';
            result ~= getElement(index, Form.ORIGINAL).replace("-", "_");
        }
        return result.toUpper;
    }

    /// Whether `name` is a valid configuration property name.
    static bool isValid(string name) pure
    {
        return name !is null && ofIfValid(name) !is null;
    }

    /// The name parsed from canonical text. Throws `InvalidConfigurationPropertyNameException` when `name` is
    /// not valid (upper case, leading dash, `_`, unbalanced brackets) and `IllegalArgumentException` for `null`.
    static ConfigurationPropertyName of(string name) pure
    {
        if (name is null)
            throw new IllegalArgumentException("'name' must not be null");
        auto parsed = elementsOf(name, false);
        return new ConfigurationPropertyName(parsed.elements, parsed.types);
    }

    /// The name parsed from canonical text, or `null` when it is not valid.
    static ConfigurationPropertyName ofIfValid(string name) pure
    {
        if (name is null)
            return null;
        auto parsed = elementsOf(name, true);
        if (!parsed.valid)
            return null;
        return new ConfigurationPropertyName(parsed.elements, parsed.types);
    }

    /// Adapt text in another notation (camel case, underscores, upper case) to a name, splitting on
    /// `separator` and processing each element with `elementValueProcessor` when given.
    static ConfigurationPropertyName adapt(string name, char separator,
            string delegate(string) pure @safe elementValueProcessor = null) pure
    {
        if (name is null)
            throw new IllegalArgumentException("Name must not be null");
        if (name.length == 0)
            return empty();
        auto parsed = parse(name, separator, elementValueProcessor);
        return new ConfigurationPropertyName(parsed.elements, parsed.types);
    }

private:
    static struct Parsed
    {
        string[] elements;
        ElementType[] types;
        bool valid = true;
    }

    static Parsed elementsOf(string name, bool returnInvalid) pure
    {
        if (name.length == 0)
            return Parsed.init;
        if (name[0] == '.' || name[$ - 1] == '.' || name[$ - 1] == '[')
        {
            if (returnInvalid)
                return Parsed(null, null, false);
            throw new InvalidConfigurationPropertyNameException(name, [
                name[0] == '.' || name[$ - 1] == '.' ? '.' : '['
            ]);
        }
        auto parsed = parse(name, '.', null);
        foreach (index, type; parsed.types)
        {
            if (type == ElementType.NON_UNIFORM)
            {
                if (returnInvalid)
                    return Parsed(null, null, false);
                char[] invalid;
                foreach (i, char ch; parsed.elements[index])
                {
                    if (!validChar(ch, i))
                        invalid ~= ch;
                }
                throw new InvalidConfigurationPropertyNameException(name, invalid.idup);
            }
        }
        return parsed;
    }

    static Parsed parse(string source, char separator, string delegate(string) pure @safe processor) pure
    {
        Parsed parsed;
        int openBrackets;
        size_t start;
        ElementType type = ElementType.EMPTY;
        void add(size_t from, size_t to, ElementType elementType)
        {
            if (to <= from || elementType == ElementType.EMPTY)
                return;
            string element = source[from .. to];
            if (processor !is null)
            {
                auto resolved = parse(processor(element), '.', null);
                if (resolved.elements.length != 1)
                    throw new RuntimeException("Resolved element must not contain multiple elements");
                element = resolved.elements[0];
                elementType = resolved.types[0];
            }
            parsed.elements ~= element;
            parsed.types ~= elementType;
        }

        foreach (i, char ch; source)
        {
            if (ch == '[')
            {
                if (openBrackets == 0)
                {
                    add(start, i, type);
                    start = i + 1;
                    type = ElementType.NUMERICALLY_INDEXED;
                }
                openBrackets++;
            }
            else if (ch == ']')
            {
                openBrackets--;
                if (openBrackets == 0)
                {
                    add(start, i, type);
                    start = i + 1;
                    type = ElementType.EMPTY;
                }
            }
            else if (!indexedType(type) && ch == separator)
            {
                add(start, i, type);
                start = i + 1;
                type = ElementType.EMPTY;
            }
            else
                type = updateType(type, ch, i - start);
        }
        if (openBrackets != 0)
            type = ElementType.NON_UNIFORM;
        add(start, source.length, type);
        return parsed;
    }

    static ElementType updateType(ElementType existing, char ch, size_t index) pure nothrow @nogc
    {
        if (indexedType(existing))
        {
            if (existing == ElementType.NUMERICALLY_INDEXED && !numeric(ch))
                return ElementType.INDEXED;
            return existing;
        }
        if (existing == ElementType.EMPTY && validChar(ch, index))
            return index == 0 ? ElementType.UNIFORM : ElementType.NON_UNIFORM;
        if (existing == ElementType.UNIFORM && ch == '-')
            return ElementType.DASHED;
        if (!validChar(ch, index))
        {
            if (existing == ElementType.EMPTY && !validChar(lower(ch), index))
                return ElementType.EMPTY;
            return ElementType.NON_UNIFORM;
        }
        return existing;
    }

    bool endsWithElementsEqualTo(const ConfigurationPropertyName name) const pure
    {
        foreach_reverse (index; 0 .. elements.length)
        {
            if (elementDiffers(name, index))
                return false;
        }
        return true;
    }

    bool elementDiffers(const ConfigurationPropertyName other, size_t i) const pure
    {
        const type1 = types[i], type2 = other.types[i];
        const e1 = elements[i], e2 = other.elements[i];
        if (fastEquality(type1) && fastEquality(type2))
            return e1 != e2;
        if (dashIgnoring(type1) && dashIgnoring(type2))
            return !dashIgnoringEquals(e1, e2, indexedType(type2));
        return !defaultEquals(e1, indexedType(type1), e2, indexedType(type2));
    }

    static bool dashIgnoringEquals(string e1, string e2, bool indexed2) pure nothrow @nogc
    {
        size_t i1, i2;
        while (i1 < e1.length)
        {
            if (i2 >= e2.length)
                return allDashes(e1[i1 .. $]);
            const ch1 = e1[i1], ch2 = e2[i2];
            if (ch1 == '-')
                i1++;
            else if (ch2 == '-')
                i2++;
            else if (ch1 != ch2)
                return false;
            else
            {
                i1++;
                i2++;
            }
        }
        if (i2 < e2.length)
        {
            if (indexed2)
                return false;
            return allDashes(e2[i2 .. $]);
        }
        return true;
    }

    static bool defaultEquals(string e1, bool indexed1, string e2, bool indexed2) pure nothrow @nogc
    {
        size_t i1, i2;
        while (i1 < e1.length)
        {
            if (i2 >= e2.length)
                return !indexed1 && noAlphaNumeric(e1[i1 .. $]);
            const ch1 = indexed1 ? e1[i1] : lower(e1[i1]);
            const ch2 = indexed2 ? e2[i2] : lower(e2[i2]);
            if (!indexed1 && !alphaNumeric(ch1))
                i1++;
            else if (!indexed2 && !alphaNumeric(ch2))
                i2++;
            else if (ch1 != ch2)
                return false;
            else
            {
                i1++;
                i2++;
            }
        }
        if (i2 < e2.length)
            return !indexed2 && noAlphaNumeric(e2[i2 .. $]);
        return true;
    }

    static bool allDashes(string rest) pure nothrow @nogc
    {
        foreach (char ch; rest)
        {
            if (ch != '-')
                return false;
        }
        return true;
    }

    static bool noAlphaNumeric(string rest) pure nothrow @nogc
    {
        foreach (char ch; rest)
        {
            if (alphaNumeric(lower(ch)))
                return false;
        }
        return true;
    }

    alias Keep = bool function(char, size_t) pure nothrow @nogc @safe;

    static string convert(string element, bool lowercase, Keep keep) pure
    {
        char[] result;
        result.reserve(element.length);
        foreach (i, char ch; element)
        {
            const c = lowercase ? lower(ch) : ch;
            if (keep(c, i))
                result ~= c;
        }
        return result.idup;
    }

    static void notNull(const ConfigurationPropertyName name) pure
    {
        if (name is null)
            throw new IllegalArgumentException("'name' must not be null");
    }

    static bool indexedType(ElementType type) pure nothrow @nogc
    {
        return type == ElementType.INDEXED || type == ElementType.NUMERICALLY_INDEXED;
    }

    static bool fastEquality(ElementType type) pure nothrow @nogc
    {
        return type == ElementType.UNIFORM || type == ElementType.NUMERICALLY_INDEXED;
    }

    static bool dashIgnoring(ElementType type) pure nothrow @nogc
    {
        return fastEquality(type) || type == ElementType.DASHED;
    }
}

/// Thrown when a configuration property name is not valid.
class InvalidConfigurationPropertyNameException : RuntimeException
{
    private string name;
    private string invalidCharacters;

    /// The rejected name and the characters that made it invalid.
    this(string name, string invalidCharacters) pure
    {
        import std.algorithm.iteration : map;
        import std.array : join;
        import std.conv : to;

        super("Configuration property name '" ~ name ~ "' is not valid:\n    Invalid characters: "
                ~ invalidCharacters.map!(c => "'" ~ c.to!string ~ "'")
                    .join(", ")
                ~ "\n    Bean: \n    Reason: Canonical names should be kebab-case ('-' separated), lowercase "
                ~ "alpha-numeric characters and must start with a letter");
        this.name = name;
        this.invalidCharacters = invalidCharacters;
    }

    /// The rejected name.
    string getName() const pure nothrow @nogc
    {
        return name;
    }

    /// The characters that are not valid in it.
    string getInvalidCharacters() const pure nothrow @nogc
    {
        return invalidCharacters;
    }
}

/// A single configuration property: its name, value and origin.
final class ConfigurationProperty
{
    private ConfigurationPropertyName name;
    private string value;
    private ConfigurationPropertySource source;
    private string origin;

    /// The property `name` with `value` from `source`, described by `origin`.
    this(ConfigurationPropertySource source, ConfigurationPropertyName name, string value, string origin = null) pure
    {
        this.source = source;
        this.name = name;
        this.value = value;
        this.origin = origin;
    }

    /// The source that supplied the property.
    ConfigurationPropertySource getSource() pure nothrow @nogc
    {
        return source;
    }

    /// The property's name.
    ConfigurationPropertyName getName() pure nothrow @nogc
    {
        return name;
    }

    /// The property's value as text.
    string getValue() const pure nothrow @nogc
    {
        return value;
    }

    /// Where the value came from (`"class path resource [application.yaml] - 3:9"`), or `null`.
    string getOrigin() const pure nothrow @nogc
    {
        return origin;
    }

    override string toString() const pure
    {
        return "[name=" ~ name.toString() ~ ", value=" ~ value ~ (origin.length ? ", origin=" ~ origin : "") ~ "]";
    }
}

/// Whether a source contains descendants of a name.
enum ConfigurationPropertyState
{
    /// It contains at least one descendant.
    PRESENT,
    /// It contains none.
    ABSENT,
    /// It cannot tell.
    UNKNOWN
}

/// A source of configuration properties, addressed by canonical `ConfigurationPropertyName`.
interface ConfigurationPropertySource
{
    /// The property with `name`, or `null`.
    ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name);

    /// Whether the source holds descendants of `name`.
    ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName name);

    /// The names this source holds, when it can list them; `null` otherwise.
    ConfigurationPropertyName[] iterator();

    /// The underlying source's name, for messages.
    string getUnderlyingSourceName();
}

/// A source that adapts the keys of an ordered map of strings (a `.properties` file, a YAML document, command
/// line arguments) to canonical names, as Spring Boot's `SpringIterableConfigurationPropertySource` over a
/// `MapPropertySource` with the `DefaultPropertyMapper`.
class MapConfigurationPropertySource : ConfigurationPropertySource
{
    private string sourceName;
    private string[] keys;
    private string[string] values;
    private string[string] origins;
    private ConfigurationPropertyName[] names;
    private ConfigurationPropertyName function(string) pure @safe mapper;

    /// An empty source called `sourceName`, mapping keys with `mapper` (the `DefaultPropertyMapper` by default).
    this(string sourceName = "map", ConfigurationPropertyName function(string) pure @safe mapper = null) pure
    {
        this.sourceName = sourceName;
        this.mapper = mapper is null ? &DefaultPropertyMapper.map : mapper;
    }

    /// A source of `entries` in insertion order (pairs of key and value).
    this(string sourceName, const string[2][] entries) pure
    {
        this(sourceName);
        foreach (entry; entries)
            put(entry[0], entry[1]);
    }

    /// Add or replace the property `key`, keeping first-insertion order.
    final void put(string key, string value, string origin = null) pure
    {
        if ((key in values) is null)
        {
            keys ~= key;
            names ~= mapper(key);
        }
        values[key] = value;
        if (origin.length)
            origins[key] = origin;
    }

    /// Add every entry of `map`, sorted by key so iteration is deterministic.
    final void putAll(const string[string] map) pure
    {
        import std.algorithm.sorting : sort;
        import std.array : array;

        foreach (key; map.keys.array.sort)
            put(key, map[key]);
    }

    /// The raw keys, in insertion order.
    const(string)[] getPropertyNames() const pure nothrow @nogc
    {
        return keys;
    }

    /// The raw value of `key`, or `null`.
    string getProperty(string key) const pure nothrow
    {
        if (auto value = key in values)
            return *value;
        return null;
    }

    ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name)
    {
        if (name is null)
            return null;
        foreach (index, candidate; names)
        {
            if (candidate !is null && candidate.equals(name))
            {
                const key = keys[index];
                auto origin = key in origins;
                return new ConfigurationProperty(this, name, values[key], origin ? *origin : sourceName ~ " - " ~ key);
            }
        }
        return null;
    }

    ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName name)
    {
        foreach (candidate; names)
        {
            if (candidate !is null && (name.isEmpty() ? !candidate.isEmpty() : name.isAncestorOf(candidate)))
                return ConfigurationPropertyState.PRESENT;
        }
        return ConfigurationPropertyState.ABSENT;
    }

    ConfigurationPropertyName[] iterator()
    {
        ConfigurationPropertyName[] result;
        foreach (name; names)
        {
            if (name !is null)
                result ~= name;
        }
        return result;
    }

    string getUnderlyingSourceName()
    {
        return sourceName;
    }
}

/// Maps `.properties`/YAML keys to names: the key is split on `.`, and an element that is not canonical (camel
/// case, underscores) is kept as a non-uniform element that compares relaxed.
struct DefaultPropertyMapper
{
    /// The name of `key`, or `null` when nothing in it is usable.
    static ConfigurationPropertyName map(string key) pure
    {
        auto valid = ConfigurationPropertyName.ofIfValid(key);
        if (valid !is null)
            return valid;
        auto adapted = ConfigurationPropertyName.adapt(key, '.');
        return adapted.isEmpty() ? null : adapted;
    }
}

/// Maps environment variable names to names: `FLINT_DATASOURCE_URL` → `flint.datasource.url`, and a numeric
/// element becomes an index (`MY_LIST_0_NAME` → `my.list[0].name`).
struct SystemEnvironmentPropertyMapper
{
    /// The name of the environment variable `key`, or `null` when it holds no usable element.
    static ConfigurationPropertyName map(string key) pure
    {
        import std.uni : toLower;

        if (key.length == 0)
            return null;
        string canonical;
        foreach (part; splitUnderscores(key))
        {
            if (part.length == 0)
                continue;
            bool digits = true;
            foreach (char ch; part)
                digits = digits && ch >= '0' && ch <= '9';
            if (digits)
                canonical ~= "[" ~ part ~ "]";
            else
                canonical ~= (canonical.length ? "." : "") ~ part.toLower;
        }
        // A key of underscores only (the shell's `_`) maps to the empty name, as Boot's does.
        return ConfigurationPropertyName.adapt(canonical is null ? "" : canonical, '.');
    }

    /// Boot's `asSystemEnvironmentLegacyName`: `name` with each dash as an element separator (`foo.the-bar` →
    /// `foo.the.bar`), or `null` when `name` has no dashed element or the result is not a valid name.
    static ConfigurationPropertyName legacyName(ConfigurationPropertyName name) pure
    {
        import std.array : replace;
        import std.string : indexOf;

        if (name is null)
            return null;
        bool dashed;
        string text;
        foreach (i; 0 .. name.getNumberOfElements())
        {
            const element = name.getElement(i, ConfigurationPropertyName.Form.DASHED);
            if (name.isIndexed(i))
            {
                text ~= "[" ~ element ~ "]";
                continue;
            }
            dashed = dashed || element.indexOf('-') >= 0;
            text ~= (text.length ? "." : "") ~ element.replace("-", ".");
        }
        return dashed ? ConfigurationPropertyName.ofIfValid(text) : null;
    }

    private static string[] splitUnderscores(string key) pure
    {
        import std.array : split;

        return key.split('_');
    }
}

/// The process environment as a configuration property source.
final class SystemEnvironmentPropertySource : MapConfigurationPropertySource
{
    /// The variables of `environment` (sorted by name).
    this(const string[string] environment, string sourceName = "systemEnvironment") pure
    {
        super(sourceName, &SystemEnvironmentPropertyMapper.map);
        putAll(environment);
    }

    // Boot's SystemEnvironmentPropertyMapper also maps a name to its legacy variable, dashes as underscores
    // (`foo.the-bar` → `FOO_THE_BAR`), and its ancestor check accepts that form.
    override ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name)
    {
        if (auto property = super.getConfigurationProperty(name))
            return property;
        auto legacy = SystemEnvironmentPropertyMapper.legacyName(name);
        return legacy is null ? null : super.getConfigurationProperty(legacy);
    }

    override ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName name)
    {
        const state = super.containsDescendantOf(name);
        if (state == ConfigurationPropertyState.PRESENT)
            return state;
        auto legacy = SystemEnvironmentPropertyMapper.legacyName(name);
        return legacy is null ? state : super.containsDescendantOf(legacy);
    }
}

/// Lookup across an ordered list of sources, highest precedence first, with Flint's one alias: a name under
/// `flint` is also found under `spring` (ADR-030 section 1), and the `flint` spelling wins inside one source.
struct ConfigurationPropertySources
{
    /// The `spring.*` alias of a `flint.*` name, or `null`.
    static ConfigurationPropertyName aliasOf(ConfigurationPropertyName name) pure
    {
        if (name is null || name.isEmpty() || name.getElement(0, ConfigurationPropertyName.Form.UNIFORM) != "flint")
            return null;
        return ConfigurationPropertyName.of("spring").append(name.subName(1));
    }

    /// A `spring.*` name in its canonical `flint.*` form; any other name unchanged.
    static ConfigurationPropertyName canonical(ConfigurationPropertyName name) pure
    {
        if (name is null || name.isEmpty() || name.getElement(0, ConfigurationPropertyName.Form.UNIFORM) != "spring")
            return name;
        return ConfigurationPropertyName.of("flint").append(name.subName(1));
    }

    /// The first property for `name` (or its alias) in `sources`, or `null`.
    static ConfigurationProperty find(ConfigurationPropertySource[] sources, ConfigurationPropertyName name)
    {
        auto alias_ = aliasOf(name);
        foreach (source; sources)
        {
            if (auto property = source.getConfigurationProperty(name))
                return property;
            if (alias_ !is null)
            {
                if (auto property = source.getConfigurationProperty(alias_))
                    return property;
            }
        }
        return null;
    }

    /// Whether any source holds a descendant of `name` (or of its alias).
    static bool containsDescendantOf(ConfigurationPropertySource[] sources, ConfigurationPropertyName name)
    {
        auto alias_ = aliasOf(name);
        foreach (source; sources)
        {
            if (source.containsDescendantOf(name) == ConfigurationPropertyState.PRESENT)
                return true;
            if (alias_ !is null && source.containsDescendantOf(alias_) == ConfigurationPropertyState.PRESENT)
                return true;
        }
        return false;
    }

    /// Every name the sources list, in canonical `flint.*` form, without duplicates, in precedence order.
    static ConfigurationPropertyName[] names(ConfigurationPropertySource[] sources)
    {
        ConfigurationPropertyName[] result;
        foreach (source; sources)
        {
            foreach (name; source.iterator())
            {
                auto canonicalName = canonical(name);
                bool seen;
                foreach (existing; result)
                    seen = seen || existing.equals(canonicalName);
                if (!seen)
                    result ~= canonicalName;
            }
        }
        return result;
    }
}

private:

char lower(char ch) pure nothrow @nogc
{
    return ch >= 'A' && ch <= 'Z' ? cast(char)(ch + ('a' - 'A')) : ch;
}

bool alpha(char ch) pure nothrow @nogc
{
    return ch >= 'a' && ch <= 'z';
}

bool numeric(char ch) pure nothrow @nogc
{
    return ch >= '0' && ch <= '9';
}

bool alphaNumeric(char ch) pure nothrow @nogc
{
    return alpha(ch) || numeric(ch);
}

bool validChar(char ch, size_t index) pure nothrow @nogc
{
    return alpha(ch) || numeric(ch) || (index != 0 && ch == '-');
}
