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
 *
 * Ported from spring-framework v7.1.0:
 * spring-expression/src/main/java/org/springframework/expression/spel/support/StandardEvaluationContext.java
 * Modified by the Flint authors.
 */
module flint.expression.spel.context;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable;
import flint.expression : EvaluationContext, TypedValue;

@safe:

// Lets the parser link without the concrete context and its mutable startup state.
package(flint.expression) interface EvaluationContextAccess : EvaluationContext
{
    bool isStandardContext() nothrow @nogc;
    TypedValue readRootObject() nothrow @nogc;
    Any readVariable(string name) nothrow @nogc;
    const(DescriptorTable) descriptorTable() const nothrow @nogc;
}
