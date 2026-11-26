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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerMultiplyTest.java
 *  Modified by the Flint authors.
 */
module biginteger_multiply_tests;

import flint.java.lang : ArithmeticException;
import flint.java.math.biginteger : BigInteger;

@safe:

@("testCase1")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        10, 40, 100, -55, 96, 51, 76, 40, -45, 85, 105, 4, 28, -86, -117, -52, 100, 120, 90
    ]);
    assert(result.signum() == 1);
}

@("testCase2")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        -11, -41, -101, 54, -97, -52, -77, -41, 44, -86, -106, -5, -29, 85, 116, 51, -101, -121, -90
    ]);
    assert(result.signum() == -1);
}

@("testCase3")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        10, 40, 100, -55, 96, 51, 76, 40, -45, 85, 115, 44, -127, 115, -21, -62, -15, 85, 64,
        -87, -2, -36, -36, -106
    ]);
    assert(result.signum() == 1);
}

@("testCase4")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        10, 40, 100, -55, 96, 51, 76, 40, -45, 85, 115, 44, -127, 115, -21, -62, -15, 85, 64,
        -87, -2, -36, -36, -106
    ]);
    assert(result.signum() == 1);
}

@("testCase5")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        -11, -41, -101, 54, -97, -52, -77, -41, 44, -86, -116, -45, 126, -116, 20, 61, 14, -86,
        -65, 86, 1, 35, 35, 106
    ]);
    assert(result.signum() == -1);
}

@("testCase6")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        -11, -41, -101, 54, -97, -52, -77, -41, 44, -86, -116, -45, 126, -116, 20, 61, 14, -86,
        -65, 86, 1, 35, 35, 106
    ]);
    assert(result.signum() == -1);
}

@("testCase7")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger(0, [0]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("testCase8")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger([0]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("testCase9")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger([1]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    assert(result.signum() == 1);
}

@("testCase10")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 1, 2, 3, 4, 5]);
    auto right = new BigInteger([1]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [
        -2, -3, -4, -5, -6, -7, -8, -2, -3, -4, -2, -3, -4, -5, -5
    ]);
    assert(result.signum() == -1);
}

@("testIntbyInt1")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40]);
    auto right = new BigInteger(-1, [1, 2, 3, 4]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [-11, -41, -101, 55, 5, 15, 96]);
    assert(result.signum() == -1);
}

@("testIntbyInt2")
unittest
{
    auto left = new BigInteger(1, [-1, -1, -1, -1]);
    auto right = new BigInteger(1, [-1, -1, -1, -1]);
    auto result = left.multiply(right);
    assert(result.toByteArray() == [0, -1, -1, -1, -2, 0, 0, 0, 1]);
    assert(result.signum() == 1);
}

@("Full limbs carry across the entire product")
unittest
{
    auto value = new BigInteger(1, [-1, -1, -1, -1, -1, -1, -1, -1]);
    assert(value.multiply(value).toByteArray() == [
        0, -1, -1, -1, -1, -1, -1, -1, -2, 0, 0, 0, 0, 0, 0, 0, 1
    ]);
}

@("BigIntegerMultiplyTest.testPowNegativeNumToOddExp")
unittest
{
    auto value = new BigInteger(-1, [50, -26, 90, 69, 120, 32, 63, -103, -14, 35]);
    auto result = value.pow(5);
    assert(result.toByteArray() == [
        -21, -94, -42, -15, -127, 113, -50, -88, 115, -35, 3, 59, -92, 111, -75, 103, -42,
        41, 34, -114, 99, -32, 105, -59, 127, 45, 108, 74, -93, 105, 33, 12, -5, -20, 17, -21,
        -119, -127, -115, 27, -122, 26, -67, 109, -125, 16, 91, -70, 109
    ]);
    assert(result.signum() == -1);
}

@("BigIntegerMultiplyTest.testPowNegativeNumToEvenExp")
unittest
{
    auto value = new BigInteger(-1, [50, -26, 90, 69, 120, 32, 63, -103, -14, 35]);
    auto result = value.pow(4);
    assert(result.toByteArray() == [
        102, 107, -122, -43, -52, -20, -27, 25, -9, 88, -13, 75, 78, 81, -33, -77, 39, 27, -37,
        106, 121, -73, 108, -47, -101, 80, -25, 71, 13, 94, -7, -33, 1, -17, -65, -70, -61, -3, -47
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerMultiplyTest.testPowNegativeNumToZeroExp")
unittest
{
    auto value = new BigInteger(-1, [50, -26, 90, 69, 120, 32, 63, -103, -14, 35]);
    auto result = value.pow(0);
    assert(result.toByteArray() == [1]);
    assert(result.signum() == 1);
}

@("BigIntegerMultiplyTest.testPowPositiveNum")
unittest
{
    auto value = new BigInteger(1, [50, -26, 90, 69, 120, 32, 63, -103, -14, 35]);
    auto result = value.pow(5);
    assert(result.toByteArray() == [
        20, 93, 41, 14, 126, -114, 49, 87, -116, 34, -4, -60, 91, -112, 74, -104, 41, -42,
        -35, 113, -100, 31, -106, 58, -128, -46, -109, -75, 92, -106, -34, -13, 4, 19, -18,
        20, 118, 126, 114, -28, 121, -27, 66, -110, 124, -17, -92, 69, -109
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerMultiplyTest.testPowPositiveNumToZeroExp")
unittest
{
    auto value = new BigInteger(1, [50, -26, 90, 69, 120, 32, 63, -103, -14, 35]);
    auto result = value.pow(0);
    assert(result.toByteArray() == [1]);
    assert(result.signum() == 1);
}

@("BigIntegerMultiplyTest.testPowException")
unittest
{
    auto value = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    try
    {
        value.pow(-5);
        assert(0, "negative exponent accepted");
    }
    catch (ArithmeticException failure)
    {
        assert(failure.getMessage() == "Negative exponent");
    }
}

@("BigInteger exponentiation handles zero and rejects out-of-range powers before allocation")
unittest
{
    assert(BigInteger.valueOf(0).pow(0).intValueExact() == 1);
    assert(BigInteger.valueOf(0).pow(int.max).signum() == 0);
    assert(BigInteger.valueOf(-1).pow(int.max).intValueExact() == -1);
    assert(BigInteger.valueOf(-1).pow(int.max - 1).intValueExact() == 1);
    auto power = BigInteger.valueOf(-16).pow(25);
    assert(power.signum() == -1);
    assert(power.toString(16) == "-10000000000000000000000000");
    try
    {
        BigInteger.valueOf(2).pow(int.max);
        assert(0, "power exceeds the supported range");
    }
    catch (ArithmeticException)
    {
    }
}
