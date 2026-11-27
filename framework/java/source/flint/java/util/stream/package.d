/++
`java.util.stream` (rulebook R10): a lazy, sequential `Stream!T` with Java's method names, and `Collectors`.

Elements are pulled one at a time through a delegate, so intermediate operations run lazily and short-circuiting
terminals (`findFirst`, `anyMatch`, `limit`) evaluate only what they need, in Java's order. Parallel streams are not
offered: `parallel()` returns the same sequential stream.
+/
module flint.java.util.stream;

import flint.java.lang : IllegalStateException, valueOf;
public import flint.java.util.stream.collector : Collector;
import flint.java.util.function_ : BiConsumer, Supplier;
import flint.java.util : ArrayList, Collection, Comparator, HashMap, Iterator, LinkedHashMap,
    LinkedHashSet, List, Map, NoSuchElementException, Objects, Optional, Set, compareNatural, stableSort;

@safe:

/// Java's `Stream`: a lazy sequence of elements with aggregate operations.
final class Stream(T)
{
    private bool delegate(out T) @safe pull;
    private bool consumed;
    private bool derived; // an intermediate stage, not a source: Java checks forEach's action before taking it

    private this(bool delegate(out T) @safe pull) pure nothrow @nogc
    {
        this.pull = pull;
    }

    private this(bool derived, bool delegate(out T) @safe pull) pure nothrow @nogc
    {
        this.pull = pull;
        this.derived = derived;
    }

    /// A stream of a copy of `items`.
    static Stream!T ofArray(T[] items)
    {
        size_t position;
        return new Stream!T((out T next) {
            if (position >= items.length)
                return false;
            next = items[position++];
            return true;
        });
    }

    /// A stream of `items`.
    static Stream!T of(T[] items...)
    {
        return ofArray(items.dup);
    }

    /// The empty stream.
    static Stream!T empty()
    {
        return new Stream!T((out T next) => false);
    }

    /// `a`'s elements, then `b`'s.
    static Stream!T concat(Stream!T a, Stream!T b)
    {
        if (a is null || b is null)
            throwNullPointerException();
        auto first = a.take(), second = b.take();
        bool onSecond;
        return new Stream!T((out T next) {
            if (!onSecond)
            {
                if (first(next))
                    return true;
                onSecond = true;
            }
            return second(next);
        });
    }

    /// `seed`, `next(seed)`, `next(next(seed))`, ...: an infinite stream; bound it with `limit`.
    static Stream!T iterate(T seed, T delegate(T) @safe next)
    {
        if (next is null)
            throwNullPointerException();
        bool started;
        T current = seed;
        return new Stream!T((out T element) {
            if (started)
                current = next(current);
            started = true;
            element = current;
            return true;
        });
    }

    private bool delegate(out T) @safe take()
    {
        if (consumed)
            throw new IllegalStateException("stream has already been operated upon or closed");
        consumed = true;
        return pull;
    }

    /// The elements matching `predicate`.
    Stream!T filter(bool delegate(T) @safe predicate)
    {
        if (predicate is null)
            throwNullPointerException();
        auto source = take();
        return new Stream!T(true, (out T next) {
            while (source(next))
                if (predicate(next))
                    return true;
            return false;
        });
    }

    /// Each element transformed by `mapper`.
    Stream!R map(R)(R delegate(T) @safe mapper)
    {
        if (mapper is null)
            throwNullPointerException();
        auto source = take();
        return new Stream!R(true, (out R next) {
            T element;
            if (!source(element))
                return false;
            next = mapper(element);
            return true;
        });
    }

    /// The elements of the stream `mapper` returns for each element, in order.
    Stream!R flatMap(R)(Stream!R delegate(T) @safe mapper)
    {
        if (mapper is null)
            throwNullPointerException();
        auto source = take();
        bool delegate(out R) @safe inner;
        return new Stream!R(true, (out R next) {
            for (;;)
            {
                if (inner !is null && inner(next))
                    return true;
                T element;
                if (!source(element))
                    return false;
                auto mapped = mapper(element);
                inner = mapped is null ? null : mapped.take();
            }
        });
    }

    /// Java's `mapToInt`: each element as an `int`.
    Stream!int mapToInt(int delegate(T) @safe mapper)
    {
        return map!int(mapper);
    }

    /// Java's `mapToLong`: each element as a `long`.
    Stream!long mapToLong(long delegate(T) @safe mapper)
    {
        return map!long(mapper);
    }

