/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/core/io/buffer/
// DataBufferFactory.java, DataBufferLimitException.java, DataBufferMatcher.java, DataBuffers.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.core.io.buffer`.
module flint.core.io.buffer;

import flint.java.lang : IllegalStateException;
import flint.java.util : List;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.core.io.buffer.DataBufferFactory sha256:cbc3630b99bc641de62a8e995b7bb4b2da257b02d6dcad24ccfacb86f87a6e31
/// A factory for `DataBuffers`, allowing for allocation and wrapping of data buffers.
interface DataBufferFactory
{
    /// Indicates whether this factory allocates direct buffers (i.e. non-heap, native memory).
    bool isDirect();

    // port:pending org.springframework.core.io.buffer.DataBufferFactory#allocateBuffer(): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBufferFactory#allocateBuffer(int): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBufferFactory#join(List): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBufferFactory#wrap(ByteBuffer): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBufferFactory#wrap(byte): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.core.io.buffer.DataBufferLimitException sha256:197ee71f8124c3afedaf7df05b5447a7fd7de885d1ced5a53f947958f5cc2e64
/// Exception that indicates the cumulative number of bytes consumed from a stream of `DataBuffer`'s exceeded some
/// pre-configured limit. This can be raised when data buffers are cached and aggregated, for example,
/// `DataBufferUtils.join`. Or it could also be raised when data buffers have been released but a parsed representation
/// is being aggregated, for example, async parsing with Jackson, SSE parsing and aggregating lines per event.
class DataBufferLimitException : IllegalStateException
{
    /// Create an instance with the given message.
    this(string message)
    {
        super(message);
    }

    // port:pending org.springframework.core.io.buffer.DataBufferLimitException#<init>(String,Throwable): type java.lang.Throwable is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.core.io.buffer.DataBufferMatcher sha256:133d266dd495f050970df1a6eb39d37fcebdec9ac15255e8f4590b3968a3bc0d
/// Contract to find delimiter(s) against one or more data buffers that can be passed one at a time to the
/// `match(DataBuffer)` method.
interface DataBufferMatcher
{
    /// Return the delimiter from the last invocation of `match(DataBuffer)`.
    byte[] delimiter();

    /// Reset the state of this matcher.
    void reset();

    // port:pending org.springframework.core.io.buffer.DataBufferMatcher#match(DataBuffer): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBufferMatcher#of(byte): varargs (R7)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.core.io.buffer.DataBuffers sha256:99946ee361445d2f51972bec4696219cc76e9325642935625d06e12f771d67c8
/// Utility methods for working with `DataBuffers` that do not require Reactor or Reactive Streams on the classpath, and
/// can therefore be used in any application. `DataBufferUtils` extends this class and adds the methods that are based
/// on Reactive Streams. This class must not depend on it.
abstract class DataBuffers
{
    // port:pending org.springframework.core.io.buffer.DataBuffers#RELEASE_CONSUMER: a constant whose initializer is not a literal

    // port:pending org.springframework.core.io.buffer.DataBuffers#createMatcher(byte): type NestedMatcher does not resolve to a pinned type

    // port:pending org.springframework.core.io.buffer.DataBuffers#logger: a constant whose initializer is not a literal

    // port:pending org.springframework.core.io.buffer.DataBuffers#matcher(byte): varargs (R7)

    // port:pending org.springframework.core.io.buffer.DataBuffers#release(DataBuffer): type org.springframework.core.io.buffer.DataBuffer is not mapped to a D symbol

    // port:pending org.springframework.core.io.buffer.DataBuffers#releaseConsumer(): generic type Consumer<...>

    // port:pending org.springframework.core.io.buffer.DataBuffers#retain(T): a generic method

    // port:pending org.springframework.core.io.buffer.DataBuffers#touch(T,Object): a generic method

    // port:pending org.springframework.core.io.buffer.DataBuffers.AbstractNestedMatcher: a nested class (R13)

    // port:pending org.springframework.core.io.buffer.DataBuffers.CompositeMatcher: a nested class (R13)

    // port:pending org.springframework.core.io.buffer.DataBuffers.KnuthMorrisPrattMatcher: a nested class (R13)

    // port:pending org.springframework.core.io.buffer.DataBuffers.NestedMatcher: a nested interface (R13)

    // port:pending org.springframework.core.io.buffer.DataBuffers.SingleByteMatcher: a nested class (R13)

    // port:pending org.springframework.core.io.buffer.DataBuffers.TwoByteMatcher: a nested class (R13)
}
// port:end
