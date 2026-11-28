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
 * (the decoder expansion, CharsetDecoder).
 * Modified by the Flint authors.
 */
/** `java.nio.charset.CharsetDecoder`. */
module flint.java.nio.charset.charsetdecoder;

import flint.java.lang : NullPointerException, RuntimeException, UnsupportedOperationException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset;
import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.codingerroraction : CodingErrorAction;
import flint.java.nio.charset.internal.coders : checkRates, checkReplacementLength, estimateCapacity,
    grownCapacity, stCoding, stEnd, stFlushed, stReset, throwIllegalState, utf16Length;

@safe:

/++
An engine that transforms a sequence of bytes in a specific charset into a sequence of 16-bit Unicode characters.

Subclasses implement `decodeLoop`. The replacement is a Java `String`, so it is a D `string` here, and its length is
counted in UTF-16 units (R14). `Charset.init` stands for a `null` charset.
+/
abstract class CharsetDecoder
{
    private Charset charset_;
    private float averageCharsPerByte_;
    private float maxCharsPerByte_;
    private string replacement_;
    private int replacementLength;
    private CodingErrorAction malformedInputAction_ = CodingErrorAction.REPORT;
    private CodingErrorAction unmappableCharacterAction_ = CodingErrorAction.REPORT;
    private ubyte state = stReset;

    /++
    Initializes a decoder with the replacement `"\uFFFD"` and the REPORT action for both kinds of error.
    Throws: `IllegalArgumentException` when either rate is not positive, or the average exceeds the maximum.
    +/
    protected this(Charset cs, float averageCharsPerByte, float maxCharsPerByte)
    {
        charset_ = cs;
        checkRates(averageCharsPerByte, maxCharsPerByte, "averageCharsPerByte", "maxCharsPerByte");
        replacement_ = "\uFFFD";
        averageCharsPerByte_ = averageCharsPerByte;
        maxCharsPerByte_ = maxCharsPerByte;
        replaceWith("\uFFFD");
    }

    /// The charset that created this decoder.
    final Charset charset() const pure nothrow @nogc
    {
        return charset_;
    }

    /// This decoder's replacement value.
    final string replacement() const pure nothrow @nogc
    {
        return replacement_;
    }

    /++
    Changes the replacement, then calls `implReplaceWith`.
    Throws: `IllegalArgumentException` when the replacement is empty (or `null`, R26) or longer than
    `maxCharsPerByte()` UTF-16 units.
    +/
    final CharsetDecoder replaceWith(string newReplacement)
    {
        const length = utf16Length(newReplacement);
        checkReplacementLength(length, maxCharsPerByte_);
        replacement_ = newReplacement;
        replacementLength = length;
        implReplaceWith(replacement_);
        return this;
    }

    /// Reports a change to this decoder's replacement. The default does nothing.
    protected void implReplaceWith(string newReplacement)
    {
    }

    /// The current action for malformed-input errors.
    CodingErrorAction malformedInputAction()
    {
        return malformedInputAction_;
    }

    /// Changes the action for malformed-input errors, then calls `implOnMalformedInput`.
    final CharsetDecoder onMalformedInput(CodingErrorAction newAction)
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
    final CharsetDecoder onUnmappableCharacter(CodingErrorAction newAction)
    {
        unmappableCharacterAction_ = newAction;
        implOnUnmappableCharacter(newAction);
        return this;
    }

    /// Reports a change to the unmappable-character action. The default does nothing.
    protected void implOnUnmappableCharacter(CodingErrorAction newAction)
    {
    }

    /// The average number of characters produced for each byte of input.
    final float averageCharsPerByte() const pure nothrow @nogc
    {
        return averageCharsPerByte_;
    }

    /// The maximum number of characters produced for each byte of input.
    final float maxCharsPerByte() const pure nothrow @nogc
    {
        return maxCharsPerByte_;
    }

    /++
    Decodes as many bytes as possible from `in_` into `out_`, applying the error actions.
    Throws: `IllegalStateException` when a decoding operation is already in progress and is not being continued;
    `CoderMalfunctionError` when `decodeLoop` throws a `RuntimeException`, or when either buffer is `null`.
    +/
    final CoderResult decode(ByteBuffer in_, CharBuffer out_, bool endOfInput)
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
                if (out_.remaining() < replacementLength)
                    return CoderResult.OVERFLOW;
                out_.put(replacement_);
            }
            in_.position(in_.position() + cr.length());
        }
    }

    private CoderResult runLoop(ByteBuffer in_, CharBuffer out_)
    {
        if (in_ is null || out_ is null)
            throw new CoderMalfunctionError(new NullPointerException());
        try
            return decodeLoop(in_, out_);
        catch (RuntimeException x)
            throw new CoderMalfunctionError(x);
    }

    /++
    Decodes the remaining bytes of `in_` into a newly allocated character buffer, as Java's `decode(ByteBuffer)` does:
    it resets the decoder, decodes with `endOfInput` true, flushes, grows the output on overflow, and flips the buffer
    before returning it.
    Throws: `MalformedInputException` or `UnmappableCharacterException` (both `CharacterCodingException`) when a REPORT
    action stops the loop on an error.
    +/
    final CharBuffer decode(ByteBuffer in_)
    {
        if (in_ is null)
            throw new NullPointerException();
        int n = estimateCapacity(in_.remaining(), averageCharsPerByte_);
        auto output = CharBuffer.allocate(n);
        if (n == 0 && in_.remaining() == 0)
            return output;
        reset();
        for (;;)
        {
            CoderResult cr = in_.hasRemaining() ? decode(in_, output, true) : CoderResult.UNDERFLOW;
            if (cr.isUnderflow())
                cr = flush(output);
            if (cr.isUnderflow())
                break;
            if (cr.isOverflow())
            {
                n = grownCapacity(n);
                auto grown = CharBuffer.allocate(n);
                output.flip();
                grown.put(output);
                output = grown;
                continue;
            }
            cr.throwException();
        }
        output.flip();
        return output;
    }

    /++
    Flushes this decoder after the final `decode(…, true)`.
    Throws: `IllegalStateException` when the previous step was not `decode` with `endOfInput` true, or a flush.
    +/
    final CoderResult flush(CharBuffer out_)
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

    /// Flushes this decoder's internal state. The default writes nothing and returns UNDERFLOW.
    protected CoderResult implFlush(CharBuffer out_)
    {
        return CoderResult.UNDERFLOW;
    }

    /// Clears any internal state, then calls `implReset`.
    final CharsetDecoder reset()
    {
        implReset();
        state = stReset;
        return this;
    }

    /// Clears charset-specific internal state. The default does nothing.
    protected void implReset()
    {
    }

    /// Decodes one or more bytes into one or more characters. Implemented by each charset.
    protected abstract CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_);

    /// Whether this decoder detects the charset. False by default.
    bool isAutoDetecting()
    {
        return false;
    }

    /// Throws `UnsupportedOperationException` unless overridden by an auto-detecting decoder.
    bool isCharsetDetected()
    {
        throw new UnsupportedOperationException();
    }

    /// Throws `UnsupportedOperationException` unless overridden by an auto-detecting decoder.
    Charset detectedCharset()
    {
        throw new UnsupportedOperationException();
    }
}
