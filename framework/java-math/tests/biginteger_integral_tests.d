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
module biginteger_integral_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("BigIntegerConvertTest.testIntValuePositive1")
unittest
{
    auto value = new BigInteger([12, 56, 100, -2, -76, 89, 45, 91, 3]);
    assert(value.intValue() == 1_496_144_643);
}

@("BigIntegerConvertTest.testIntValuePositive2")
unittest
{
    auto value = new BigInteger([12, 56, 100]);
    assert(value.intValue() == 800_868);
}

@("BigIntegerConvertTest.testIntValuePositive3")
unittest
{
    auto value = new BigInteger(1, [56, 13, 78, -12, -5, 56, 100]);
    assert(value.intValue() == -184_862_620);
}

@("BigIntegerConvertTest.testIntValueNegative1")
unittest
{
    auto value = new BigInteger(-1, [12, 56, 100, -2, -76, -128, 45, 91, 3]);
    assert(value.intValue() == 2_144_511_229);
}

@("BigIntegerConvertTest.testIntValueNegative2")
unittest
{
    auto value = new BigInteger([-12, 56, 100]);
    assert(value.intValue() == -771_996);
}

@("BigIntegerConvertTest.testIntValueNegative3")
unittest
{
    auto value = new BigInteger(-1, [12, 56, 100, -2, -76, 127, 45, 91, 3]);
    assert(value.intValue() == -2_133_678_851);
}

@("BigIntegerConvertTest.testLongValuePositive1")
unittest
{
    auto value = new BigInteger([12, 56, 100, -2, -76, 89, 45, 91, 3, 120, -34, -12, 45, 98]);
    assert(value.longValue() == 3_268_209_772_258_930_018L);
}

@("BigIntegerConvertTest.testLongValuePositive2")
unittest
{
    auto value = new BigInteger([12, 56, 100, 18, -105, 34, -18, 45]);
    assert(value.longValue() == 880_563_758_158_769_709L);
}

@("BigIntegerConvertTest.testLongValueNegative1")
unittest
{
    auto value = new BigInteger([12, -1, 100, -2, -76, -128, 45, 91, 3]);
    assert(value.longValue() == -43_630_045_168_837_885L);
}

@("BigIntegerConvertTest.testLongValueNegative2")
unittest
{
    auto value = new BigInteger([-12, 56, 100, 45, -101, 45, 98]);
    assert(value.longValue() == -3_315_696_807_498_398L);
}

@("BigIntegerConvertTest.testValueOfIntegerMax")
unittest
{
    auto value = BigInteger.valueOf(int.max);
    assert(value.toByteArray() == [127, -1, -1, -1]);
    assert(value.signum() == 1);
}

@("BigIntegerConvertTest.testValueOfIntegerMin")
unittest
{
    auto value = BigInteger.valueOf(int.min);
    assert(value.toByteArray() == [-128, 0, 0, 0]);
    assert(value.signum() == -1);
}

@("BigIntegerConvertTest.testValueOfLongMax")
unittest
{
    auto value = BigInteger.valueOf(long.max);
    assert(value.toByteArray() == [127, -1, -1, -1, -1, -1, -1, -1]);
    assert(value.signum() == 1);
}

@("BigIntegerConvertTest.testValueOfLongMin")
unittest
{
    auto value = BigInteger.valueOf(long.min);
    assert(value.toByteArray() == [-128, 0, 0, 0, 0, 0, 0, 0]);
    assert(value.signum() == -1);
}

@("BigIntegerConvertTest.testValueOfLongPositive1")
unittest
{
    auto value = BigInteger.valueOf(268_209_772_258_930_018L);
    assert(value.toByteArray() == [3, -72, -33, 93, -24, -56, 45, 98]);
    assert(value.signum() == 1);
}

@("BigIntegerConvertTest.testValueOfLongPositive2")
unittest
{
    auto value = BigInteger.valueOf(58_930_018L);
    assert(value.toByteArray() == [3, -125, 51, 98]);
    assert(value.signum() == 1);
}

@("BigIntegerConvertTest.testValueOfLongNegative1")
unittest
{
    auto value = BigInteger.valueOf(-268_209_772_258_930_018L);
    assert(value.toByteArray() == [-4, 71, 32, -94, 23, 55, -46, -98]);
    assert(value.signum() == -1);
}

@("BigIntegerConvertTest.testValueOfLongNegative2")
unittest
{
    auto value = BigInteger.valueOf(-58_930_018L);
    assert(value.toByteArray() == [-4, 124, -52, -98]);
    assert(value.signum() == -1);
}

@("BigIntegerConvertTest.testValueOfLongZero")
unittest
{
    auto value = BigInteger.valueOf(0L);
    assert(value.toByteArray() == [0]);
    assert(value.signum() == 0);
}
