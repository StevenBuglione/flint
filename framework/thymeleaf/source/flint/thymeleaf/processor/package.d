/*
 * Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/processor/IProcessor.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/processor/AbstractProcessor.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.processor;

import flint.thymeleaf.templatemode : TemplateMode;

@safe:

/// Common metadata exposed by all processors in a Thymeleaf dialect.
interface IProcessor
{
    /// The template mode supported by this processor.
    TemplateMode getTemplateMode();

    /// The processor's ordering precedence in its dialect.
    int getPrecedence();
}

/// A processor with fixed template mode and precedence.
abstract class AbstractProcessor : IProcessor
{
    private immutable TemplateMode templateMode;
    private immutable int precedence;

    /// Retains the supplied mode and precedence (R5, R15).
    this(TemplateMode templateMode, int precedence) nothrow @nogc
    {
        this.templateMode = templateMode;
        this.precedence = precedence;
    }

    /// The template mode supported by this processor.
    final override TemplateMode getTemplateMode() nothrow @nogc
    {
        return templateMode;
    }

    /// The processor's ordering precedence in its dialect.
    final override int getPrecedence() nothrow @nogc
    {
        return precedence;
    }
}
