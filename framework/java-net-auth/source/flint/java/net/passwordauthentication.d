/*
 * Copyright (c) 1997, 2013, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/PasswordAuthentication.java
// Modified by the Flint authors.

/++
`java.net.PasswordAuthentication`: the user name and password that an `Authenticator` supplies. Equality and hashing
are by identity, as in Java, which doesn't override `equals` or `hashCode`.
+/
module flint.java.net.passwordauthentication;

@safe:

/// A user name and a password. The constructor copies the password, and `getPassword` returns that copy.
final class PasswordAuthentication
{
    private string userName;
    private wchar[] password;

    /++
    Stores `userName` and a copy of `password`, so later changes to the caller's array don't reach this object. A
    `null` password counts as empty (R26), where Java throws `NullPointerException`.
    +/
    this(string userName, scope const(wchar)[] password) pure nothrow
    {
        this.userName = userName;
        this.password = password.dup;
    }

    /// The user name.
    string getUserName() const pure nothrow @nogc
    {
        return userName;
    }

    /++
    The stored password: the same array on every call, as in Java, so a caller can clear it once it has been used.
    +/
    wchar[] getPassword() pure nothrow @nogc
    {
        return password;
    }
}
