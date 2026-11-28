/*
 * Copyright (c) 2000, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/EventListenerProxy.java
// Modified by the Flint authors.

module flint.java.util.eventlistenerproxy;

import flint.java.util.eventlistener : EventListener;

@safe:

/++
An abstract wrapper for an `EventListener` that associates additional parameters with the listener. Subclasses
provide the storage and accessors for those parameters, as Java's class does.

Java bounds the parameter `T extends EventListener`; D keeps it as a template constraint. The parameter also
defaults to `EventListener` so the bound's upper type can be named without importing the marker leaf twice.
+/
abstract class EventListenerProxy(T = EventListener) : EventListener if (is(T : EventListener))
{
    private T listener;

    /// Creates a proxy for `listener`. A null listener is kept, as Java keeps it.
    this(T listener)
    {
        this.listener = listener;
    }

    /// The listener associated with the proxy.
    T getListener() nothrow @nogc
    {
        return listener;
    }
}
