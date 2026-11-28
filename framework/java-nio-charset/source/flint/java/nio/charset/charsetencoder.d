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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/Charset-X-Coder.java.template
 * (the encoder expansion, CharsetEncoder).
 * Modified by the Flint authors.
 */
/** `java.nio.charset.CharsetEncoder`. */
module flint.java.nio.charset.charsetencoder;

import flint.java.lang : NullPointerException, RuntimeException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset;
import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.codingerroraction : CodingErrorAction;
import flint.java.nio.charset.internal.coders : checkRates, checkReplacementLength, estimateCapacity,
    grownCapacity, stCoding, stEnd, stFlushed, stReset, throwIllegalArgument, throwIllegalState, utf16Length;
import flint.java.nio.charset.internal.decoders : isLegalReplacementFor;

@safe:

/++
An engine that transforms a sequence of 16-bit Unicode characters into a sequence of bytes in a specific charset.

Subclasses implement `encodeLoop`. `Charset.init` stands for a `null` charset; as in Java, constructing an encoder for
it throws `NullPointerException` unless `isLegalReplacement` is overridden.
+/
abstract class CharsetEncoder
{
    private static immutable byte[1] defaultReplacement = ['?'];

    private Charset charset_;
    private float averageBytesPerChar_;
    private float maxBytesPerChar_;
    private byte[] replacement_;
    private CodingErrorAction malformedInputAction_ = CodingErrorAction.REPORT;
    private CodingErrorAction unmappableCharacterAction_ = CodingErrorAction.REPORT;
    private ubyte state = stReset;

    /++
    Initializes an encoder with the given replacement and the REPORT action for both kinds of error.
    Throws: `IllegalArgumentException` when either rate is not positive, the average exceeds the maximum, or the
    replacement is not acceptable to `replaceWith`.
    +/
    protected this(Charset cs, float averageBytesPerChar, float maxBytesPerChar, scope const(byte)[] replacement)
    {
        charset_ = cs;
        checkRates(averageBytesPerChar, maxBytesPerChar, "averageBytesPerChar", "maxBytesPerChar");
        averageBytesPerChar_ = averageBytesPerChar;
        maxBytesPerChar_ = maxBytesPerChar;
        replaceWith(replacement);
    }

    /// Initializes an encoder with the replacement `{ (byte)'?' }`.
    protected this(Charset cs, float averageBytesPerChar, float maxBytesPerChar)
    {
        this(cs, averageBytesPerChar, maxBytesPerChar, defaultReplacement[]);
    }

    /// The charset that created this encoder.
    final Charset charset() const pure nothrow @nogc
    {
        return charset_;
    }

    /// A copy of this encoder's replacement value.
    final byte[] replacement() const pure nothrow
    {
        return replacement_.dup;
    }

    /++
    Changes the replacement to a copy of `newReplacement`, then calls `implReplaceWith` with the copy.
    Throws: `IllegalArgumentException` when the replacement is empty (or `null`, R26), longer than
    `maxBytesPerChar()`, or not legal by `isLegalReplacement`.
    +/
    final CharsetEncoder replaceWith(scope const(byte)[] newReplacement)
    {
        checkReplacementLength(newReplacement.length, maxBytesPerChar_);
        if (!isLegalReplacement(newReplacement))
            throwIllegalArgument("Illegal replacement");
        replacement_ = newReplacement.dup;
        implReplaceWith(replacement_);
        return this;
    }

    /// Reports a change to this encoder's replacement. The default does nothing.
    protected void implReplaceWith(byte[] newReplacement)
    {
    }

    /++
    Whether `repl` is a legal replacement: by default, whether this charset's decoder decodes it without an error
    under the REPORT actions. This port has the decoders of the six standard charsets only.
    +/
    bool isLegalReplacement(scope const(byte)[] repl)
    {
        return isLegalReplacementFor(charset_, repl);
    }

    /// The current action for malformed-input errors.
    CodingErrorAction malformedInputAction()
    {
        return malformedInputAction_;
    }

    /// Changes the action for malformed-input errors, then calls `implOnMalformedInput`.
    final CharsetEncoder onMalformedInput(CodingErrorAction newAction)
    {
        malformedInputAction_ = newAction;
        implOnMalformedInput(newAction);
        return this;
    }

    /// Reports a change to the malformed-input action. The default does nothing.
    protected void implOnMalformedInput(CodingErrorAction newAction)
    {
    }

    /// The current action for unmappable-character errors.
    CodingErrorAction unmappableCharacterAction()
    {
        return unmappableCharacterAction_;
    }

    /// Changes the action for unmappable-character errors, then calls `implOnUnmappableCharacter`.
    final CharsetEncoder onUnmappableCharacter(CodingErrorAction newAction)
    {
        unmappableCharacterAction_ = newAction;
        implOnUnmappableCharacter(newAction);
        return this;
    }

    /// Reports a change to the unmappable-character action. The default does nothing.
    protected void implOnUnmappableCharacter(CodingErrorAction newAction)
    {
    }

    /// The average number of bytes produced for each character of input.
    final float averageBytesPerChar() const pure nothrow @nogc
    {
        return averageBytesPerChar_;
    }

    /// The maximum number of bytes produced for each character of input.
    final float maxBytesPerChar() const pure nothrow @nogc
    {
        return maxBytesPerChar_;
    }

