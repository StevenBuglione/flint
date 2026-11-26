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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerAddTest.java
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerSubtractTest.java
 *  Modified by the Flint authors.
 */
module biginteger_tests;

import flint.java.lang : IndexOutOfBoundsException, NullPointerException, NumberFormatException;
import flint.java.math.biginteger : BigInteger;

@safe:

@("BigIntegerAddTest.testCase1")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [11, 22, 33, 44, 55, 66, 77, 11, 22, 33]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase2")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [-12, -23, -34, -45, -56, -67, -78, -12, -23, -33]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase3")
unittest
{
    auto left = new BigInteger(1, [3, 4, 5, 6, 7, 8, 9]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [2, 2, 2, 2, 2, 2, 2]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase4")
unittest
{
    auto left = new BigInteger(-1, [3, 4, 5, 6, 7, 8, 9]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [-3, -3, -3, -3, -3, -3, -2]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase5")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(-1, [3, 4, 5, 6, 7, 8, 9]);
    auto result = left.add(right);
    assert(result.toByteArray() == [-3, -3, -3, -3, -3, -3, -2]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase6")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [3, 4, 5, 6, 7, 8, 9]);
    auto result = left.add(right);
    assert(result.toByteArray() == [2, 2, 2, 2, 2, 2, 2]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase7")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 15, 26, 37, 41, 52, 63, 74, 15, 26, 37]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase8")
unittest
{
    auto left = new BigInteger([10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger([1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 15, 26, 37, 41, 52, 63, 74, 15, 26, 37]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase9")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [
        -2, -3, -4, -5, -16, -27, -38, -42, -53, -64, -75, -16, -27, -37
    ]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase10")
unittest
{
    auto left = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [
        -2, -3, -4, -5, -16, -27, -38, -42, -53, -64, -75, -16, -27, -37
    ]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase11")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [
        1, 2, 3, 3, -6, -15, -24, -40, -49, -58, -67, -6, -15, -23
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase12")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [-2, -3, -4, -4, 5, 14, 23, 39, 48, 57, 66, 5, 14, 23]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase13")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.add(right);
    assert(result.toByteArray() == [-2, -3, -4, -4, 5, 14, 23, 39, 48, 57, 66, 5, 14, 23]);
    assert(result.signum() == -1);
}

@("BigIntegerAddTest.testCase14")
unittest
{
    auto left = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [
        1, 2, 3, 3, -6, -15, -24, -40, -49, -58, -67, -6, -15, -23
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase15")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerAddTest.testCase16")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [0]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 5, 6, 7]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase17")
unittest
{
    auto left = new BigInteger(1, [0]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 5, 6, 7]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase18")
unittest
{
    auto left = new BigInteger(1, [0]);
    auto right = new BigInteger(1, [0]);
    auto result = left.add(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerAddTest.testCase19")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger([0]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 5, 6, 7]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase20")
unittest
{
    auto left = new BigInteger([0]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 5, 6, 7]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase21")
unittest
{
    auto left = new BigInteger([0]);
    auto right = new BigInteger([0]);
    auto result = left.add(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerAddTest.testCase22")
unittest
{
    auto left = new BigInteger([1]);
    auto right = new BigInteger([1]);
    auto result = left.add(right);
    assert(result.toByteArray() == [2]);
    assert(result.signum() == 1);
}

@("BigIntegerAddTest.testCase23")
unittest
{
    auto left = new BigInteger(1, [
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ]);
    auto right = new BigInteger(1, [-1, -1, -1, -1, -1, -1, -1, -1]);
    auto result = left.add(right);
    assert(result.toByteArray() == [1, 0, 0, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1, -1, -2]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase1")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [9, 18, 27, 36, 45, 54, 63, 9, 18, 27]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase2")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-10, -19, -28, -37, -46, -55, -64, -10, -19, -27]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase3")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [11, 22, 33, 44, 55, 66, 77, 11, 22, 33]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase4")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [11, 22, 33, 44, 55, 66, 77, 11, 22, 33]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase5")
unittest
{
    auto left = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-10, -19, -28, -37, -46, -55, -64, -10, -19, -27]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase6")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [9, 18, 27, 36, 45, 54, 63, 9, 18, 27]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase7")
unittest
{
    auto left = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-12, -23, -34, -45, -56, -67, -78, -12, -23, -33]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase8")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-12, -23, -34, -45, -56, -67, -78, -12, -23, -33]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase9")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [
        1, 2, 3, 3, -6, -15, -24, -40, -49, -58, -67, -6, -15, -23
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase10")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-2, -3, -4, -4, 5, 14, 23, 39, 48, 57, 66, 5, 14, 23]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase11")
unittest
{
    auto left = new BigInteger(1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 15, 26, 37, 41, 52, 63, 74, 15, 26, 37]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase12")
unittest
{
    auto left = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [1, 2, 3, 4, 15, 26, 37, 41, 52, 63, 74, 15, 26, 37]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase13")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [
        -2, -3, -4, -5, -16, -27, -38, -42, -53, -64, -75, -16, -27, -37
    ]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase14")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [
        -2, -3, -4, -5, -16, -27, -38, -42, -53, -64, -75, -16, -27, -37
    ]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase15")
unittest
{
    auto left = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto right = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-2, -3, -4, -4, 5, 14, 23, 39, 48, 57, 66, 5, 14, 23]);
    assert(result.signum() == -1);
}

@("BigIntegerSubtractTest.testCase16")
unittest
{
    auto left = new BigInteger(-1, [10, 20, 30, 40, 50, 60, 70, 10, 20, 30]);
    auto right = new BigInteger(-1, [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [
        1, 2, 3, 3, -6, -15, -24, -40, -49, -58, -67, -6, -15, -23
    ]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase17")
unittest
{
    auto left = new BigInteger(1, [-120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto right = new BigInteger(1, [-120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerSubtractTest.testCase18")
unittest
{
    auto left = new BigInteger(1, [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto right = new BigInteger(0, [0]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase19")
unittest
{
    auto left = new BigInteger(0, [0]);
    auto right = new BigInteger(-1, [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase20")
unittest
{
    auto left = new BigInteger(0, [0]);
    auto right = new BigInteger(0, [0]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerSubtractTest.testCase21")
unittest
{
    auto left = new BigInteger(1, [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto right = new BigInteger([0]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase22")
unittest
{
    auto left = new BigInteger([0]);
    auto right = new BigInteger(-1, [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [120, 34, 78, -23, -111, 45, 127, 23, 45, -3]);
    assert(result.signum() == 1);
}

@("BigIntegerSubtractTest.testCase23")
unittest
{
    auto left = new BigInteger([0]);
    auto right = new BigInteger([0]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerSubtractTest.testCase24")
unittest
{
    auto left = new BigInteger([1]);
    auto right = new BigInteger([1]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [0]);
    assert(result.signum() == 0);
}

@("BigIntegerSubtractTest.testCase25")
unittest
{
    auto left = new BigInteger(1, [-1, -1, -1, -1, -1, -1, -1, -1]);
    auto right = new BigInteger(1, [-128, -128, -128, -128, -128, -128, -128, -128, -128]);
    auto result = left.subtract(right);
    assert(result.toByteArray() == [-128, 127, 127, 127, 127, 127, 127, 127, 127]);
    assert(result.signum() == -1);
}

@("Java 9 byte ranges copy only the selected bytes")
unittest
{
    byte[] input = [17, -1, 127, 23];
    auto negative = new BigInteger(input, 1, 2);
    auto positive = new BigInteger(1, input, 2, 1);
    input[1 .. 3] = 0;
    assert(negative.toByteArray() == [-1, 127]);
    assert(positive.toByteArray() == [127]);
    assert((new BigInteger(input, 2, 0)).toByteArray() == [0]);
    assert((new BigInteger(-1, input, 0, 0)).signum() == 0);

    auto copy = negative.toByteArray();
    copy[0] = 0;
    assert(negative.toByteArray() == [-1, 127]);
}

@("Signed bytes keep the sign bit at limb boundaries")
unittest
{
    const byte[][] encodings = [
        [0], [-1], [-128], [0, -128], [-1, 127], [-128, 0, 0, 0], [0, -128, 0, 0, 0],
        [-1, 127, -1, -1, -1], [0, -1, -1, -1, -1]
    ];
    foreach (bytes; encodings)
        assert((new BigInteger(bytes)).toByteArray() == bytes);
    assert((new BigInteger([0, 0, 0])).toByteArray() == [0]);
    assert((new BigInteger([-1, -1, -128])).toByteArray() == [-128]);
    assert((new BigInteger(-1, [0, 0, 0])).signum() == 0);
}

@("Binary constructors distinguish empty signed encodings from empty magnitudes")
unittest
{
    import std.exception : assertThrown;

    byte[] empty = [];
    assertThrown!NumberFormatException(new BigInteger(empty));
    assertThrown!NumberFormatException(new BigInteger(new byte[0]));
    assertThrown!NumberFormatException(new BigInteger(cast(byte[]) null));
    assertThrown!NumberFormatException(new BigInteger((new byte[1])[0 .. 0]));
    assert((new BigInteger(0, new byte[0])).signum() == 0);
    assert((new BigInteger(-1, cast(byte[]) null)).signum() == 0);
}

@("Binary constructors reject invalid signs and slices")
unittest
{
    import std.exception : assertThrown;

    assertThrown!NumberFormatException(new BigInteger(2, [1]));
    assertThrown!NumberFormatException(new BigInteger(0, [0, 1]));
    assertThrown!IndexOutOfBoundsException(new BigInteger([1], 1, 1));
    assertThrown!IndexOutOfBoundsException(new BigInteger(1, [1], int.max, 1));
}

@("Signed arithmetic cancels to zero and shares no mutable bytes")
unittest
{
    import std.exception : assertThrown;

    auto negative = new BigInteger([-128, 0, 0, 0]);
    auto positive = new BigInteger(1, [-128, 0, 0, 0]);
    assert(positive.add(negative).signum() == 0);
    assert(negative.subtract(negative).toByteArray() == [0]);
    assert(negative.add(negative).toByteArray() == [-1, 0, 0, 0, 0]);
    assert(positive.subtract(negative).toByteArray() == [1, 0, 0, 0, 0]);
    assert(negative.compareTo(positive) < 0);
    assert(positive.compareTo(negative) > 0);
    assert(negative.compareTo(new BigInteger([-1, -128, 0, 0, 0])) == 0);
    assertThrown!NullPointerException(negative.add(null));
}

@("Extrema reuse their operands and reject null") unittest
{
    import std.exception : assertThrown;

    auto negative = BigInteger.valueOf(long.min);
    auto positive = negative.negate();
    assert(positive.toByteArray() == [0, -128, 0, 0, 0, 0, 0, 0, 0]);
    assert(negative.longValueExact() == long.min);
    assert(negative.abs() == positive);
    assert(positive.abs() is positive);
    assert(negative.min(positive) is negative);
    assert(negative.max(positive) is positive);
    assertThrown!NullPointerException(negative.min(null));
    assertThrown!NullPointerException(negative.max(null));
}
