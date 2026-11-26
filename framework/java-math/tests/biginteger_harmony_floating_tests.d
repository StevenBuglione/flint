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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerConvertTest.java
 *  Modified by the Flint authors.
 */
module biginteger_harmony_floating_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

private static immutable byte[] belowDoubleOverflowMidpoint = [
    0, -1, -1, -1, -1, -1, -1, -8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
];

private static immutable byte[] doubleOverflowMidpoint = [
    -1, -1, -1, -1, -1, -1, -1, -8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0
];

private static immutable byte[] aboveDoubleRange = [
    54, 72, 80, 98, -31, 13, 74, -83, 53, 71, 106, 122, -29, -35, 108, 28, 58, -78, 93, -31,
    -29, 13, 114, -113, -75, 93, 89, 61, 46, -123, -40, 18, 79, -4, 121, 94, -2, 50, -26,
    -36, -8, 122, -121, 95, 24, -71, -47, 115, -6, -95, 74, -85, -72, 113, -97, 121, -97, -22,
    67, 65, 59, 22, 68, -71, -58, -2, -21, -109, -13, -19, -36, -24, 57, -64, 104, 25, -34, 96,
    89, -93, -72, -15, -53, 107, 3, 109, -101, -98, 23, -71, 91, 2, -45, 22, -124, -41, 56,
    -71, -2, -78, 92, 114, 35, 115, -125, 61, 67, 39, 112, -107, 1, -7, -33, 108, -8, -52, 64,
    104, -36, 64, -83, 107, -53, -8, 11, 75, -89, 74, 31, -83, 71, -36, -65, 31, 7
];

private static immutable byte[] doubleHighestPowerOfTwo = [
    -128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0
];

@("BigIntegerConvertTest.testDoubleValueZero")
unittest
{
    auto value = new BigInteger(0, []);
    assert(value.doubleValue() == 0.0);
}

@("BigIntegerConvertTest.testDoubleValuePositive1")
unittest
{
    auto value = new BigInteger(1, [6, 101, 44, -50, 33]);
    assert(value.doubleValue() == 2.7467238945E10);
}

@("BigIntegerConvertTest.testDoubleValuePositive2")
unittest
{
    auto value = new BigInteger(1, [
        2, 16, -1, -15, -112, -38, 104, 5, -42, 70, -64, 80, 50, -16, -61, 76
    ]);
    assert(value.doubleValue() == 2.7467238945723645E36);
}

@("BigIntegerConvertTest.testDoubleValueNegative1")
unittest
{
    auto value = new BigInteger(-1, [6, 101, 44, -50, 33]);
    assert(value.doubleValue() == -2.7467238945E10);
}

@("BigIntegerConvertTest.testDoubleValueNegative2")
unittest
{
    auto value = new BigInteger(-1, [
        2, 16, -1, -15, -112, -38, 104, 5, -42, 70, -64, 80, 50, -16, -61, 76
    ]);
    assert(value.doubleValue() == -2.7467238945723645E36);
}

@("BigIntegerConvertTest.testDoubleValuePosRounded1")
unittest
{
    auto value = new BigInteger(1, [-128, 1, 2, 3, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.doubleValue() == 1.54747264387948E26);
}

@("BigIntegerConvertTest.testDoubleValuePosRounded2")
unittest
{
    auto value = new BigInteger(1, [-128, 1, 2, 3, 4, 5, 36, 23, 1, -3, -5]);
    assert(value.doubleValue() == 1.547472643879479E26);
}

@("BigIntegerConvertTest.testDoubleValuePosNotRounded")
unittest
{
    auto value = new BigInteger(1, [-128, 1, 2, 3, 4, 5, -128, 23, 1, -3, -5]);
    assert(value.doubleValue() == 1.5474726438794828E26);
}

@("BigIntegerConvertTest.testDoubleValueNegRounded1")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, 2, 3, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.doubleValue() == -1.54747264387948E26);
}

@("BigIntegerConvertTest.testDoubleValueNegRounded2")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, 2, 3, 4, 5, 36, 23, 1, -3, -5]);
    assert(value.doubleValue() == -1.547472643879479E26);
}

@("BigIntegerConvertTest.testDoubleValueNegNotRounded")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, 2, 3, 4, 5, -128, 23, 1, -3, -5]);
    assert(value.doubleValue() == -1.5474726438794828E26);
}

@("BigIntegerConvertTest.testDoubleValuePosMaxValue")
unittest
{
    auto value = new BigInteger(1, belowDoubleOverflowMidpoint);
    assert(value.doubleValue() == double.max);
}

@("BigIntegerConvertTest.testDoubleValueNegMaxValue")
unittest
{
    auto value = new BigInteger(-1, belowDoubleOverflowMidpoint);
    assert(value.doubleValue() == -double.max);
}

@("BigIntegerConvertTest.testDoubleValuePositiveInfinity1")
unittest
{
    auto value = new BigInteger(1, doubleOverflowMidpoint);
    assert(value.doubleValue() == double.infinity);
}

@("BigIntegerConvertTest.testDoubleValuePositiveInfinity2")
unittest
{
    auto value = new BigInteger(1, aboveDoubleRange);
    assert(value.doubleValue() == double.infinity);
}

