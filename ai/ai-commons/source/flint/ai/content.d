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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/content/Content.java
// Modified by the Flint authors.
module flint.ai.content;

import flint.engine.aot.any : Any;
import flint.java.util : Map;
import std.typecons : Nullable;

@safe:

/// Text and metadata shared by chat messages and media-bearing content.
interface Content
{
    /// Returns the text when available. Empty text is a present value.
    Nullable!string getText();

    /// Returns the metadata associated with the content.
    Map!(string, Any) getMetadata();
}
