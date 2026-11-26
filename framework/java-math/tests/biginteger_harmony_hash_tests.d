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
 *  Ported from harmony 6.0M3, classlib/modules/math/src/test/java/org/apache/harmony/tests/java/math/BigIntegerHashCodeTest.java
 *  Modified by the Flint authors.
 */
module biginteger_harmony_hash_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

private static immutable byte[] first = [
    -114, 24, 101, -45, 99, 20, 71, -67, 9, -41, 62, -27, -28, -102, 121, -6, -38, 1
];
private static immutable byte[] second = [
    -27, -53, -110, -70, 7, 9, -22, -47, 106, 103, 38, 127, -50, -78, 114, 77, 51, 113, -101,
    58, 121, -6, -38, 1
];

@("testEqualObjects") unittest
{
    const value = new BigInteger(1, first);
    const equal = new BigInteger(1, first);
    assert(value.equals(equal));
    assert(value.hashCode() == equal.hashCode());
}

@("testUnequalObjectsUnequal") unittest
{
    const value = new BigInteger(1, first);
    const other = new BigInteger(-1, second);
    assert(!value.equals(other));
    assert(value.hashCode() != other.hashCode());
}