    /// The elements without duplicates, keeping the first occurrence.
    Stream!T distinct()
    {
        auto source = take();
        static if (!__traits(compiles, { bool[T] probe; probe[T.init] = true; }))
        {
            // A mutable array cannot key an associative array (Java's List<Object[]>): compare by value.
            T[] seen;
            return new Stream!T(true, (out T next) {
                while (source(next))
                {
                    bool duplicate;
                    foreach (previous; seen)
                        if (previous == next)
                        {
                            duplicate = true;
                            break;
                        }
                    if (duplicate)
                        continue;
                    seen ~= next;
                    return true;
                }
                return false;
            });
        }
        else
        {
            bool[T] seen;
            return new Stream!T(true, (out T next) {
                while (source(next))
                {
                    if (next in seen)
                        continue;
                    seen[next] = true;
                    return true;
                }
                return false;
            });
        }
    }

    /// The elements in natural order (stable), sorted on the first pull. After a failure, a retried pull keeps the
    /// elements already pulled, as Java's sorting sink does: it pulls on after an upstream failure and sorts again
    /// after a comparison failure.
    Stream!T sorted()
    {
        auto source = take();
        T[] items;
        size_t position;
        bool ready;
        return new Stream!T(true, (out T next) {
            if (!ready)
            {
                pullAll(source, items);
                stableSort(items, (T a, T b) => compareNatural(a, b));
                ready = true;
            }
            if (position >= items.length)
                return false;
            next = items[position++];
            return true;
        });
    }

    /// The elements ordered by `comparator` (stable), sorted on the first pull and retried as `sorted()` is. As in
    /// Java, the upstream is taken before a null `comparator` throws `NullPointerException`.
    Stream!T sorted(Comparator!T comparator)
    {
        auto source = take();
        if (comparator is null)
            throwNullPointerException();
        T[] items;
        size_t position;
        bool ready;
        return new Stream!T(true, (out T next) {
            if (!ready)
            {
                pullAll(source, items);
                stableSort(items, &comparator.compare);
                ready = true;
            }
            if (position >= items.length)
                return false;
            next = items[position++];
            return true;
        });
    }

    /// The elements ordered by `compare` (stable). Unlike the `Comparator` overload, this Flint convenience sorts when
    /// called, so `compare` can be a borrowed `scope` delegate.
    Stream!T sorted(int delegate(T, T) @safe compare)
    {
        auto items = toArray();
        stableSort(items, compare);
        return ofArray(items);
    }

    /// Each element, after calling `action` on it as it passes.
    Stream!T peek(void delegate(T) @safe action)
    {
        if (action is null)
            throwNullPointerException();
        auto source = take();
        return new Stream!T(true, (out T next) {
            if (!source(next))
                return false;
            action(next);
            return true;
        });
    }

    /// At most the first `maxSize` elements.
    Stream!T limit(long maxSize)
    {
        if (maxSize < 0)
            throw new IllegalArgumentException(valueOf(maxSize));
        auto source = take();
        long taken;
        return new Stream!T(true, (out T next) {
            if (taken >= maxSize || !source(next))
                return false;
            taken++;
            return true;
        });
    }

    /// The elements after the first `n`.
    Stream!T skip(long n)
    {
        if (n < 0)
            throw new IllegalArgumentException(valueOf(n));
        auto source = take();
        long skipped;
        return new Stream!T(true, (out T next) {
            while (skipped < n)
            {
                T ignored;
                if (!source(ignored))
                    return false;
                skipped++;
            }
            return source(next);
        });
    }

    /// The same stream: Flint streams are sequential.
    Stream!T parallel() pure nothrow @nogc
    {
        return this;
    }

    /// The same stream.
    Stream!T sequential() pure nothrow @nogc
    {
        return this;
    }

    /// Call `action` on each element. A null `action` throws `NullPointerException`: a derived stage checks it
    /// first, while a source stream is taken (and spent) before the check, as Java's head pipeline does.
    void forEach(void delegate(T) @safe action)
    {
        if (action is null)
            rejectNullAction();
        auto source = take();
        T next;
        while (source(next))
            action(next);
    }

    pragma(inline, false) private noreturn rejectNullAction()
    {
        if (!derived)
            take();
        throwNullPointerException();
    }

    /// Call `action` on each element, in order.
    void forEachOrdered(void delegate(T) @safe action)
    {
        forEach(action);
    }

    /// The elements as a new D array.
    T[] toArray()
    {
        return drain(take());
    }

