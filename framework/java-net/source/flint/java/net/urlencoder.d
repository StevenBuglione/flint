/*
 * Copyright (c) 1995, 2023, Oracle and/or its affiliates. All rights reserved.
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

/* Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/URLEncoder.java.
 * Modified by the Flint authors: D overloads using the Flint form codec and charset facade.
 */
/** Java SE's HTML form encoder. */
module flint.java.net.urlencoder;

import flint.java.net.internal.formcharset : throwNullArgument;
import flint.java.net.internal.formencode : encodeForm;
import flint.java.net.internal.formcharsetname : formCharsetForName;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

struct URLEncoder
{
    @disable this();

    /// Encode with Flint's UTF-8 default charset.
    deprecated("Use encode(String, Charset)") static string encode(string input) pure
    {
        return encode(input, StandardCharsets.UTF_8);
    }

    /// Throws UnsupportedEncodingException for an illegal or unsupported charset name.
    static string encode(string input, string name) pure
    {
        return encode(input, formCharsetForName(name, ""));
    }

    /// Throws NullPointerException for a null input or charset.
    static string encode(string input, Charset charset) pure
    {
        if (charset == Charset.init)
            throwNullArgument("charset");
        return encodeForm(input, charset);
    }
}
