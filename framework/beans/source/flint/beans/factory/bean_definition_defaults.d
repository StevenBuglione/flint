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
 * Ported from spring-framework v7.1.0,
 * spring-beans/src/main/java/org/springframework/beans/factory/support/BeanDefinitionDefaults.java.
 * Modified by the Flint authors.
 */
module flint.beans.factory.bean_definition_defaults;

import flint.util : StringUtils;
import std.typecons : Nullable;

@safe:

/// Default values for bean definition properties.
class BeanDefinitionDefaults
{
    private Nullable!bool lazyInit;
    private int autowireMode;
    private int dependencyCheck;
    private Nullable!string initMethodName;
    private Nullable!string destroyMethodName;

    /// Records whether singleton beans should be initialized lazily by default.
    void setLazyInit(bool value) pure nothrow @nogc
    {
        lazyInit = value;
    }

    /// Whether lazy initialization was enabled explicitly.
    bool isLazyInit() const pure nothrow @nogc
    {
        return !lazyInit.isNull && lazyInit.get();
    }

    /// The lazy initialization flag, if explicitly set.
    Nullable!bool getLazyInit() const pure nothrow @nogc
    {
        return lazyInit;
    }

    /// Sets the default autowire mode.
    void setAutowireMode(int mode) pure nothrow @nogc
    {
        autowireMode = mode;
    }

    /// The default autowire mode, initially AUTOWIRE_NO.
    int getAutowireMode() const pure nothrow @nogc
    {
        return autowireMode;
    }

    /// Sets the default dependency check code.
    void setDependencyCheck(int code) pure nothrow @nogc
    {
        dependencyCheck = code;
    }

    /// The default dependency check, initially DEPENDENCY_CHECK_NONE.
    int getDependencyCheck() const pure nothrow @nogc
    {
        return dependencyCheck;
    }

    /// Sets the optional default initialization callback name.
    void setInitMethodName(Nullable!string name) pure nothrow @nogc
    {
        initMethodName = callbackName(name);
    }

    /// The default initialization callback name, if present.
    Nullable!string getInitMethodName() const pure nothrow @nogc
    {
        return initMethodName;
    }

    /// Sets the optional default destruction callback name.
    void setDestroyMethodName(Nullable!string name) pure nothrow @nogc
    {
        destroyMethodName = callbackName(name);
    }

    /// The default destruction callback name, if present.
    Nullable!string getDestroyMethodName() const pure nothrow @nogc
    {
        return destroyMethodName;
    }
}

private Nullable!string callbackName(Nullable!string name) pure nothrow @nogc
{
    return !name.isNull && StringUtils.hasText(name.get()) ? name : Nullable!string.init;
}
