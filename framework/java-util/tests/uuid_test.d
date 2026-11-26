/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.

 *
 * Ported from harmony 6.0M3, classlib/modules/luni/src/test/api/common/org/apache/harmony/luni/tests/java/util/UUIDTest.java
 * Modified by the Flint authors.
 */
module uuid_test;

import flint.java.util.uuid : UUID;

@safe:

@("UUIDTest.test_getLeastSignificantBits")
unittest
{
    foreach (bits; [0L, long.min, long.max])
        assert((new UUID(0, bits)).getLeastSignificantBits() == bits);
}

@("UUIDTest.test_getMostSignificantBits")
unittest
{
    foreach (bits; [0L, long.min, long.max])
        assert((new UUID(bits, 0)).getMostSignificantBits() == bits);
}

@("UUIDTest.test_version")
unittest
{
    foreach (versionBits; 0 .. 6)
        assert((new UUID(cast(long) versionBits << 12, 0)).version_() == versionBits);
}

@("UUIDTest.test_variant")
unittest
{
    foreach (topNibble; [0, 7, 3, 1, 8, 11, 10, 9, 12, 13, 14, 15])
    {
        const expected = topNibble < 8 ? 0 : topNibble < 12 ? 2 : topNibble >> 1;
        assert((new UUID(0, cast(long)(cast(ulong) topNibble << 60))).variant() == expected);
    }
}

@("UUIDTest.test_toString")
unittest
{
    assert((new UUID(cast(long) 0xf81d4fae7dec11d0UL, cast(long) 0xa76500a0c91e6bf6UL))
            .toString() == "f81d4fae-7dec-11d0-a765-00a0c91e6bf6");
    assert((new UUID(0x1000, long.min)).toString() == "00000000-0000-1000-8000-000000000000");
}

@("UUIDTest.test_randomUUID")
unittest
{
    auto id = UUID.randomUUID();
    assert(id.variant() == 2);
    assert(id.version_() == 4);
}

@("Generated UUIDs use lowercase hex and the standard v4 layout")
unittest
{
    string previous;
    foreach (i; 0 .. 32)
    {
        const text = UUID.randomUUID().toString();
        assert(text.length == 36);
        foreach (position, ch; text)
        {
            if (position == 8 || position == 13 || position == 18 || position == 23)
                assert(ch == '-');
            else
                assert((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'));
        }
        assert(text[14] == '4');
        assert(text[19] == '8' || text[19] == '9' || text[19] == 'a' || text[19] == 'b');
        assert(previous != text);
        previous = text;
    }
}
