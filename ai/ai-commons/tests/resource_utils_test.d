/*
 * Copyright 2023-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Flint's own tests for the ported org.springframework.ai.util.ResourceUtils.
module resource_utils_test;

import flint.ai.util : ResourceUtils;
import std.exception : assertThrown;

@safe:

private string writeTempFile(string name, string content)
{
    import std.file : exists, mkdirRecurse, tempDir, write;
    import std.path : buildPath;

    const dir = buildPath(tempDir(), "flint-ai-resource-utils-tests");
    if (!exists(dir))
        mkdirRecurse(dir);
    const path = buildPath(dir, name);
    write(path, content);
    return path;
}

@("reads a file URI as UTF-8 text")
unittest
{
    const path = writeTempFile("file-uri.txt", "Read through a file URI");

    assert(ResourceUtils.getText("file:" ~ path) == "Read through a file URI");
}

@("decodes multibyte UTF-8 without loss")
unittest
{
    const path = writeTempFile("utf8.txt", "héllo wörld \u4F60\u597D");

    assert(ResourceUtils.getText("file:" ~ path) == "héllo wörld \u4F60\u597D");
}

@("an empty resource yields the empty string")
unittest
{
    const path = writeTempFile("empty.txt", "");

    assert(ResourceUtils.getText("file:" ~ path) == "");
}

@("a missing file URI propagates the read failure")
unittest
{
    import std.path : buildPath, dirName;

    const existing = writeTempFile("missing-parent-marker.txt", "x");
    const missing = buildPath(dirName(existing), "does-not-exist.txt");

    assertThrown!Exception(ResourceUtils.getText("file:" ~ missing));
}
