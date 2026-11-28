/*
 * Copyright (c) 2000, 2023, Oracle and/or its affiliates. All rights reserved.
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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/channels/spi/AbstractInterruptibleChannel.java
 * Modified by the Flint authors.
 */
/** `java.nio.channels.spi.AbstractInterruptibleChannel`. */
module flint.java.nio.channels.spi.abstractinterruptiblechannel;

import core.atomic : atomicLoad, cas;
import flint.java.nio.channels.asynchronouscloseexception : AsynchronousCloseException;
import flint.java.nio.channels.channel : Channel;
import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;

@safe:

/++
Base implementation class for interruptible channels (`java.nio.channels.spi.AbstractInterruptibleChannel`).

A concrete channel calls `begin` before, and `end` after, an I/O operation that might block indefinitely, so that
asynchronous closing is reported. `close` marks the channel closed once and then runs `implCloseChannel`.

Java arms `begin`'s interrupt hook on the current `Thread`; Flint's `Thread` façade does not exist yet, so Thread
interruption is deferred (the `ClosedByInterruptException` half of `end`) exactly as in the `java.util.concurrent`
ports. `end` still throws `AsynchronousCloseException` when an incomplete operation observes a closed channel.
+/
abstract class AbstractInterruptibleChannel : Channel, InterruptibleChannel
{
    private shared bool closed_;

    /// Initializes a new instance of this class.
    protected this()
    {
    }

    /++
    Closes this channel.

    If the channel is already closed this returns immediately. Otherwise it marks the channel closed and calls
    `implCloseChannel` to complete the close. An exception from `implCloseChannel` propagates and leaves the channel
    closed.
    +/
    final override void close()
    {
        if (!cas(&closed_, false, true))
            return;
        implCloseChannel();
    }

    /// Closes this channel for real, called by `close` at most once.
    protected abstract void implCloseChannel();

    /// Tells whether or not this channel is open.
    final override bool isOpen()
    {
        return !atomicLoad(closed_);
    }

    /// Marks the beginning of an I/O operation that might block indefinitely. Thread interruption is deferred.
    protected final void begin()
    {
    }

    /++
    Marks the end of an I/O operation that might block indefinitely.

    Throws `AsynchronousCloseException` when `completed` is false and the channel has been closed. Thread
    interruption (Java's `ClosedByInterruptException`) is deferred until the `Thread` façade lands.
    +/
    protected final void end(bool completed)
    {
        if (!completed && !isOpen())
            throw new AsynchronousCloseException;
    }
}
