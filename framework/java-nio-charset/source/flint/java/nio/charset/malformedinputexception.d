/*
 * Copyright (c) 2000, 2021, Oracle and/or its affiliates. All rights reserved.
 *
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
 *
 */

/*
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/MalformedInputException.java
 * Modified by the Flint authors.
 */
module flint.java.nio.charset.malformedinputexception;

import flint.java.lang : Integer;
import flint.java.nio.charset.charactercodingexception : CharacterCodingException;

@safe:

/// Checked exception thrown when an input byte sequence is not legal for given charset, or an input character sequence is not a legal sixteen-bit Unicode sequence.
class MalformedInputException : CharacterCodingException
{
    private int inputLength;

    /// Constructs an instance with the given input length; the cause stays open. The message, `Input length = `
    /// and the length, is built here once, because `getMessage` is `@nogc` in Flint.
    this(int inputLength, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Input length = " ~ Integer.toString(inputLength), file, line);
        this.inputLength = inputLength;
    }

    /// The length of the input.
    int getInputLength() const pure nothrow @nogc
    {
        return inputLength;
    }
}
