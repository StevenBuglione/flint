// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
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
 * Modified by the Flint authors: ported from spring-framework v7.1.0,
 * spring-beans/src/main/java/org/springframework/beans/{BeansException,FatalBeanException,
 * BeanInstantiationException}.java.
 */

/++
`org.springframework.beans`: the root of the bean exception hierarchy.
+/
module flint.beans;

import flint.core : NestedRuntimeException;

@safe:

/// Abstract superclass for all exceptions thrown in the beans package and subpackages.
abstract class BeansException : NestedRuntimeException
{
    /// `msg`, with a cause that can still be initialized (Java's `(String)` constructor).
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(msg, file: file, line: line);
    }

    /// `msg` and an initialized `cause`, even `null` (Java's `(String, Throwable)` constructor).
    this(string msg, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(msg, cause, file, line);
    }

    /// Selects the cause overload for a `null` literal, as Java's overload resolution does.
    this(string msg, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(msg, cast(Throwable) null, file, line);
    }
}

/// Thrown on an unrecoverable problem encountered in the beans packages or sub-packages.
class FatalBeanException : BeansException
{
    /// `msg`, with a cause that can still be initialized (Java's `(String)` constructor).
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(msg, file: file, line: line);
    }

    /// `msg` and an initialized `cause`, even `null` (Java's `(String, Throwable)` constructor).
    this(string msg, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(msg, cause, file, line);
    }

    /// Selects the cause overload for a `null` literal, as Java's overload resolution does.
    this(string msg, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(msg, cast(Throwable) null, file, line);
    }
}

/// Thrown when instantiation of a bean failed.
class BeanInstantiationException : FatalBeanException
{
    private string beanClass;

    /// `Failed to instantiate [beanClass]: msg`, with a cause that can still be initialized.
    this(string beanClass, string msg) pure nothrow
    {
        super("Failed to instantiate [" ~ beanClass ~ "]: " ~ msg);
        this.beanClass = beanClass;
    }

    /// `Failed to instantiate [beanClass]: msg` and an initialized `cause`.
    this(string beanClass, string msg, Throwable cause) pure nothrow
    {
        super("Failed to instantiate [" ~ beanClass ~ "]: " ~ msg, cause);
        this.beanClass = beanClass;
    }

    /// The canonical name of the class that failed to instantiate.
    string getBeanClass() const pure nothrow @nogc
    {
        return beanClass;
    }
}