    /// Append every remaining element of `source` to `items`, then drop `source`. A throwing `source` stays set, with
    /// the elements pulled so far kept, so a retry pulls on.
    private static void pullAll(ref bool delegate(out T) @safe source, ref T[] items)
    {
        if (source is null)
            return;
        T next;
        while (source(next))
            items ~= next;
        source = null;
    }

    private static T[] drain(scope bool delegate(out T) @safe source)
    {
        T[] result;
        T next;
        while (source(next))
            result ~= next;
        return result;
    }

    /// The elements as an unmodifiable list (Java 16's `Stream.toList`).
    List!T toList()
    {
        return List!T.of(toArray());
    }

    /// Collect the elements with a collector from `Collectors`, or a Java `Collector`. As in Java, the collector
    /// supplies its container before the first element is pulled, accumulates each element as it is read and finishes
    /// after the last. A collector offering only `apply(T[])` receives every element at once.
    auto collect(C)(C collector)
    {
        import flint.java.util.stream.collector : Collector, collectWith;

        static if (is(C : Collector!(T, A, R), A, R))
            return collectWith!(T, A, R)(collector, &take);
        else static if (is(typeof(collector.supply!T())))
        {
            auto source = take();
            auto state = collector.supply!T();
            T next;
            while (source(next))
                collector.accumulate(state, next);
            return collector.finish(state);
        }
        else
            return collector.apply(toArray());
    }

    /// Java's three-argument `collect`: `supplier` makes the container before the first element is pulled,
    /// `accumulator` adds each element as it is read, and the container is the result. A sequential stream never
    /// calls `combiner`, but as in Java a null one throws `NullPointerException` before the source is taken.
    R collect(R)(R delegate() @safe supplier, void delegate(R, T) @safe accumulator, void delegate(R, R) @safe combiner)
    {
        if (supplier is null || accumulator is null || combiner is null)
            throwNullPointerException();
        auto source = take();
        R container = supplier();
        T next;
        while (source(next))
            accumulator(container, next);
        return container;
    }

    /// The same with Java's functional interfaces (R9).
    R collect(R)(Supplier!R supplier, BiConsumer!(R, T) accumulator, BiConsumer!(R, R) combiner)
    {
        if (supplier is null || accumulator is null || combiner is null)
            throwNullPointerException();
        return collect!R(supplier.asDelegate(), accumulator.asDelegate(), combiner.asDelegate());
    }

    /// How many elements.
    long count()
    {
        auto source = take();
        long n;
        T next;
        while (source(next))
            n++;
        return n;
    }

    /// The first element, or empty. Throws `NullPointerException` when that element is null.
    Optional!T findFirst()
    {
        auto source = take();
        T next;
        return source(next) ? Optional!T.of(next) : Optional!T.empty();
    }

    /// Some element (the first: Flint streams are sequential), or empty.
    Optional!T findAny()
    {
        return findFirst();
    }

    /// Whether any element matches.
    bool anyMatch(bool delegate(T) @safe predicate)
    {
        if (predicate is null)
            throwNullPointerException();
        auto source = take();
        T next;
        while (source(next))
            if (predicate(next))
                return true;
        return false;
    }

    /// Whether every element matches (true for an empty stream).
    bool allMatch(bool delegate(T) @safe predicate)
    {
        if (predicate is null)
            throwNullPointerException();
        auto source = take();
        T next;
        while (source(next))
            if (!predicate(next))
                return false;
        return true;
    }

    /// Whether no element matches.
    bool noneMatch(bool delegate(T) @safe predicate)
    {
        return !anyMatch(predicate);
    }

    /// The least element under `comparator`, or empty.
    Optional!T min(Comparator!T comparator)
    {
        if (comparator is null)
            throwNullPointerException();
        return reduce((T a, T b) => comparator.compare(a, b) <= 0 ? a : b);
    }

    /// The greatest element under `comparator`, or empty.
    Optional!T max(Comparator!T comparator)
    {
        if (comparator is null)
            throwNullPointerException();
        return reduce((T a, T b) => comparator.compare(a, b) >= 0 ? a : b);
    }

    /// Fold the elements with `accumulator`, starting from `identity`.
    T reduce(T identity, T delegate(T, T) @safe accumulator)
    {
        if (accumulator is null)
            throwNullPointerException();
        auto source = take();
        T result = identity, next;
        while (source(next))
            result = accumulator(result, next);
        return result;
    }

