/*
 * Copyright (c) 1996, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/zip/Inflater.java
// Modified by the Flint authors.

module flint.java.util.zip.inflater;

import core.exception : onOutOfMemoryError;
import flint.java.lang.runtimeexception : IllegalArgumentException;
import flint.java.util.zip.dataformatexception : DataFormatException;
import flint.java.util.zip.ffi.inflate : InflateStream;
import flint.java.util.zip.ffi.stream : StreamStatus, isolateInput;
import flint.java.util.zip.internal.exceptions : throwNullPointerException;

@safe:

/// Decompresses zlib or raw deflate data.
class Inflater
{
    private Object lock;
    private InflateStream stream;
    private const(byte)[] input;
    private bool reachedEnd;
    private bool dictionaryNeeded;
    private long bytesRead;
    private long bytesWritten;

    this()
    {
        this(false);
    }

    this(bool nowrap)
    {
        lock = new Object();
        requireSuccess(stream.open(nowrap));
    }

    // DMD marks the class allocation for GC finalization only with a class destructor.
    ~this() nothrow @nogc
    {
        stream.close();
    }

    /// Holds the input array until consumed or replaced. Null is empty under R26.
    void setInput(const(byte)[] bytes)
    {
        checkLength(bytes.length);
        synchronized (lock)
            input = bytes;
    }

    /// Write decompressed input to the supplied output array. Null is empty under R26.
    int inflate(scope byte[] output)
    {
        checkLength(output.length);
        synchronized (lock)
        {
            ensureOpen();
            input = isolateInput(input, output);
            const step = stream.step(input, output);
            input = step.read == input.length ? null : input[step.read .. $];
            bytesRead += step.read;
            bytesWritten += step.written;
            final switch (step.status)
            {
            case StreamStatus.finished:
                reachedEnd = true;
                break;
            case StreamStatus.needsDictionary:
                dictionaryNeeded = true;
                break;
            case StreamStatus.dataError:
                throw new DataFormatException(stream.message());
            case StreamStatus.ok:
            case StreamStatus.noProgress:
                break;
            case StreamStatus.streamError:
            case StreamStatus.noMemory:
            case StreamStatus.versionError:
                requireSuccess(step.status);
                break;
            }
            return step.written;
        }
    }

    /// Install the requested preset dictionary. A wrong dictionary leaves it pending.
    void setDictionary(scope const(byte)[] dictionary)
    {
        checkLength(dictionary.length);
        synchronized (lock)
        {
            ensureOpen();
            const status = stream.setDictionary(dictionary);
            if (status == StreamStatus.dataError || status == StreamStatus.streamError)
                throw new IllegalArgumentException(stream.message());
            requireSuccess(status);
            dictionaryNeeded = false;
        }
    }

    int getRemaining()
    {
        synchronized (lock)
            return cast(int) input.length;
    }

    bool needsInput()
    {
        synchronized (lock)
            return input.length == 0;
    }

    bool needsDictionary()
    {
        synchronized (lock)
            return dictionaryNeeded;
    }

    bool finished()
    {
        synchronized (lock)
            return reachedEnd;
    }

    int getAdler()
    {
        synchronized (lock)
        {
            ensureOpen();
            return cast(int) stream.adler;
        }
    }

    long getBytesRead()
    {
        synchronized (lock)
        {
            ensureOpen();
            return bytesRead;
        }
    }

    /// The low 32 bits of the input byte count, as Java's deprecated `getTotalIn`.
    int getTotalIn()
    {
        synchronized (lock)
        {
            ensureOpen();
            return cast(int) bytesRead;
        }
    }

    long getBytesWritten()
    {
        synchronized (lock)
        {
            ensureOpen();
            return bytesWritten;
        }
    }

    /// The low 32 bits of the output byte count, as Java's deprecated `getTotalOut`.
    int getTotalOut()
    {
        synchronized (lock)
        {
            ensureOpen();
            return cast(int) bytesWritten;
        }
    }

    void reset()
    {
        synchronized (lock)
        {
            ensureOpen();
            requireSuccess(stream.reset());
            input = null;
            reachedEnd = false;
            dictionaryNeeded = false;
            bytesRead = bytesWritten = 0;
        }
    }

    void end()
    {
        synchronized (lock)
        {
            // Java's end() releases the stream without reporting zlib's final status.
            stream.close();
            input = null;
        }
    }

    private void ensureOpen()
    {
        if (!stream.isOpen)
            throwNullPointerException("Inflater has been closed");
    }

    private static void checkLength(size_t length)
    {
        if (length > int.max)
            throw new IllegalArgumentException("Array length exceeds the Inflater range");
    }

    private static void requireSuccess(StreamStatus status)
    {
        if (status == StreamStatus.noMemory)
            onOutOfMemoryError();
        if (status != StreamStatus.ok)
            throw new Exception("Inflate operation failed");
    }
}
