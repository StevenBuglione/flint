/*
 * Copyright 2022 VMware, Inc.
 * Copyright 2023 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/Observation.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/GlobalObservationConvention.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationConvention.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/KeyValuesConvention.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationFilter.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationHandler.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationPredicate.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationRegistry.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationView.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/SimpleEvent.java
// Modified by the Flint authors.
module flint.micrometer.observation;

import core.sync.mutex : Mutex;
import flint.engine.aot.any : Any;
import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.objects : statelessInstance;
import flint.engine.aot.text : decimal;
import flint.java.lang : Iterable, NullPointerException;
import flint.java.util.formatter : formatJava;
import flint.java.util.function_ : BiPredicate;
import flint.micrometer.common : KeyValue, KeyValues;
import std.typecons : Nullable;

@safe:

private alias EventKeyValues = Iterable!KeyValue;

/// Read-only view of the observation metadata and cardinality keys.
private interface ObservationContextView
{
    Nullable!string getName();
    Nullable!string getContextualName();
    ObservationView getParentObservation();
    Throwable getError();
    KeyValues getLowCardinalityKeyValues();
    KeyValues getHighCardinalityKeyValues();
    KeyValue getLowCardinalityKeyValue(string key);
    KeyValue getHighCardinalityKeyValue(string key);
    KeyValues getAllKeyValues();
}

/// Read-only access to an observation context.
interface ObservationView
{
    ObservationContextView getContextView();
}

/// Observation API. The context carries the metadata supplied to handlers.
interface Observation : ObservationView
{
    /// Read-only view of the observation metadata and cardinality keys.
    alias ContextView = ObservationContextView;

    /// A timestamped event with optional observation metadata.
    interface Event
    {
        string getName();
        string getContextualName();
        long getWallTime();
        KeyValues getLowCardinalityKeyValues();
        KeyValues getHighCardinalityKeyValues();
        KeyValues getKeyValues();
        /// Virtual formatting implementation for the Java-named overloads.
        Event formatErased(scope Any[] entries);

        /// Format the contextual name with the conversions supported by Flint's Java formatter.
        final Event format(scope Any[] entries)
        {
            return formatErased(entries);
        }

        /// Create an event whose contextual name is its name.
        static Event of(string name)
        {
            return of(name, name);
        }

        /// Create an event with the current epoch time in milliseconds.
        static Event of(string name, string contextualName)
        {
            return of(name, contextualName, currentTimeMillis());
        }

        /// Create an event with an explicit epoch time in milliseconds.
        static Event of(string name, string contextualName, long wallTime)
        {
            return of(name, contextualName, wallTime, KeyValues.empty());
        }

        /// Create an event with an explicit time and high-cardinality keys.
        static Event of(string name, string contextualName, long wallTime, EventKeyValues highCardinality)
        {
            return of(name, contextualName, wallTime, highCardinality, KeyValues.empty());
        }

        /// Create an event with an explicit time and both sets of keys.
        static Event of(string name, string contextualName, long wallTime,
                EventKeyValues highCardinality, EventKeyValues lowCardinality)
        {
            return new SimpleEvent(name, contextualName, wallTime, highCardinality, lowCardinality);
        }

        /// Format the contextual name with R7 stack-boxed Java arguments.
        Event format(Args...)(Args entries)
        {
            Any[Args.length] boxed;
            static foreach (i; 0 .. Args.length)
                boxed[i] = Any.of(entries[i]);
            return formatErased(boxed[]);
        }

        /// Java default methods for implementations that supply an event name (R3).
        mixin template Defaults(alias EventType = Event, alias formatImpl = formatEvent)
        {
            override string getContextualName()
            {
                return getName();
            }

            override long getWallTime()
            {
                return 0;
            }

            override KeyValues getLowCardinalityKeyValues()
            {
                return KeyValues.empty();
            }

            override KeyValues getHighCardinalityKeyValues()
            {
                return KeyValues.empty();
            }

            override KeyValues getKeyValues()
            {
                EventType event = this;
                return event.getLowCardinalityKeyValues().and(event.getHighCardinalityKeyValues());
            }

            override EventType formatErased(scope Any[] entries)
            {
                return formatImpl(this, entries);
            }
        }
    }

    /// Mutable metadata and cardinality keys for a single observation.
    static class Context : ContextView
    {
        private Nullable!string name;
        private Nullable!string contextualName;
        private ObservationView parentObservation;
        private Throwable error;
        private KeyValue[string] lowCardinality;
        private KeyValue[string] highCardinality;
        private Mutex gate;
        // A zero-argument call supplies an empty array, distinct from an explicitly null array.
        private static immutable string[1] emptyKeyStorage;

        /// Construct an empty context.
        this()
        {
            gate = new Mutex;
        }

        override Nullable!string getName() nothrow @nogc
        {
            return name;
        }

        void setName(string name) nothrow @nogc
        {
            this.name = Nullable!string(name);
        }

        override Nullable!string getContextualName() nothrow @nogc
        {
            return contextualName;
        }

        void setContextualName(Nullable!string contextualName) nothrow @nogc
        {
            this.contextualName = contextualName;
        }

        override ObservationView getParentObservation() nothrow @nogc
        {
            return parentObservation;
        }

        void setParentObservation(ObservationView parentObservation) nothrow @nogc
        {
            this.parentObservation = parentObservation;
        }

        override Throwable getError() nothrow @nogc
        {
            return error;
        }

        void setError(Throwable error) nothrow @nogc
        {
            this.error = error;
        }

        /// Add or replace a low-cardinality key.
        Context addLowCardinalityKeyValue(KeyValue value)
        {
            addKeyValue(lowCardinality, value);
            return this;
        }

        /// Add or replace a high-cardinality key.
        Context addHighCardinalityKeyValue(KeyValue value)
        {
            addKeyValue(highCardinality, value);
            return this;
        }

        /// Add or replace low-cardinality keys.
        Context addLowCardinalityKeyValues(KeyValues values)
        {
            if (values is null)
                throw new NullPointerException("keyValues");
            foreach (value; values)
                addLowCardinalityKeyValue(value);
            return this;
        }

        /// Add or replace high-cardinality keys.
        Context addHighCardinalityKeyValues(KeyValues values)
        {
            if (values is null)
                throw new NullPointerException("keyValues");
            foreach (value; values)
                addHighCardinalityKeyValue(value);
            return this;
        }

        /// Remove a low-cardinality key.
        Context removeLowCardinalityKeyValue(string key)
        {
            removeKeyValue(lowCardinality, key);
            return this;
        }

        /// Remove a high-cardinality key.
        Context removeHighCardinalityKeyValue(string key)
        {
            removeKeyValue(highCardinality, key);
            return this;
        }

        /// Call the variadic removal with an empty array.
        final Context removeLowCardinalityKeyValues()
        {
            return removeLowCardinalityKeyValues(emptyKeyStorage[0 .. 0]);
        }

        /// Remove the supplied low-cardinality keys.
        Context removeLowCardinalityKeyValues(scope const(string)[] keys...)
        {
            if (keys is null)
                throw new NullPointerException("keyNames");
            foreach (key; keys)
                removeLowCardinalityKeyValue(key);
            return this;
        }

        /// Call the variadic removal with an empty array.
        final Context removeHighCardinalityKeyValues()
        {
            return removeHighCardinalityKeyValues(emptyKeyStorage[0 .. 0]);
        }

        /// Remove the supplied high-cardinality keys.
        Context removeHighCardinalityKeyValues(scope const(string)[] keys...)
        {
            if (keys is null)
                throw new NullPointerException("keyNames");
            foreach (key; keys)
                removeHighCardinalityKeyValue(key);
            return this;
        }

        override KeyValue getLowCardinalityKeyValue(string key)
        {
            return findKeyValue(lowCardinality, key);
        }

        override KeyValue getHighCardinalityKeyValue(string key)
        {
            return findKeyValue(highCardinality, key);
        }

        override KeyValues getLowCardinalityKeyValues()
        {
            return keyValues(lowCardinality);
        }

        override KeyValues getHighCardinalityKeyValues()
        {
            return keyValues(highCardinality);
        }

        override KeyValues getAllKeyValues()
        {
            return getLowCardinalityKeyValues().and(getHighCardinalityKeyValues());
        }

        private void addKeyValue(ref KeyValue[string] values, KeyValue value)
        {
            if (value is null)
                throw new NullPointerException("keyValue");
            string key = value.getKey();
            checkKey(key);
            synchronized (gate)
                values[key] = value;
        }

        private void removeKeyValue(ref KeyValue[string] values, string key)
        {
            checkKey(key);
            synchronized (gate)
                values.remove(key);
        }

        private KeyValue findKeyValue(ref KeyValue[string] values, string key)
        {
            checkKey(key);
            synchronized (gate)
                return values.get(key, null);
        }

        private KeyValues keyValues(ref KeyValue[string] values)
        {
            KeyValue[] snapshot;
            synchronized (gate)
                snapshot = values.values;
            return KeyValues.of(snapshot);
        }

        private static void checkKey(string key)
        {
            if (key is null)
                throw new NullPointerException("key");
        }
    }
}

// Keep the erased Java formatting body shared across Event implementations.
private Observation.Event formatEvent(Observation.Event event, scope Any[] entries)
{
    string name = event.getName();
    string contextualName = event.getContextualName();
    if (contextualName is null)
        throw new NullPointerException("contextualName");
    string text = formatJava(contextualName, entries);
    return Observation.Event.of(name, text is null ? "" : text, event.getWallTime(),
            event.getHighCardinalityKeyValues(), event.getLowCardinalityKeyValues());
}

private final class SimpleEvent : Observation.Event
{
    private string name;
    private string contextualName;
    private long wallTime;
    private KeyValues highCardinality;
    private KeyValues lowCardinality;

    this(string name, string contextualName, long wallTime, EventKeyValues highCardinality,
            EventKeyValues lowCardinality)
    {
        this.name = name;
        this.contextualName = contextualName;
        this.wallTime = wallTime;
        this.highCardinality = KeyValues.of(highCardinality);
        this.lowCardinality = KeyValues.of(lowCardinality);
    }

    override string getName() nothrow @nogc
    {
        return name;
    }

    override string getContextualName() nothrow @nogc
    {
        return contextualName;
    }

    override long getWallTime() nothrow @nogc
    {
        return wallTime;
    }

    override KeyValues getHighCardinalityKeyValues() nothrow @nogc
    {
        return highCardinality;
    }

    override KeyValues getLowCardinalityKeyValues() nothrow @nogc
    {
        return lowCardinality;
    }

    override string toString() const
    {
        return "event.name='" ~ (name is null ? "null" : name) ~ "', event.contextualName='" ~ (contextualName is null
                ? "null" : contextualName) ~ "', event.wallTime=" ~ decimal(wallTime);
    }

    override KeyValues getKeyValues()
    {
        return lowCardinality.and(highCardinality);
    }

    override Observation.Event formatErased(scope Any[] entries)
    {
        return formatEvent(this, entries);
    }
}

/// Marker for key-value naming conventions.
interface KeyValuesConvention
{
}

// A Java type bound requires inheritance. D's implicit conversion also accepts alias-this wrappers.
private template isObservationContext(T)
{
    static if (is(T == Observation.Context))
        enum isObservationContext = true;
    else static if (is(T Bases == super) && Bases.length > 0)
        enum isObservationContext = isObservationContext!(Bases[0]);
    else
        enum isObservationContext = false;
}

private alias ContextConvention = ObservationConvention!(Observation.Context);

/// Supplies observation names and key values for a context type.
interface ObservationConvention(T) : KeyValuesConvention if (isObservationContext!T)
{
    /// The shared convention that declines every context.
    static @property ContextConvention EMPTY() nothrow @nogc
    {
        return statelessInstance!EmptyObservationConvention();
    }

    /// Check whether this convention applies before passing a context of type T to its getters.
    bool supportsContext(Observation.Context context);

    KeyValues getLowCardinalityKeyValues(T context);
    KeyValues getHighCardinalityKeyValues(T context);
    Nullable!string getName();
    Nullable!string getContextualName(T context);

    /// Java defaults for an implementation that only specifies when it applies (R3).
    mixin template Defaults(alias Context = T)
    {
        override KeyValues getLowCardinalityKeyValues(Context context)
        {
            return KeyValues.empty();
        }

        override KeyValues getHighCardinalityKeyValues(Context context)
        {
            return KeyValues.empty();
        }

        override Nullable!string getName()
        {
            return Nullable!string.init;
        }

        override Nullable!string getContextualName(Context context)
        {
            return Nullable!string.init;
        }
    }
}

/// A convention eligible for registration as a global observation convention.
interface GlobalObservationConvention(T) : ObservationConvention!T if (isObservationContext!T)
{
}

private final class EmptyObservationConvention : ContextConvention
{
    override bool supportsContext(Observation.Context context) nothrow @nogc
    {
        return false;
    }

    mixin ContextConvention.Defaults;
}

/// Rewrites the context before stop handlers receive it.
interface ObservationFilter
{
    /// Return the context to pass to subsequent filters and handlers.
    Observation.Context map(Observation.Context context);
}

/// Decides whether observations with a given name and context should be created.
interface ObservationPredicate : BiPredicate!(string, Observation.Context)
{
}

/// Hooks into an observation's lifecycle for a particular context type.
interface ObservationHandler(T) if (isObservationContext!T)
{
    /// React to the start of an observation.
    void onStart(T context);

    /// React to a reported error.
    void onError(T context);

    /// React to a signaled event.
    void onEvent(Observation.Event event, T context);

    /// React to the opening of an observation scope.
    void onScopeOpened(T context);

    /// React to the closing of an observation scope.
    void onScopeClosed(T context);

    /// React to a reset of the current scope (added in Micrometer 1.10.4).
    deprecated("Use onScopeClosed for cleanup when a scope is closed.") void onScopeReset(T context);

    /// React to the stop of an observation.
    void onStop(T context);

    /// Check whether this handler applies to the supplied context.
    bool supportsContext(Observation.Context context);

    /// Supply Micrometer's no-op default callbacks (R3).
    mixin template Defaults(alias Context = T, alias Event = Observation.Event)
    {
        override void onStart(Context context)
        {
        }

        override void onError(Context context)
        {
        }

        override void onEvent(Event event, Context context)
        {
        }

        override void onScopeOpened(Context context)
        {
        }

        override void onScopeClosed(Context context)
        {
        }

        deprecated("Use onScopeClosed for cleanup when a scope is closed.") override void onScopeReset(Context context)
        {
        }

        override void onStop(Context context)
        {
        }
    }
}

private alias HandlerSupport = bool delegate(Observation.Context) @safe;
private alias PredicateCallback = bool delegate(string, Observation.Context) @safe;
private alias FilterCallback = Observation.Context delegate(Observation.Context) @safe;

/// Configures registries that supply and manage observations.
interface ObservationRegistry
{
    /// The ordered callbacks associated with an observation registry.
    static class ObservationConfig
    {
        private Mutex gate;
        private ObservationPredicate[] predicates;
        private ObservationFilter[] filters;
        private RegisteredObservationHandler firstHandler;
        private RegisteredObservationHandler lastHandler;

        /// Construct an empty registry configuration.
        this()
        {
            gate = new Mutex;
        }

        /// Register a handler with its declared context type.
        ObservationConfig observationHandler(T)(ObservationHandler!T handler)
        {
            return appendHandler(new RegisteredObservationHandler(cast(Object) handler,
                    handler is null ? null : &handler.supportsContext));
        }

        /// Register a support predicate with default no-op handler callbacks (R9).
        ObservationConfig observationHandler(HandlerSupport supportsContext)
        {
            return appendHandler(new RegisteredObservationHandler(null, supportsContext));
        }

        /// Register a literal null with the same semantics as a null handler.
        final ObservationConfig observationHandler(typeof(null))
        {
            return observationHandler(cast(HandlerSupport) null);
        }

        // Allocate the adapter at registration, then publish one ordered entry.
        protected ObservationConfig appendHandler(RegisteredObservationHandler handler)
        {
            synchronized (gate)
            {
                if (lastHandler is null)
                    firstHandler = handler;
                else
                    lastHandler.next = handler;
                lastHandler = handler;
            }
            return this;
        }

        package(flint.micrometer) ObservationHandlerSnapshot getObservationHandlers()
        {
            synchronized (gate)
                return ObservationHandlerSnapshot(firstHandler, lastHandler);
        }

        /// Register a predicate after the predicates already configured.
        ObservationConfig observationPredicate(ObservationPredicate predicate)
        {
            synchronized (gate)
                predicates = predicates ~ predicate;
            return this;
        }

        /// Retain a D delegate as a registry predicate (R9).
        ObservationConfig observationPredicate(PredicateCallback predicate)
        {
            return observationPredicate(predicate is null ? null : new DelegateObservationPredicate(predicate));
        }

        /// Preserve Java's literal-null registration when selecting the predicate overload.
        final ObservationConfig observationPredicate(typeof(null))
        {
            return observationPredicate(cast(ObservationPredicate) null);
        }

        /// Register a filter after the filters already configured.
        ObservationConfig observationFilter(ObservationFilter filter)
        {
            synchronized (gate)
                filters = filters ~ filter;
            return this;
        }

        /// Retain a D delegate as a registry filter (R9).
        ObservationConfig observationFilter(FilterCallback filter)
        {
            return observationFilter(filter is null ? null : new DelegateObservationFilter(filter));
        }

        /// Preserve Java's literal-null registration when selecting the filter overload.
        final ObservationConfig observationFilter(typeof(null))
        {
            return observationFilter(cast(ObservationFilter) null);
        }

        package(flint.micrometer) bool isObservationEnabled(Nullable!string name, Observation.Context context)
        {
            ObservationPredicate[] snapshot;
            synchronized (gate)
                snapshot = predicates;

            string callbackName;
            if (!name.isNull)
            {
                const supplied = name.get();
                callbackName = supplied is null ? "" : supplied;
            }
            foreach (predicate; snapshot)
            {
                if (predicate is null)
                    throw new NullPointerException("observationPredicate");
                if (!predicate.test(callbackName, context))
                    return false;
            }
            return true;
        }

        package(flint.micrometer) ObservationFilterSnapshot getObservationFilters()
        {
            synchronized (gate)
                return ObservationFilterSnapshot(filters);
        }
    }
}

// Readers hold the first and last entries together, and never read the last entry's mutable link.
private struct ObservationHandlerSnapshot
{
    private RegisteredObservationHandler current;
    private RegisteredObservationHandler last;

    @property bool empty() const nothrow @nogc
    {
        return current is null;
    }

    @property RegisteredObservationHandler front() nothrow @nogc
    {
        return current;
    }

    void popFront() nothrow @nogc
    {
        current = current is last ? null : current.next;
    }
}

private final class RegisteredObservationHandler
{
    private RegisteredObservationHandler next;
    private Object handler;
    private HandlerSupport supports;

    this(Object handler, HandlerSupport supports)
    {
        this.handler = handler;
        this.supports = supports;
    }

    Object source() nothrow @nogc
    {
        if (supports is null)
            return null;
        return handler is null ? this : handler;
    }

    bool supportsContext(Observation.Context context)
    {
        if (supports is null)
            throw new NullPointerException("observationHandler");
        return supports(context);
    }
}

// A reader can invoke a retained callback without changing the snapshot's membership.
private struct ObservationFilterSnapshot
{
    private ObservationFilter[] filters;

    @property size_t length() const nothrow @nogc
    {
        return filters.length;
    }

    inout(ObservationFilter) opIndex(size_t index) inout nothrow @nogc
    {
        return filters[index];
    }
}

private final class DelegateObservationPredicate : ObservationPredicate
{
    private PredicateCallback callback;

    this(PredicateCallback callback)
    {
        this.callback = callback;
    }

    override bool test(string name, Observation.Context context)
    {
        return callback(name, context);
    }
}

private final class DelegateObservationFilter : ObservationFilter
{
    private FilterCallback callback;

    this(FilterCallback callback)
    {
        this.callback = callback;
    }

    override Observation.Context map(Observation.Context context)
    {
        return callback(context);
    }
}