    /// Fold the elements with `accumulator`; empty for an empty stream. Throws `NullPointerException` for a null result.
    Optional!T reduce(T delegate(T, T) @safe accumulator)
    {
        if (accumulator is null)
            throwNullPointerException();
        auto source = take();
        T result, next;
        if (!source(result))
            return Optional!T.empty();
        while (source(next))
            result = accumulator(result, next);
        return Optional!T.of(result);
    }

    static if (__traits(isArithmetic, T))
    {
        /// The sum of the elements (Java's `IntStream.sum`).
        T sum()
        {
            return reduce(cast(T) 0, (T a, T b) => cast(T)(a + b));
        }
    }

    /// An iterator over the remaining elements.
    Iterator!T iterator()
    {
        return new StreamIterator!T(take());
    }
}

private final class StreamIterator(T) : Iterator!T
{
    private bool delegate(out T) @safe source;
    private bool buffered, finished;
    private T buffer;

    this(bool delegate(out T) @safe source) pure nothrow @nogc
    {
        this.source = source;
    }

    bool hasNext()
    {
        if (!buffered && !finished)
        {
            buffered = source(buffer);
            finished = !buffered;
        }
        return buffered;
    }

    T next()
    {
        if (!hasNext())
            throw new NoSuchElementException();
        buffered = false;
        return buffer;
    }

    void remove()
    {
        import flint.java.lang : UnsupportedOperationException;

        throw new UnsupportedOperationException("remove");
    }
}

private import flint.java.lang : IllegalArgumentException;

// Java's eager `Objects.requireNonNull` on a stage or terminal callback, before the source is taken (R8). One
// out-of-line cold throw keeps each operation's common path small.
pragma(inline, false) private noreturn throwNullPointerException(string message = null)
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException(message);
}

/// Java's `Collectors`: the common terminal reductions for `Stream.collect`.
struct Collectors
{
    /// The elements as a mutable `ArrayList`.
    static ToList toList() pure nothrow @nogc
    {
        return ToList.init;
    }

    /// The elements as an unmodifiable list.
    static ToUnmodifiableList toUnmodifiableList() pure nothrow @nogc
    {
        return ToUnmodifiableList.init;
    }

    /// The elements as a mutable `HashSet` (insertion order).
    static ToSet toSet() pure nothrow @nogc
    {
        return ToSet.init;
    }

    /// The elements as strings, concatenated with `delimiter`, between `prefix` and `suffix`.
    static Joining joining(string delimiter = "", string prefix = "", string suffix = "") pure nothrow @nogc
    {
        return Joining(delimiter, prefix, suffix);
    }

    /// The number of elements.
    static Counting counting() pure nothrow @nogc
    {
        return Counting.init;
    }

    /// A map from `keyMapper`'s result to `valueMapper`'s. A duplicate key throws `IllegalStateException`, a null
    /// value `NullPointerException`.
    static ToMap!(KF, VF) toMap(KF, VF)(KF keyMapper, VF valueMapper)
    {
        return ToMap!(KF, VF)(keyMapper, valueMapper);
    }

    /// The elements grouped into lists by `classifier`'s result, in first-seen order. A null result throws
    /// `NullPointerException`.
    static GroupingBy!F groupingBy(F)(F classifier)
    {
        return GroupingBy!F(classifier);
    }
}

/++
The collectors share one static protocol, which `Stream.collect` drives: `supply!E()` makes the container,
`accumulate(container, element)` adds each element and `finish(container)` returns the result. `apply(items)` runs the
same three steps over a D array.
+/
private auto collectArray(C, E)(ref C collector, E[] items)
{
    auto state = collector.supply!E();
    foreach (e; items)
        collector.accumulate(state, e);
    return collector.finish(state);
}

/// `Collectors.toList()`.
struct ToList
{
    /// A new, empty `ArrayList`.
    ArrayList!E supply(E)()
    {
        return new ArrayList!E();
    }

    /// Add `element`.
    void accumulate(E)(ArrayList!E list, E element)
    {
        list.add(element);
    }

    /// The list.
    List!E finish(E)(ArrayList!E list)
    {
        return list;
    }

    /// Collect `items`.
    List!E apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// `Collectors.toUnmodifiableList()`.
struct ToUnmodifiableList
{
    /// No elements yet.
    E[] supply(E)()
    {
        return null;
    }

    /// Append `element`.
    void accumulate(E)(ref E[] items, E element)
    {
        items ~= element;
    }

    /// The elements as an unmodifiable list. Throws `NullPointerException` for a null element, as Java's does after
    /// accumulating them all.
    List!E finish(E)(ref E[] items)
    {
        foreach (e; items)
            if (Objects.isNull(e))
                throwNullPointerException();
        return List!E.of(items);
    }

