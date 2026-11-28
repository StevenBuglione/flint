/*
 * Copyright (c) 1997, 2019, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/jar/JarEntry.java
// Modified by the Flint authors. Java's checked `IOException` on `getAttributes` is dropped (D-8)
// and the `Certificate`/`CodeSigner` accessors are deferred with `java.security.cert` (phase 3).

module flint.java.util.jar.jarentry;

import flint.java.util.jar : Attributes;
import flint.java.util.zip.zipentry : ZipEntry;

@safe:

/// This class is used to represent a JAR file entry.
class JarEntry : ZipEntry
{
    package(flint.java.util.jar) Attributes attr;

    /// Creates a new `JarEntry` for the specified JAR file entry name.
    this(string name)
    {
        super(name);
    }

    /// Creates a new `JarEntry` with fields taken from the specified `ZipEntry`.
    this(ZipEntry ze)
    {
        super(ze);
    }

    /// Creates a new `JarEntry` with fields taken from the specified `JarEntry`.
    this(JarEntry je)
    {
        this(cast(ZipEntry) je);
        this.attr = je.attr;
    }

    /// Returns the `Manifest` `Attributes` for this entry, or `null` if none.
    Attributes getAttributes()
    {
        return attr;
    }

    /// Returns the real name of this `JarEntry`.
    ///
    /// A multi-release `JarFile` reports the versioned entry's path here; this port has no
    /// `JarFile` yet, so it is the base name `getName` returns.
    string getRealName()
    {
        return super.getName();
    }
}
