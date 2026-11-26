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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerCompareTest.java
 *  Modified by the Flint authors.
 */
module biginteger_harmony_comparison_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

private static immutable byte[] largeMagnitude = [
    12, 56, 100, -2, -76, 89, 45, 91, 3, -15, 35, 26, 3, 91
];
private static immutable byte[] smallMagnitude = [45, 91, 3, -15, 35, 26, 3, 91];
private static immutable byte[] otherMagnitude = [10, 20, 30, 40, 50, 60, 70, 10, 20, 30];
private static immutable byte[] absMagnitude = [1, 2, 3, 4, 5, 6, 7];
private static immutable byte[] negativeBytes = [
    -13, -57, -101, 1, 75, -90, -46, -92, -4, 14, -36, -27, -4, -91
];

@("testAbsPositive") unittest
{
    auto result = new BigInteger(1, absMagnitude).abs();
    assert(result.toByteArray() == absMagnitude);
    assert(result.signum() == 1);
}

@("testAbsNegative") unittest
{
    auto result = new BigInteger(-1, absMagnitude).abs();
    assert(result.toByteArray() == absMagnitude);
    assert(result.signum() == 1);
}

@("testNegatePositive") unittest
{
    auto result = new BigInteger(1, largeMagnitude).negate();
    assert(result.toByteArray() == negativeBytes);
    assert(result.signum() == -1);
}

@("testNegateNegative") unittest
{
    auto result = new BigInteger(-1, largeMagnitude).negate();
    assert(result.toByteArray() == largeMagnitude);
    assert(result.signum() == 1);
}

@("testNegateZero") unittest
{
    auto result = BigInteger.valueOf(0).negate();
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("testCompareToPosPos1") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = new BigInteger(1, otherMagnitude);
    assert(left.compareTo(right) == 1);
}

@("testCompareToPosPos2") unittest
{
    auto left = new BigInteger(1, otherMagnitude);
    auto right = new BigInteger(1, largeMagnitude);
    assert(left.compareTo(right) == -1);
}

@("testCompareToEqualPos") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = new BigInteger(1, largeMagnitude);
    assert(left.compareTo(right) == 0);
}

@("testCompareToNegNeg1") unittest
{
    auto left = new BigInteger(-1, largeMagnitude);
    auto right = new BigInteger(-1, otherMagnitude);
    assert(left.compareTo(right) == -1);
}

@("testCompareNegNeg2") unittest
{
    auto left = new BigInteger(-1, otherMagnitude);
    auto right = new BigInteger(-1, largeMagnitude);
    assert(left.compareTo(right) == 1);
}

@("testCompareToEqualNeg") unittest
{
    auto left = new BigInteger(-1, largeMagnitude);
    auto right = new BigInteger(-1, largeMagnitude);
    assert(left.compareTo(right) == 0);
}

@("testCompareToDiffSigns1") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = new BigInteger(-1, otherMagnitude);
    assert(left.compareTo(right) == 1);
}

@("testCompareToDiffSigns2") unittest
{
    auto left = new BigInteger(-1, largeMagnitude);
    auto right = new BigInteger(1, otherMagnitude);
    assert(left.compareTo(right) == -1);
}

@("testCompareToPosZero") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = BigInteger.valueOf(0);
    assert(left.compareTo(right) == 1);
}

@("testCompareToZeroPos") unittest
{
    auto left = BigInteger.valueOf(0);
    auto right = new BigInteger(1, largeMagnitude);
    assert(left.compareTo(right) == -1);
}

@("testCompareToNegZero") unittest
{
    auto left = new BigInteger(-1, largeMagnitude);
    auto right = BigInteger.valueOf(0);
    assert(left.compareTo(right) == -1);
}

@("testCompareToZeroNeg") unittest
{
    auto left = BigInteger.valueOf(0);
    auto right = new BigInteger(-1, largeMagnitude);
    assert(left.compareTo(right) == 1);
}

@("testCompareToZeroZero") unittest
{
    auto left = BigInteger.valueOf(0);
    auto right = BigInteger.valueOf(0);
    assert(left.compareTo(right) == 0);
}

@("testMaxGreater") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = new BigInteger(1, smallMagnitude);
    auto result = left.max(right);
    assert(result.toByteArray() == largeMagnitude);
    assert(result.signum() == 1);
}

@("testMaxLess") unittest
{
    auto left = new BigInteger(1, smallMagnitude);
    auto right = new BigInteger(1, largeMagnitude);
    auto result = left.max(right);
    assert(result.toByteArray() == largeMagnitude);
    assert(result.signum() == 1);
}

@("testMaxEqual") unittest
{
    auto left = new BigInteger(1, smallMagnitude);
    auto right = new BigInteger(1, smallMagnitude);
    auto result = left.max(right);
    assert(result.toByteArray() == smallMagnitude);
    assert(result.signum() == 1);
}

@("testMaxNegZero") unittest
{
    auto left = new BigInteger(-1, smallMagnitude);
    auto right = BigInteger.valueOf(0);
    auto result = left.max(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("testMinGreater") unittest
{
    auto left = new BigInteger(1, largeMagnitude);
    auto right = new BigInteger(1, smallMagnitude);
    auto result = left.min(right);
    assert(result.toByteArray() == smallMagnitude);
    assert(result.signum() == 1);
}

@("testMinLess") unittest
{
    auto left = new BigInteger(1, smallMagnitude);
    auto right = new BigInteger(1, largeMagnitude);
    auto result = left.min(right);
    assert(result.toByteArray() == smallMagnitude);
    assert(result.signum() == 1);
}

@("testMinEqual") unittest
{
    auto left = new BigInteger(1, smallMagnitude);
    auto right = new BigInteger(1, smallMagnitude);
    auto result = left.min(right);
    assert(result.toByteArray() == smallMagnitude);
    assert(result.signum() == 1);
}

@("testMinPosZero") unittest
{
    auto left = new BigInteger(1, smallMagnitude);
    auto right = BigInteger.valueOf(0);
    auto result = left.min(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("testSignumPositive") unittest
{
    const value = new BigInteger(1, largeMagnitude);
    assert(value.signum() == 1);
}

@("testSignumNegative") unittest
{
    const value = new BigInteger(-1, largeMagnitude);
    assert(value.signum() == -1);
}

@("testSignumZero") unittest
{
    const value = BigInteger.valueOf(0);
    assert(value.signum() == 0);
}
