/*
 * Copyright (c) 1996, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/zip/Deflater.java
// Modified by the Flint authors.

module flint.java.util.zip.deflater;

import core.exception : onOutOfMemoryError;
import flint.java.lang : IllegalArgumentException;
import flint.java.util.zip.ffi.deflate : DeflateParameters, DeflateStream;
import flint.java.util.zip.ffi.stream : StreamStatus, isolateInput;
import flint.java.util.zip.internal.exceptions : throwNullPointerException;

@safe:

/// Compresses zlib or raw deflate data.
class Deflater
{
    enum int NO_COMPRESSION = 0;
    enum int BEST_SPEED = 1;
    enum int BEST_COMPRESSION = 9;
    enum int DEFAULT_COMPRESSION = -1;
    enum int DEFAULT_STRATEGY = 0;
    enum int FILTERED = 1;
    enum int HUFFMAN_ONLY = 2;

    private Object lock;
    private DeflateStream stream;
    private DeflateParameters parameters;
    private const(byte)[] input;
    private bool finishRequested;
    private bool reachedEnd;
    private long bytesRead;
    private long bytesWritten;

    this()
    {
        this(DEFAULT_COMPRESSION, false);
    }

    this(int level)
    {
        this(level, false);
    }

    this(int level, bool nowrap)
    {
        lock = new Object();
        const status = stream.open(level, nowrap);
        if (status == StreamStatus.streamError)
            throw new IllegalArgumentException();
        requireSuccess(status);
        parameters.level = level;
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

    /// Install a preset dictionary without crediting it as stream input.
    void setDictionary(scope const(byte)[] dictionary)
    {
        checkLength(dictionary.length);
        synchronized (lock)
        {
            ensureOpen();
            const status = stream.setDictionary(dictionary);
            if (status == StreamStatus.streamError)
                throw new IllegalArgumentException();
            requireSuccess(status);
        }
    }

    /// Stage the compression level for the next successful parameter update.
    void setLevel(int level)
    {
        if (level < DEFAULT_COMPRESSION || level > BEST_COMPRESSION)
            throw new IllegalArgumentException("invalid compression level");
        synchronized (lock)
        {
            if (parameters.level != level)
            {
                parameters.level = level;
                parameters.pending = true;
            }
        }
    }

    /// Stage the compression strategy for the next successful parameter update.
    void setStrategy(int strategy)
    {
        if (strategy < DEFAULT_STRATEGY || strategy > HUFFMAN_ONLY)
            throw new IllegalArgumentException();
        synchronized (lock)
        {
            if (parameters.strategy != strategy)
            {
                parameters.strategy = strategy;
                parameters.pending = true;
            }
        }
    }

    bool needsInput()
    {
        synchronized (lock)
            return input.length == 0;
    }

    void finish()
    {
        synchronized (lock)
            finishRequested = true;
    }

    bool finished()
    {
        synchronized (lock)
            return reachedEnd;
    }

    /// Write compressed output to the supplied array. Null is empty under R26.
    int deflate(scope byte[] output)
    {
        checkLength(output.length);
        synchronized (lock)
        {
            ensureOpen();
            input = isolateInput(input, output);
            const step = stream.step(input, output, finishRequested, parameters);
            if (step.status == StreamStatus.finished)
                reachedEnd = true;
            else if (step.status != StreamStatus.noProgress)
                requireSuccess(step.status);
            input = step.read == input.length ? null : input[step.read .. $];
            bytesRead += step.read;
            bytesWritten += step.written;
            return step.written;
        }
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

    long getBytesWritten()
    {
        synchronized (lock)
        {
            ensureOpen();
            return bytesWritten;
        }
    }

    void reset()
    {
        synchronized (lock)
        {
            ensureOpen();
            requireSuccess(stream.reset());
            input = null;
            finishRequested = reachedEnd = false;
            bytesRead = bytesWritten = 0;
        }
    }

    void end()
    {
        synchronized (lock)
        {
            const status = stream.close();
            input = null;
            if (status != StreamStatus.dataError)
                requireSuccess(status);
        }
    }

    private void ensureOpen()
    {
        if (!stream.isOpen)
            throwNullPointerException("Deflater has been closed");
    }

    private static void checkLength(size_t length)
    {
        if (length > int.max)
            throw new IllegalArgumentException("Array length exceeds the Deflater range");
    }

    private static void requireSuccess(StreamStatus status)
    {
        if (status == StreamStatus.noMemory)
            onOutOfMemoryError();
        if (status != StreamStatus.ok)
            throw new Exception("Deflate operation failed");
    }
}
