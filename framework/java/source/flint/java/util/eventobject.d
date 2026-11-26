/*
 * Copyright (c) 1996, 2019, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/EventObject.java
// Modified by the Flint authors.

module flint.java.util.eventobject;

import flint.java.lang : IllegalArgumentException;

@safe:

/// Base class for events with an originating object.
class EventObject
{
    /// The object on which the event initially occurred.
    protected Object source;

    /// Constructs an event. Throws IllegalArgumentException when source is null.
    this(Object source)
    {
        if (source is null)
            throw new IllegalArgumentException("null source");

        this.source = source;
    }

    /// The object on which the event initially occurred.
    Object getSource()
    {
        return source;
    }

    /// Returns the runtime type name and the source's string representation.
    override string toString()
    {
        import flint.engine.aot.objects : objectToString;

        return typeid(this).name ~ "[source=" ~ objectToString(source) ~ "]";
    }
}