    /++
    Encodes as many characters as possible from `in_` into `out_`, applying the error actions.
    Throws: `IllegalStateException` when an encoding operation is already in progress and is not being continued;
    `CoderMalfunctionError` when `encodeLoop` throws a `RuntimeException`, or when either buffer is `null`.
    +/
    final CoderResult encode(CharBuffer in_, ByteBuffer out_, bool endOfInput)
    {
        const ubyte newState = endOfInput ? stEnd : stCoding;
        if (state != stReset && state != stCoding && !(endOfInput && state == stEnd))
            throwIllegalState(state, newState);
        state = newState;
        for (;;)
        {
            CoderResult cr = runLoop(in_, out_);
            if (cr.isOverflow())
                return cr;
            if (cr.isUnderflow())
            {
                if (!endOfInput || !in_.hasRemaining())
                    return cr;
                cr = CoderResult.malformedForLength(in_.remaining());
            }
            const action = cr.isMalformed() ? malformedInputAction_ : unmappableCharacterAction_;
            if (action == CodingErrorAction.REPORT)
                return cr;
            if (action == CodingErrorAction.REPLACE)
            {
                if (out_.remaining() < replacement_.length)
                    return CoderResult.OVERFLOW;
                out_.put(replacement_);
            }
            in_.position(in_.position() + cr.length());
        }
    }

    private CoderResult runLoop(CharBuffer in_, ByteBuffer out_)
    {
        if (in_ is null || out_ is null)
            throw new CoderMalfunctionError(new NullPointerException());
        try
            return encodeLoop(in_, out_);
        catch (RuntimeException x)
            throw new CoderMalfunctionError(x);
    }

    /++
    Flushes this encoder after the final `encode(…, true)`.
    Throws: `IllegalStateException` when the previous step was not `encode` with `endOfInput` true, or a flush.
    +/
    final CoderResult flush(ByteBuffer out_)
    {
        if (state == stEnd)
        {
            const cr = implFlush(out_);
            if (cr.isUnderflow())
                state = stFlushed;
            return cr;
        }
        if (state != stFlushed)
            throwIllegalState(state, stFlushed);
        return CoderResult.UNDERFLOW;
    }

    /// Flushes this encoder's internal state. The default writes nothing and returns UNDERFLOW.
    protected CoderResult implFlush(ByteBuffer out_)
    {
        return CoderResult.UNDERFLOW;
    }

    /// Clears any internal state, then calls `implReset`.
    final CharsetEncoder reset()
    {
        implReset();
        state = stReset;
        return this;
    }

    /// Clears charset-specific internal state. The default does nothing.
    protected void implReset()
    {
    }

    /// Encodes one or more characters into one or more bytes. Implemented by each charset.
    protected abstract CoderResult encodeLoop(CharBuffer in_, ByteBuffer out_);

    /++
    Whether this encoder can encode the character `c`. It runs a complete encoding operation, so it resets the
    encoder and must not be called while an encoding operation is in progress.
    Throws: `IllegalStateException` when an encoding operation is in progress.
    +/
    bool canEncode(wchar c)
    {
        auto cb = CharBuffer.allocate(1);
        cb.put(c);
        cb.flip();
        return canEncodeBuffer(cb);
    }

    /// Whether this encoder can encode the UTF-8 character sequence `cs`, as UTF-16 (R14, R26).
    bool canEncode(scope const(char)[] cs)
    {
        auto cb = CharBuffer.allocate(utf16Length(cs));
        cb.put(cs);
        cb.flip();
        return canEncodeBuffer(cb);
    }

    /// Whether this encoder can encode the remaining characters of `cs`, without moving its position.
    bool canEncode(CharBuffer cs)
    {
        if (cs is null)
            throw new NullPointerException();
        return canEncodeBuffer(cs.duplicate());
    }

    private bool canEncodeBuffer(CharBuffer cb)
    {
        if (state == stFlushed)
            reset();
        else if (state != stReset)
            throwIllegalState(state, stCoding);
        const malformed = malformedInputAction();
        const unmappable = unmappableCharacterAction();
        scope (exit)
        {
            onMalformedInput(malformed);
            onUnmappableCharacter(unmappable);
            reset();
        }
        onMalformedInput(CodingErrorAction.REPORT);
        onUnmappableCharacter(CodingErrorAction.REPORT);
        return !encodeAll(cb).result.isError();
    }

    /++
    Encodes the remaining characters of `in_` into a newly allocated byte buffer, as Java's `encode(CharBuffer)` does:
    it resets the encoder, encodes with `endOfInput` true, flushes, grows the output on overflow, and flips the buffer
    before returning it.
    Throws: `MalformedInputException` or `UnmappableCharacterException` (both `CharacterCodingException`) when a REPORT
    action stops the loop on an error.
    +/
    final ByteBuffer encode(CharBuffer in_)
    {
        if (in_ is null)
            throw new NullPointerException();
        auto outcome = encodeAll(in_);
        if (outcome.result.isError())
            outcome.result.throwException();
        outcome.buffer.flip();
        return outcome.buffer;
    }

    private struct EncodeOutcome
    {
        CoderResult result;
        ByteBuffer buffer;
    }

    // The convenience encode(CharBuffer) without its CharacterCodingException: an error result is returned.
    private EncodeOutcome encodeAll(CharBuffer in_)
    {
        int n = estimateCapacity(in_.remaining(), averageBytesPerChar());
        auto out_ = ByteBuffer.allocate(n);
        if (n == 0 && in_.remaining() == 0)
            return EncodeOutcome(CoderResult.UNDERFLOW, out_);
        reset();
        for (;;)
        {
            CoderResult cr = in_.hasRemaining() ? encode(in_, out_, true) : CoderResult.UNDERFLOW;
            if (cr.isUnderflow())
                cr = flush(out_);
            if (cr.isUnderflow())
                return EncodeOutcome(cr, out_);
            if (!cr.isOverflow())
                return EncodeOutcome(cr, out_);
            n = grownCapacity(n);
            auto grown = ByteBuffer.allocate(n);
            out_.flip();
            grown.put(out_);
            out_ = grown;
        }
    }
}
