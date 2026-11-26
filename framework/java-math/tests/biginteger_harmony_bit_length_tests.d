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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerOperateBitsTest.java
 *  Modified by the Flint authors.
 */
module biginteger_harmony_bit_length_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

private static immutable byte[] wideMagnitude = [
    12, 56, 100, -2, -76, 89, 45, 91, 3, -15, 35, 26, 3, 91
];
private static immutable byte[] topBitSet = [-128, 56, 100, -2, -76, 89, 45, 91, 3, -15, 35, 26];
private static immutable byte[] powerOfTwo = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

@("testBitLengthZero") unittest
{
    assert(BigInteger.valueOf(0).bitLength() == 0);
}

@("testBitLengthPositive1") unittest
{
    assert(new BigInteger(1, wideMagnitude).bitLength() == 108);
}

@("testBitLengthPositive2") unittest
{
    assert(new BigInteger(1, topBitSet).bitLength() == 96);
}

@("testBitLengthPositive3") unittest
{
    assert(new BigInteger(1, powerOfTwo).bitLength() == 81);
}

@("testBitLengthNegative1") unittest
{
    assert(new BigInteger(-1, wideMagnitude).bitLength() == 108);
}

@("testBitLengthNegative2") unittest
{
    assert(new BigInteger(-1, topBitSet).bitLength() == 96);
}

@("testBitLengthNegative3") unittest
{
    assert(new BigInteger(-1, powerOfTwo).bitLength() == 80);
}
