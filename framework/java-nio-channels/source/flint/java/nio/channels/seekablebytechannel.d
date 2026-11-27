/*
 * Copyright (c) 2007, 2022, Oracle and/or its affiliates. All rights reserved.
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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/channels/SeekableByteChannel.java
 * Modified by the Flint authors.
 */
module flint.java.nio.channels.seekablebytechannel;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.channels.bytechannel : ByteChannel;

@safe:

/// A byte channel that maintains a current position and allows the position to be changed.
interface SeekableByteChannel : ByteChannel
{
    /// Reads a sequence of bytes from this channel into `dst` starting at the current position.
    override int read(ByteBuffer dst);

    /// Writes a sequence of bytes to this channel from `src` starting at the current position.
    override int write(ByteBuffer src);

    /// Returns this channel's position.
    long position();

    /// Sets this channel's position.
    SeekableByteChannel position(long newPosition);

    /// Returns the current size of entity to which this channel is connected.
    long size();

    /// Truncates the entity to which this channel is connected to the given `size`.
    SeekableByteChannel truncate(long size);
}
