/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.lang.javaobject;

@safe:

/++
Maps Java's `equals`, `hashCode` and `compareTo` onto D's `opEquals`, `toHash` and `opCmp`, so `==`, associative
arrays and sorting use the Java methods. Mix it into a class that declares `bool equals(Object)` and
`int hashCode()` (and optionally `int compareTo(T)`); `toString` keeps its name in both languages.
+/
mixin template JavaObject()
{
    static if (is(typeof(this) == class))
    {
        /// `==` through an `Object` reference calls `equals`.
        override bool opEquals(Object other)
        {
            return this.equals(other);
        }

        /// `==` between two instances calls `equals`, and stays `@safe`.
        bool opEquals(typeof(this) other)
        {
            return this is other || (other !is null && this.equals(other));
        }

        /// Associative arrays call `hashCode`. An exception from `hashCode` hashes to 0.
        override size_t toHash() @safe nothrow
        {
            try
                return cast(size_t) cast(uint) this.hashCode();
            catch (Exception)
                return 0;
        }

        static if (__traits(hasMember, typeof(this), "compareTo"))
        {
            /// `<` calls `compareTo`; another class compares as unordered (0), as Java would throw.
            override int opCmp(Object other)
            {
                auto that = cast(typeof(this)) other;
                return that is null ? 0 : this.compareTo(that);
            }
        }
    }
    else
    {
        /// `==` calls `equals`.
        bool opEquals(const typeof(this) other) const
        {
            return this.equals(other);
        }

        /// Associative arrays call `hashCode`.
        size_t toHash() const @safe nothrow
        {
            try
                return cast(size_t) cast(uint) this.hashCode();
            catch (Exception)
                return 0;
        }
    }
}
