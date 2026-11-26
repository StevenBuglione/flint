// Ported from spring-boot v4.2.0: core/spring-boot-test/src/main/java/org/springframework/boot/test/util/TestPropertyValues.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: nullable property values use Nullable!string (R5).
module flint.boot.test.util;

import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException;
import flint.java.util : Map, MapEntry;
import std.typecons : Nullable;

@safe:

/// Test utilities for working with property values.
final class TestPropertyValues
{
    @disable private this();

    /// A single name-value pair.
    static final class Pair
    {
        private string name;
        private Nullable!string value;

        private this(string name, Nullable!string value) pure nothrow @nogc
        {
            this.name = name;
            this.value = value;
        }

        /// Sets this pair in the target map.
        void addTo(Map!(string, Any) properties)
        {
            if (properties is null)
                throw new NullPointerException;
            properties.put(name, value.isNull ? Any.init : Any.of(value.get));
        }

        /// Parses at the first colon or equals sign, trimming both parts as Java's String.trim does.
        static Pair parse(string pair)
        {
            if (pair is null)
                throw new NullPointerException;
            foreach (index, codeUnit; pair)
            {
                if (codeUnit == ':' || codeUnit == '=')
                {
                    if (index != 0)
                        return of(trim(pair[0 .. index]), Nullable!string(trim(pair[index + 1 .. $])));
                    break;
                }
            }
            return of(trim(pair), Nullable!string(""));
        }

        /// Creates a pair from the entry's current key and value.
        static Pair fromMapEntry(MapEntry!(string, Nullable!string) entry)
        {
            if (entry is null)
                throw new NullPointerException;
            return of(entry.getKey(), entry.getValue());
        }

        /// Creates a pair with the supplied name and value.
        static Pair of(string name, Nullable!string value) pure nothrow
        {
            return new Pair(name, value);
        }

        private static string trim(string text) pure nothrow @nogc
        {
            size_t first;
            size_t last = text.length;
            while (first < last && text[first] <= ' ')
                ++first;
            while (first < last && text[last - 1] <= ' ')
                --last;
            return text[first .. last];
        }
    }
}
