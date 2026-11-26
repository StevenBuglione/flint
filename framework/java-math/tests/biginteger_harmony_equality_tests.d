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
module biginteger_harmony_equality_tests;

import flint.java.math.biginteger : BigInteger;

@safe:

private static immutable byte[] magnitude = [
    12, 56, 100, -2, -76, 89, 45, 91, 3, -15, 35, 26, 3, 91
];

@("testEqualsObject") unittest
{
    const value = new BigInteger(1, magnitude);
    assert(!value.equals(new Object()));
}

@("testEqualsNull") unittest
{
    const value = new BigInteger(1, magnitude);
    assert(!value.equals(null));
}

@("testEqualsBigIntegerTrue") unittest
{
    const value = new BigInteger(1, magnitude);
    Object equal = new BigInteger(1, magnitude);
    assert(value.equals(equal));
}

@("testEqualsBigIntegerFalse") unittest
{
    const value = new BigInteger(1, magnitude);
    Object smaller = new BigInteger(1, magnitude[6 .. $]);
    assert(!value.equals(smaller));
}
