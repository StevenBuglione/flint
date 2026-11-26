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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerToStringTest.java
 *  Modified by the Flint authors.
 */
module biginteger_harmony_format_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

@("BigIntegerToStringTest.testRadixOutOfRange")
unittest
{
    auto value = new BigInteger(1, [6, 35, -45, 11, -123, -74, -110, -79]);
    assert(value.toString(45) == "442429234853876401");
}

@("BigIntegerToStringTest.testRadix2Neg")
unittest
{
    auto value = new BigInteger(-1, [
        5, 49, 34, 85, -62, -84, 82, -86, -86, -86, -86, -86, -107
    ]);
    enum expected = "-101001100010010001001010101110000101010110001010010"
        ~ "101010101010101010101010101010101010101010010101";
    assert(value.toString(2) == expected);
}

@("BigIntegerToStringTest.testRadix2Pos")
unittest
{
    auto value = new BigInteger(1, [80, -8, 26, -86, -86, 37, 85, 82, -86, -95, 18]);
    assert(value.toString(
            2) == "101000011111000000110101010101010101010001001010101010101010010101010101010000100010010");
}

@("BigIntegerToStringTest.testRadix10Neg")
unittest
{
    auto value = new BigInteger(-1, [
        2, 72, -105, 86, 48, -123, 114, 54, 71, -119, -121, -125, -108, -121, 41, -124
    ]);
    assert(value.toString(16) == "-2489756308572364789878394872984");
}

@("BigIntegerToStringTest.testRadix10Pos")
unittest
{
    auto value = new BigInteger(1, [
        35, -121, 98, 120, -110, 52, 117, 103, 57, -121, 54, 71, 52, 118
    ]);
    assert(value.toString(16) == "2387627892347567398736473476");
}

@("BigIntegerToStringTest.testRadix16Neg")
unittest
{
    auto value = new BigInteger(-1, [
        2, -121, 98, -118, -120, 52, 81, -72, 0, -122, 92, 103, -24, -41, -1, 32
    ]);
    assert(value.toString(16) == "-287628a883451b800865c67e8d7ff20");
}

@("BigIntegerToStringTest.testRadix16Pos")
unittest
{
    auto value = new BigInteger(1, [
        2, -121, 98, -118, -120, 52, 81, -72, 0, -122, 92, 103, -24, -41, -1, 32
    ]);
    assert(value.toString(16) == "287628a883451b800865c67e8d7ff20");
}

@("BigIntegerToStringTest.testRadix24Neg")
unittest
{
    auto value = new BigInteger(-1, [
        78, 47, 50, -64, -54, 37, 82, 80, 107, 100, 41, -23, 93, 73, -45, -111, 86, 75, -78, 59, -16
    ]);
    assert(value.toString(24) == "-287628a88gmn3451b8ijk00865c67e8d7ff20");
}

@("BigIntegerToStringTest.testRadix24Pos")
unittest
{
    auto value = new BigInteger(1, [
        3, 65, -9, 114, -77, 14, -20, 100, 101, 84, 64, 127, -37, -62, 28, 17, 86, 75, -78, 59, -16
    ]);
    assert(value.toString(24) == "287628a883451bg80ijhk0865c67e8d7ff20");
}

@("BigIntegerToStringTest.testRadix36Neg")
unittest
{
    auto value = new BigInteger(-1, [
        1, -104, -112, 12, 70, -48, -51, 80, 23, 68, 78, 45, -114, -95, -32, 127, -8, 1, 92,
        -103, 68, -41, -48, 0, -31, 21, -121, 63, 14, 119, 30, 81, -105, -93, 9, 9, 97, -27, 29,
        1, 27, 127, -53, 55, 43, 75, -109, 78, -36, -80
    ]);
    assert(value.toString(36) == "-uhguweut98iu4h3478tq3985pq98yeiuth33485yq4aiuhalai485yiaehasdkr8tywi5uhslei8");
}

@("BigIntegerToStringTest.testRadix36Pos")
unittest
{
    auto value = new BigInteger(1, [
        100, -17, -96, -128, -9, -6, -66, 106, -16, 40, 51, 84, 103, 10, -66, 71, -62, -52,
        76, -48, -43, 96, -11, -27, -91, 17, -98, 126, -92, -21, 29, 5, 109, -27, 40, -18,
        -117, 11, 21, -93, -103, 66, 114, 55, -36, -11, 43, -120, 37, 24, -44, 78
    ]);
    assert(value.toString(36) == "23895lt45y6vhgliuwhgi45y845htsuerhsi4586ysuerhtsio5y68peruhgsil4568ypeorihtse48y6");
}
