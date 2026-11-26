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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/template/{NoOpTemplateRenderer,TemplateRenderer,ValidationMode}.java
// Modified by the Flint authors.
module flint.ai.template_;

import flint.engine.aot.any : Any;
import flint.java.util : Map;
import flint.java.util.function_ : BiFunction;

@safe:

private alias Variables = Map!(string, Any);

/// Controls how a renderer handles missing template variables.
enum ValidationMode
{
    /// Throws a validation exception. This is the default mode.
    THROW,
    /// Logs a warning and renders with the missing variables.
    WARN,
    /// Skips validation.
    NONE
}

/// Renders a template with the given variables.
interface TemplateRenderer : BiFunction!(string, Variables, string)
{
    /// Applies the renderer to the template and its variables.
    override string apply(string template_, Variables variables);
}

/// Validates the input and returns the template unchanged.
class NoOpTemplateRenderer : TemplateRenderer
{
    /// Returns the original text after validating the template and variable names.
    override string apply(string template_, Variables variables)
    {
        import flint.java.lang : IllegalArgumentException;
        import flint.util : StringUtils;

        if (!StringUtils.hasText(template_))
            throw new IllegalArgumentException("template cannot be null or empty");
        if (variables is null)
            throw new IllegalArgumentException("variables cannot be null");
        variables.forEach((string key, Any) {
            if (key is null)
                throw new IllegalArgumentException("variables keys cannot be null");
        });
        return template_;
    }
}
