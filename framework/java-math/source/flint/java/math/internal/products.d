/*
 *  Licensed to the Apache Software Foundation (ASF) under one or more
 *  contributor license agreements.  See the NOTICE file distributed with
 *  this work for additional information regarding copyright ownership.
 *  The ASF licenses this file to You under the Apache License, Version 2.0
 *  (the "License"); you may not use this file except in compliance with
 *  the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  Copyright 2006, 2010 The Apache Software Foundation.
 *  Ported from harmony 6.0M3, classlib/modules/math/src/main/java/java/math/Multiplication.java
 *  Modified by the Flint authors.
 */
module flint.java.math.internal.products;

@safe:

package(flint.java.math):

/// Multiply two magnitudes into a zeroed destination with room for both lengths.
void multiplyLimbs(scope uint[] product, scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    foreach (i, word; left)
    {
        ulong carry;
        foreach (j, factor; right)
        {
            // A full limb product plus a limb and a carry fits in 64 bits.
            const ulong sum = cast(ulong) word * factor + product[i + j] + carry;
            product[i + j] = cast(uint) sum;
            carry = sum >> 32;
        }
        product[i + right.length] = cast(uint) carry;
    }
}