    /// Collect `items`.
    List!E apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// `Collectors.toSet()`.
struct ToSet
{
    /// A new, empty `LinkedHashSet`.
    LinkedHashSet!E supply(E)()
    {
        return new LinkedHashSet!E();
    }

    /// Add `element`.
    void accumulate(E)(LinkedHashSet!E set, E element)
    {
        set.add(element);
    }

    /// The set.
    Set!E finish(E)(LinkedHashSet!E set)
    {
        return set;
    }

    /// Collect `items`.
    Set!E apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// `Collectors.joining(...)`.
struct Joining
{
    /// Between elements.
    string delimiter;
    /// Before the first element.
    string prefix;
    /// After the last element.
    string suffix;

    /// The text so far, and whether an element was added.
    static struct State
    {
        /// The joined text, without the suffix.
        string text;
        /// Whether `text` holds an element.
        bool any;
    }

    /// The prefix alone.
    State supply(E)()
    {
        return State(prefix);
    }

    /// Append `element`, after the delimiter unless it is the first.
    void accumulate(E)(ref State state, E element)
    {
        if (state.any)
            state.text ~= delimiter;
        state.text ~= valueOf(element);
        state.any = true;
    }

    /// The text with the suffix.
    string finish(ref State state)
    {
        return state.text ~ suffix;
    }

    /// Collect `items`.
    string apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// `Collectors.counting()`.
struct Counting
{
    /// Zero.
    long supply(E)()
    {
        return 0;
    }

    /// Count `element`.
    void accumulate(E)(ref long count, E element)
    {
        count++;
    }

    /// The count.
    long finish(ref long count)
    {
        return count;
    }

    /// Collect `items`.
    long apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// `Collectors.toMap(keyMapper, valueMapper)`.
struct ToMap(KF, VF)
{
    /// Computes each key.
    KF keyMapper;
    /// Computes each value.
    VF valueMapper;

    /// A new, empty `HashMap`.
    auto supply(E)()
    {
        alias K = typeof(keyMapper(E.init));
        alias V = typeof(valueMapper(E.init));
        return new HashMap!(K, V)();
    }

    /// Map `element` to its key and value. A null value throws `NullPointerException`, a key already present
    /// `IllegalStateException`.
    void accumulate(K, V, E)(HashMap!(K, V) map, E element)
    {
        auto key = keyMapper(element);
        auto value = valueMapper(element);
        if (Objects.isNull(value))
            throwNullPointerException();
        if (map.containsKey(key))
            throw duplicateKey(valueOf(key), valueOf(map.get(key)), valueOf(value));
        map.put(key, value);
    }

    /// The map.
    Map!(K, V) finish(K, V)(HashMap!(K, V) map)
    {
        return map;
    }

    /// Collect `items`.
    auto apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

private IllegalStateException duplicateKey(string key, string existing, string added)
{
    return new IllegalStateException(
            "Duplicate key " ~ key ~ " (attempted merging values " ~ existing ~ " and " ~ added ~ ")");
}

/// `Collectors.groupingBy(classifier)`.
struct GroupingBy(F)
{
    /// Computes each element's group.
    F classifier;

    /// A new, empty `LinkedHashMap`.
    auto supply(E)()
    {
        alias K = typeof(classifier(E.init));
        return new LinkedHashMap!(K, List!E)();
    }

    /// Add `element` to its group. A null group key throws `NullPointerException`.
    void accumulate(K, E)(LinkedHashMap!(K, List!E) groups, E element)
    {
        auto key = classifier(element);
        if (Objects.isNull(key))
            throwNullPointerException("element cannot be mapped to a null key");
        auto group = groups.get(key);
        if (group is null)
        {
            group = new ArrayList!E();
            groups.put(key, group);
        }
        group.add(element);
    }

    /// The groups.
    Map!(K, List!E) finish(K, E)(LinkedHashMap!(K, List!E) groups)
    {
        return groups;
    }

    /// Collect `items`.
    auto apply(E)(E[] items)
    {
        return collectArray(this, items);
    }
}

/// Collections of `T` as streams, for code that holds a D array: `stream(items).filter(...)`.
Stream!T stream(T)(T[] items)
{
    return Stream!T.ofArray(items);
}

/// The elements of `collection` as a stream.
Stream!T stream(T)(Collection!T collection)
{
    return collection.stream();
}
