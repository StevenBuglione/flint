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
