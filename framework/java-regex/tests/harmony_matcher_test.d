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
 * Ported from harmony 6.0M3, classlib/modules/regex/src/test/java/org/apache/harmony/tests/java/util/regex/MatcherTest.java
 * Modified by the Flint authors.
 */
module flint.java.util.regex.harmony_matcher_test;

import flint.java.util.regex.pattern : Pattern;

@safe:

@("MatcherTest.testPattern")
unittest
{
    foreach (expression; [
        "(a|b)*abb", "(1*2*3*4*)*567", "(a|b|c|d)*aab", "(1|2|3|4|5|6|7|8|9|0)(1|2|3|4|5|6|7|8|9|0)*",
        "(abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ)*", "(a|b)*(a|b)*A(a|b)*lice.*",
        "(a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z)(a|b|c|d|e|f|g|h|"
        ~ "i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z)*(1|2|3|4|5|6|7|8|9|0)*|while|for|struct|if|do"
    ])
    {
        auto compiled = Pattern.compile(expression);
        assert(compiled.matcher("aaa").pattern() is compiled);
        assert(Pattern.compile(expression).matcher("aaa").pattern().toString() == expression);
    }
}

@("MatcherTest.testGroupCount")
unittest
{
    foreach (i, expression; [
        "(a|b)*aabb", "((a)|b)*aabb", "((a|b)*)a(abb)", "(((a)|(b))*)aabb", "(((a)|(b))*)aa(b)b",
        "(((a)|(b))*)a(a(b)b)"
    ])
    {
        auto matcher = Pattern.compile(expression).matcher("ababababbaaabb");
        matcher.matches();
        assert(matcher.groupCount() == i + 1);
    }
}