@("BigIntegerConvertTest.testDoubleValueNegativeInfinity1")
unittest
{
    auto value = new BigInteger(-1, aboveDoubleRange);
    assert(value.doubleValue() == -double.infinity);
}

@("BigIntegerConvertTest.testDoubleValueNegativeInfinity2")
unittest
{
    auto value = new BigInteger(-1, doubleOverflowMidpoint);
    assert(value.doubleValue() == -double.infinity);
}

@("BigIntegerConvertTest.testDoubleValuePosMantissaIsZero")
unittest
{
    auto value = new BigInteger(1, doubleHighestPowerOfTwo);
    assert(value.doubleValue() == 8.98846567431158E307);
}

@("BigIntegerConvertTest.testDoubleValueNegMantissaIsZero")
unittest
{
    auto value = new BigInteger(-1, doubleHighestPowerOfTwo);
    assert(value.doubleValue() == -8.98846567431158E307);
}

@("BigIntegerConvertTest.testFloatValueZero")
unittest
{
    auto value = new BigInteger(0, []);
    assert(value.floatValue() == 0.0f);
}

@("BigIntegerConvertTest.testFloatValuePositive1")
unittest
{
    auto value = new BigInteger(1, [1, -93, 29, -26]);
    assert(value.floatValue() == 2.7467238E7f);
}

@("BigIntegerConvertTest.testFloatValuePositive2")
unittest
{
    auto value = new BigInteger(1, [1, 125, 47, 60, 75, 32, -95, -1, 86]);
    assert(value.floatValue() == 2.7467239E19f);
}

@("BigIntegerConvertTest.testFloatValueNegative1")
unittest
{
    auto value = new BigInteger(-1, [1, -93, 29, -26]);
    assert(value.floatValue() == -2.7467238E7f);
}

@("BigIntegerConvertTest.testFloatValueNegative2")
unittest
{
    auto value = new BigInteger(-1, [1, 125, 47, 60, 75, 32, -95, -1, 86]);
    assert(value.floatValue() == -2.7467239E19f);
}

@("BigIntegerConvertTest.testFloatValuePosRounded1")
unittest
{
    auto value = new BigInteger(1, [-128, 1, -1, -4, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == 1.5475195E26f);
}

@("BigIntegerConvertTest.testFloatValuePosRounded2")
unittest
{
    auto value = new BigInteger(1, [-128, 1, 2, -128, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == 1.5474728E26f);
}

@("BigIntegerConvertTest.testFloatValuePosNotRounded")
unittest
{
    auto value = new BigInteger(1, [-128, 1, 2, 3, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == 1.5474726E26f);
}

@("BigIntegerConvertTest.testFloatValueNegRounded1")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, -1, -4, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == -1.5475195E26f);
}

@("BigIntegerConvertTest.testFloatValueNegRounded2")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, 2, -128, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == -1.5474728E26f);
}

@("BigIntegerConvertTest.testFloatValueNegNotRounded")
unittest
{
    auto value = new BigInteger(-1, [-128, 1, 2, 3, 4, 5, 60, 23, 1, -3, -5]);
    assert(value.floatValue() == -1.5474726E26f);
}

@("BigIntegerConvertTest.testFloatValuePosMaxValue")
unittest
{
    auto value = new BigInteger(1, [
        0, -1, -1, -1, 0, -1, -1, -8, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ]);
    assert(value.floatValue() == float.max);
}

@("BigIntegerConvertTest.testFloatValueNegMaxValue")
unittest
{
    auto value = new BigInteger(-1, [
        0, -1, -1, -1, 0, -1, -1, -8, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ]);
    assert(value.floatValue() == -float.max);
}

@("BigIntegerConvertTest.testFloatValuePositiveInfinity1")
unittest
{
    auto value = new BigInteger(1, [
        0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ]);
    assert(value.floatValue() == float.infinity);
}

@("BigIntegerConvertTest.testFloatValuePositiveInfinity2")
unittest
{
    auto value = new BigInteger(1, aboveDoubleRange);
    assert(value.floatValue() == float.infinity);
}

@("BigIntegerConvertTest.testFloatValueNegativeInfinity1")
unittest
{
    auto value = new BigInteger(-1, aboveDoubleRange);
    assert(value.floatValue() == -float.infinity);
}

@("BigIntegerConvertTest.testFloatValueNegativeInfinity2")
unittest
{
    auto value = new BigInteger(-1, [
        0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
    ]);
    assert(value.floatValue() == -float.infinity);
}

@("BigIntegerConvertTest.testFloatValuePosMantissaIsZero")
unittest
{
    auto value = new BigInteger(1, [-128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert(value.floatValue() == 1.7014118E38f);
}

@("BigIntegerConvertTest.testFloatValueNegMantissaIsZero")
unittest
{
    auto value = new BigInteger(-1, [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert(value.floatValue() == -float.infinity);
}

@("BigIntegerConvertTest.testFloatValueBug2482")
unittest
{
    auto value = new BigInteger(1, [-128, 0, 0, 1]);
    assert(value.floatValue() == 2.14748365E9f);
}
