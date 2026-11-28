/*
 * Copyright (c) 1994, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/Iterator.java
// Modified by the Flint authors.

/++
Internal: `Iterator` lives in its own leaf so `flint.java.util.enumeration` can name it without importing the
`flint.java.util` aggregate back (D rejects the package cycle; docs/spring/api-mapping.md, "Package cycles").
`flint.java.util` re-exports it, so the canonical import path and `api/framework/mapping.json`'s `d` are
unchanged. Applications import `flint.java.util`, never this module.
+/
module flint.java.util.internal.iterator;

@safe:

/// Java's `Iterator`.
interface Iterator(T)
{
    /// Whether another element follows.
    bool hasNext();
    /// The next element. Throws `NoSuchElementException` at the end.
    T next();
    /// Remove the element last returned. Throws `UnsupportedOperationException` unless supported.
    void remove();
}
