/*
 * Copyright 2002-present the original author or authors.
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
// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans/factory/parsing/
// ProblemReporter.java, SourceExtractor.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.beans.factory.parsing`.
module flint.beans.factory.parsing;

import flint.core.io : Resource;
import flint.engine.aot.any : Any;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.parsing.ProblemReporter sha256:d67eb0cc6ec79ac45f120a80e8eaffd1f0961c5d09ef91c7f01c6f49affdf206
/// SPI interface allowing tools and other external processes to handle errors and warnings reported during bean
/// definition parsing.
interface ProblemReporter
{
    // port:pending org.springframework.beans.factory.parsing.ProblemReporter#error(Problem): type org.springframework.beans.factory.parsing.Problem is not mapped to a D symbol

    // port:pending org.springframework.beans.factory.parsing.ProblemReporter#fatal(Problem): type org.springframework.beans.factory.parsing.Problem is not mapped to a D symbol

    // port:pending org.springframework.beans.factory.parsing.ProblemReporter#warning(Problem): type org.springframework.beans.factory.parsing.Problem is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.parsing.SourceExtractor sha256:668d0087ea9269659da917b260406f779421a0c3b6245688dff6a1498052664e
/// Simple strategy allowing tools to control how source metadata is attached to the bean definition metadata.
/// Configuration parsers may provide the ability to attach source metadata during the parse phase. They will offer this
/// metadata in a generic format which can be further modified by a `SourceExtractor` before being attached to the bean
/// definition metadata.
interface SourceExtractor
{
    /// Extract the source metadata from the candidate object supplied by the configuration parser.
    Any extractSource(Any sourceCandidate, Resource definingResource);
}
// port:end
