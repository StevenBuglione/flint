/*
 * Copyright 2022 VMware, Inc.
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
// Modified by the Flint authors.
module flint.micrometer.observation;

import core.sync.mutex : Mutex;
import flint.java.lang : NullPointerException;
import flint.micrometer.common : KeyValue, KeyValues;
import std.typecons : Nullable;

@safe:

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
