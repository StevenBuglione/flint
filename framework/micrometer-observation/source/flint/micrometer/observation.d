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
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/ObservationView.java
// Ported from micrometer-observation 1.18.0: io/micrometer/observation/SimpleEvent.java
// Modified by the Flint authors.
module flint.micrometer.observation;

import core.sync.mutex : Mutex;
import flint.engine.aot.any : Any;
import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.text : decimal;
import flint.java.lang : Iterable, NullPointerException;
import flint.java.util.formatter : formatJava;
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
