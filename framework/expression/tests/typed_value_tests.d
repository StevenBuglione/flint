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
 * spring-expression/src/main/java/org/springframework/expression/TypedValue.java
 * Also from spel/support/StandardEvaluationContext.java.
 * Modified by the Flint authors.
 */
module flint.expression.typed_value_tests;

import flint.core.convert : TypeDescriptor;
import flint.engine.aot.any : Any;
import flint.expression : TypedValue;
import flint.expression.spel.support : StandardEvaluationContext;

@safe:

@("TypedValue derives a descriptor from the wrapped value") unittest
{
    auto value = TypedValue(Any.of(34));
    auto descriptor = value.getTypeDescriptor();
    assert(descriptor.getType() == "int");
    assert(value.getTypeDescriptor() is descriptor);
    assert(TypedValue.NULL.getTypeDescriptor() is null);
    auto typedNull = TypedValue(Any.of(cast(Object) null));
    assert(typedNull.getTypeDescriptor() is null);
}

@("a context root keeps its explicit type even when its value is null")
unittest
{
    auto context = new StandardEvaluationContext;
    auto descriptor = TypeDescriptor.valueOf!string;
    context.setRootObject(Any.init, descriptor);
    auto explicitRoot = context.getRootObject();
    assert(explicitRoot.getValue().isNull());
    assert(explicitRoot.getTypeDescriptor() is descriptor);

    context.setRootObject(Any.of(17));
    auto literalRoot = context.getRootObject();
    assert(literalRoot.getValue().get!int == 17);
    assert(literalRoot.getTypeDescriptor().getType() == "int");
    assert(explicitRoot.getTypeDescriptor() is descriptor);
}
