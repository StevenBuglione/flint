/*
 * Copyright (c) 2000, 2021, Oracle and/or its affiliates. All rights reserved.
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

/*
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/spi/CharsetProvider.java
 * Modified by the Flint authors.
 */
/** `java.nio.charset.spi.CharsetProvider`. */
module flint.java.nio.charset.spi.charsetprovider;

import flint.java.nio.charset : Charset;
import flint.java.util : Iterator;

@safe:

/++
Charset service-provider class (`java.nio.charset.spi.CharsetProvider`).

A concrete subclass implements `charsets()` and `charsetForName(string)`. Java's `SecurityManager`
permission check is omitted because `SecurityManager` is deprecated for removal in Java 21 and excluded
from Flint. `Charset` is a value type here, so `Charset.init` stands for Java's `null` return when a
charset name is not supported by the provider.
+/
abstract class CharsetProvider
{
    /// Initializes a new charset provider.
    protected this()
    {
    }

    /// Creates an iterator that iterates over the charsets supported by this provider.
    abstract Iterator!Charset charsets();

    /++
    Retrieves a charset for `charsetName` (a canonical name or alias), or `Charset.init` if the named
    charset is not supported by this provider.
    +/
    abstract Charset charsetForName(string charsetName);
}
