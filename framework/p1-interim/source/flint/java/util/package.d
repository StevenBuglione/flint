/++
Interim stand-in for framework-core's `flint.java.util.Optional` (rulebook R5): the methods the web
packages and their tests call. Deleted when `flint:java` lands.
+/
module flint.java.util;

@safe:

/// `java.util.NoSuchElementException`.
class NoSuchElementException : imported!"flint.java.lang".RuntimeException
{
    ///
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, null, file, line);
    }
}

/// `java.util.Optional<T>`.
struct Optional(T)
{
    private T value;
    private bool present;

    /// A present value.
    static Optional of(T value)
    {
        Optional result;
        result.value = value;
        result.present = true;
        return result;
    }

    /// The empty optional.
    static Optional empty() pure nothrow @nogc
    {
        return Optional.init;
    }

    /// Whether a value is present.
    bool isPresent() const pure nothrow @nogc
    {
        return present;
    }

    /// Whether no value is present.
    bool isEmpty() const pure nothrow @nogc
    {
        return !present;
    }

    /// The value. Throws: `NoSuchElementException` when empty.
    inout(T) get() inout
    {
        if (!present)
            throw new NoSuchElementException("No value present");
        return value;
    }

    /// The value, or `other`.
    inout(T) orElse(inout(T) other) inout
    {
        return present ? value : other;
    }
}

/++
`java.util.LinkedHashMap<K, V>`, reduced: insertion-ordered `put`, `get`, `containsKey`, `remove`, `keySet`,
`size`. Reference semantics like Java's (a class). Replaced by framework-core's `Map!(K, V)` (R10).
+/
final class LinkedHashMap(K, V)
{
    private K[] order;
    private V[K] values;

    /// Puts `value`; an existing key keeps its position. Returns the previous value or `V.init`.
    V put(K key, V value)
    {
        if (auto existing = key in values)
        {
            auto previous = *existing;
            *existing = value;
            return previous;
        }
        order ~= key;
        values[key] = value;
        return V.init;
    }

    /// The value for `key`, or `V.init`.
    V get(K key)
    {
        if (auto existing = key in values)
            return *existing;
        return V.init;
    }

    /// Whether `key` is present.
    bool containsKey(K key) const
    {
        return (key in values) !is null;
    }

    /// Removes `key`; returns its value or `V.init`.
    V remove(K key)
    {
        if (auto existing = key in values)
        {
            auto previous = *existing;
            values.remove(key);
            foreach (i, k; order)
                if (k == key)
                {
                    order = order[0 .. i] ~ order[i + 1 .. $];
                    break;
                }
            return previous;
        }
        return V.init;
    }

    /// The keys in insertion order.
    K[] keySet()
    {
        return order.dup;
    }

    /// The number of entries.
    int size() const pure nothrow @nogc
    {
        return cast(int) order.length;
    }

    /// Whether there are none.
    bool isEmpty() const pure nothrow @nogc
    {
        return order.length == 0;
    }

    /// `foreach (key, value; map)` in insertion order.
    int opApply(scope int delegate(K, V) @safe dg)
    {
        foreach (key; order.dup)
            if (auto result = dg(key, values[key]))
                return result;
        return 0;
    }
}

/// `java.util.ArrayList<T>`, reduced: `add`, `get`, `size`, iteration. A class, so `Any` holds it by reference.
final class ArrayList(T)
{
    private T[] items;

    ///
    this(T[] items = null) pure nothrow
    {
        this.items = items;
    }

    /// Appends `item`.
    bool add(T item) pure nothrow
    {
        items ~= item;
        return true;
    }

    /// The element at `index`.
    T get(int index) pure
    {
        return items[index];
    }

    /// The number of elements.
    int size() const pure nothrow @nogc
    {
        return cast(int) items.length;
    }

    /// Whether there are none.
    bool isEmpty() const pure nothrow @nogc
    {
        return items.length == 0;
    }

    /// The elements as a D array.
    T[] toArray() pure nothrow
    {
        return items.dup;
    }

    /// `foreach (item; list)`.
    int opApply(scope int delegate(T) @safe dg)
    {
        foreach (item; items)
            if (auto result = dg(item))
                return result;
        return 0;
    }
}
