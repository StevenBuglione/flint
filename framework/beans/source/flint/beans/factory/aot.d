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
// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans/factory/aot/
// AotBeanProcessingException.java, AotException.java, AotProcessingException.java, AutowiredArguments.java,
// BeanDefinitionPropertyValueCodeGeneratorDelegates.java, BeanFactoryInitializationAotContribution.java,
// BeanFactoryInitializationAotProcessor.java, BeanFactoryInitializationCode.java,
// BeanRegistrationAotContribution.java, BeanRegistrationAotProcessor.java, BeanRegistrationCode.java,
// BeanRegistrationCodeFragments.java, BeanRegistrationCodeFragmentsDecorator.java,
// BeanRegistrationExcludeFilter.java, BeanRegistrationsCode.java, CodeWarnings.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.beans.factory.aot`.
module flint.beans.factory.aot;

import flint.beans.factory.config : ConfigurableListableBeanFactory;
import flint.beans.factory.support : RootBeanDefinition;
import flint.java.lang : RuntimeException;
import flint.java.util : List;
import flint.java.util : Set;
import flint.engine.aot.any : Any;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.AotBeanProcessingException sha256:1eb0eae1ab4dca8d0b997b2bd7b6b3fa9af20ade2bcf202c4fd535aaa4886171
/// Thrown when AOT fails to process a bean.
class AotBeanProcessingException : AotProcessingException
{
    private RootBeanDefinition beanDefinition;

    /// Return the bean definition of the bean that failed to be processed.
    RootBeanDefinition getBeanDefinition()
    {
        return this.beanDefinition;
    }

    // port:pending org.springframework.beans.factory.aot.AotBeanProcessingException#<init>(RegisteredBean,String): type org.springframework.beans.factory.support.RegisteredBean is not mapped to a D symbol

    // port:pending org.springframework.beans.factory.aot.AotBeanProcessingException#<init>(RegisteredBean,String,Throwable): type org.springframework.beans.factory.support.RegisteredBean is not mapped to a D symbol

    // port:pending org.springframework.beans.factory.aot.AotBeanProcessingException#createErrorMessage(RegisteredBean,String): type org.springframework.beans.factory.support.RegisteredBean is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.AotException sha256:a5466a7d2aab95438df9e1972332de0a94d155fdf9973a62400408197c8cad34
/// Abstract superclass for all exceptions thrown by ahead-of-time processing.
abstract class AotException : RuntimeException
{
    // port:pending org.springframework.beans.factory.aot.AotException#<init>(String,Throwable): type java.lang.Throwable is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.AotProcessingException sha256:05a957c5710e08c7596bdc5e8529900074ca26671baa4490db595f5f14216293
/// Throw when an AOT processor failed.
class AotProcessingException : AotException
{
    // port:pending org.springframework.beans.factory.aot.AotProcessingException#<init>(String,Throwable): type java.lang.Throwable is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.AutowiredArguments sha256:b0946c12c5442c10428aae05017347730982eadd655138a3e93632606b09559b
/// Resolved arguments to be autowired.
interface AutowiredArguments
{
    /// Return the arguments as an object array.
    Any[] toArray();

    // port:pending org.springframework.beans.factory.aot.AutowiredArguments#get(int): a generic method

    // port:pending org.springframework.beans.factory.aot.AutowiredArguments#get(int,Class): a generic method

    // port:pending org.springframework.beans.factory.aot.AutowiredArguments#getObject(int): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.AutowiredArguments#of(Object): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates sha256:616b03462104df754d48d2258026fdfdef4ec39f31f0f6ca99309dd7c86880c3
/// Code generator `Delegate` for common bean definition property values.
abstract class BeanDefinitionPropertyValueCodeGeneratorDelegates
{
    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates#INSTANCES: a constant whose initializer is not a literal

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates#createValueCodeGenerator(GeneratedMethods,List): type org.springframework.aot.generate.ValueCodeGenerator is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.AutowiredPropertyMarkerDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.BeanReferenceDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.LinkedHashMapDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.ManagedListDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.ManagedMapDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.ManagedSetDelegate: a nested class (R13)

    // port:pending org.springframework.beans.factory.aot.BeanDefinitionPropertyValueCodeGeneratorDelegates.TypedStringValueDelegate: a nested class (R13)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanFactoryInitializationAotContribution sha256:e2d506a1a8e53065160faec56e5dd71a6db8b7c98bed7e0e1a0d274d06b55b9d
/// AOT contribution from a `BeanFactoryInitializationAotProcessor` used to initialize a bean factory. Note: Beans
/// implementing this interface will not have registration methods generated during AOT processing unless they also
/// implement `org.springframework.beans.factory.aot.BeanRegistrationExcludeFilter`.
interface BeanFactoryInitializationAotContribution
{
    // port:pending org.springframework.beans.factory.aot.BeanFactoryInitializationAotContribution#applyTo(GenerationContext,BeanFactoryInitializationCode): type org.springframework.aot.generate.GenerationContext is excluded (runtime-reflection)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanFactoryInitializationAotProcessor sha256:7e2f769f15ece43da37bb5b7cd430301310b75d764e344e17d706fc60905213e
/// AOT processor that makes bean factory initialization contributions by processing `ConfigurableListableBeanFactory`
/// instances. `BeanFactoryInitializationAotProcessor` implementations may be registered in a
/// `AotServices#FACTORIES_RESOURCE_LOCATION` resource or as a bean. Using this interface on a registered bean will
/// cause the bean and all of its dependencies to be initialized during AOT processing. We generally recommend that this
/// interface is only used with infrastructure beans such as `BeanFactoryPostProcessor` which have limited dependencies
/// and are already initialized early in the bean factory lifecycle. If such a bean is registered using a factory
/// method, make sure to make it `static` so that its enclosing class does not have to be initialized. A component that
/// implements this interface is not contributed.
interface BeanFactoryInitializationAotProcessor
{
    /// Process the given `ConfigurableListableBeanFactory` instance ahead-of-time and return a contribution or `null`.
    /// Processors are free to use any techniques they like to analyze the given bean factory. Most typically use
    /// reflection to find fields or methods to use in the contribution. Contributions typically generate source code or
    /// resource files that can be used when the AOT optimized application runs. If the given bean factory does not
    /// contain anything that is relevant to the processor, this method should return a `null` contribution.
    BeanFactoryInitializationAotContribution processAheadOfTime(ConfigurableListableBeanFactory beanFactory);
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanFactoryInitializationCode sha256:f002aab03d7b710c8adeb85cddee3a4f1c8b491aa52176ab41a2f06775c20b41
/// Interface that can be used to configure the code that will be generated to perform bean factory initialization.
interface BeanFactoryInitializationCode
{
    /// The recommended variable name to use to refer to the bean factory.
    enum string BEAN_FACTORY_VARIABLE = "beanFactory";

    // port:pending org.springframework.beans.factory.aot.BeanFactoryInitializationCode#addInitializer(MethodReference): type org.springframework.aot.generate.MethodReference is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.BeanFactoryInitializationCode#getClassName(): type ClassName does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanFactoryInitializationCode#getMethods(): type org.springframework.aot.generate.GeneratedMethods is excluded (runtime-reflection)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationAotContribution sha256:8285bff1a16c67dfbfb4288130550987356f84f4d35432d31874c04245bb6223
/// AOT contribution from a `BeanRegistrationAotProcessor` used to register a single bean definition.
interface BeanRegistrationAotContribution
{
    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotContribution#applyTo(GenerationContext,BeanRegistrationCode): type org.springframework.aot.generate.GenerationContext is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotContribution#concat(BeanRegistrationAotContribution,BeanRegistrationAotContribution): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotContribution#customizeBeanRegistrationCodeFragments(GenerationContext,BeanRegistrationCodeFragments): type org.springframework.aot.generate.GenerationContext is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotContribution#withCustomCodeFragments(UnaryOperator): generic type UnaryOperator<...>
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationAotProcessor sha256:567aa6d237cd916e2980abb33a02cd217494ee021a82bed286251a1e31e2c7e1
/// AOT processor that makes bean registration contributions by processing `RegisteredBean` instances.
/// `BeanRegistrationAotProcessor` implementations may be registered in a `AotServices#FACTORIES_RESOURCE_LOCATION`
/// resource or as a bean. Using this interface on a registered bean will cause the bean and all of its dependencies to
/// be initialized during AOT processing. We generally recommend that this interface is only used with infrastructure
/// beans such as `BeanPostProcessor` which have limited dependencies and are already initialized early in the bean
/// factory lifecycle. If such a bean is registered using a factory method, make sure to make it `static` so that its
/// enclosing class does not have to be initialized. An AOT processor replaces its usual runtime behavior by an
/// optimized arrangement, usually in generated code. For that reason, a component that implements this interface is not
/// contributed by default. If a component that implements this interface still needs to be invoked at runtime,
/// `isBeanExcludedFromAotProcessing` can be overridden.
interface BeanRegistrationAotProcessor
{
    /// The name of an attribute that can be `set` on a `org.springframework.beans.factory.config.BeanDefinition` to
    /// signal that its registration should not be processed.
    enum string IGNORE_REGISTRATION_ATTRIBUTE = "aotProcessingIgnoreRegistration";

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotProcessor#isBeanExcludedFromAotProcessing(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationAotProcessor#processAheadOfTime(RegisteredBean): type org.springframework.beans.factory.support.RegisteredBean is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationCode sha256:edd5061b971cfc63a4be6bc983b7644bf520da901d8adc55197dce41c15e594d
/// Interface that can be used to configure the code that will be generated to perform registration of a single bean.
interface BeanRegistrationCode
{
    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCode#addInstancePostProcessor(MethodReference): type org.springframework.aot.generate.MethodReference is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCode#getClassName(): type ClassName does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCode#getMethods(): type org.springframework.aot.generate.GeneratedMethods is excluded (runtime-reflection)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationCodeFragments sha256:e565561a342c765c309416b0f665a8357691a210813b0175d28b7fcf06503c71
/// Generate the various fragments of code needed to register a bean. A default implementation is provided that suits
/// most needs and custom code fragments are only expected to be used by library authors having built custom arrangement
/// on top of the core container. Users are not expected to implement this interface directly, but rather extends from
/// `BeanRegistrationCodeFragmentsDecorator` and only override the necessary method(s).
interface BeanRegistrationCodeFragments
{
    /// The variable name used when creating the bean definition.
    enum string BEAN_DEFINITION_VARIABLE = "beanDefinition";
    /// The variable name used when creating the bean definition.
    enum string INSTANCE_SUPPLIER_VARIABLE = "instanceSupplier";

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#generateInstanceSupplierCode(GenerationContext,BeanRegistrationCode,boolean): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#generateNewBeanDefinitionCode(GenerationContext,ResolvableType,BeanRegistrationCode): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#generateReturnCode(GenerationContext,BeanRegistrationCode): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#generateSetBeanDefinitionPropertiesCode(GenerationContext,BeanRegistrationCode,RootBeanDefinition,Predicate): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#generateSetBeanInstanceSupplierCode(GenerationContext,BeanRegistrationCode,CodeBlock,List): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragments#getTarget(RegisteredBean): type ClassName does not resolve to a pinned type
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator sha256:2800e9c7cebe7248c9048687e6a6919171c5e5536f194baa2b7192075549d5bb
/// A `BeanRegistrationCodeFragments` decorator implementation. Typically used when part of the default code fragments
/// have to customized, by extending this class and using it as part of
/// `BeanRegistrationAotContribution.withCustomCodeFragments(UnaryOperator)`.
class BeanRegistrationCodeFragmentsDecorator : BeanRegistrationCodeFragments
{
    private BeanRegistrationCodeFragments delegate_;

    @disable this();

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#<init>(BeanRegistrationCodeFragments): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#generateInstanceSupplierCode(GenerationContext,BeanRegistrationCode,boolean): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#generateNewBeanDefinitionCode(GenerationContext,ResolvableType,BeanRegistrationCode): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#generateReturnCode(GenerationContext,BeanRegistrationCode): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#generateSetBeanDefinitionPropertiesCode(GenerationContext,BeanRegistrationCode,RootBeanDefinition,Predicate): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#generateSetBeanInstanceSupplierCode(GenerationContext,BeanRegistrationCode,CodeBlock,List): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationCodeFragmentsDecorator#getTarget(RegisteredBean): type ClassName does not resolve to a pinned type
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationExcludeFilter sha256:278be48fa70f9891d8d23a35c1fa0bd512737e96c73a0ab8fcd251e9ecf8c69d
/// Filter that can be used to exclude AOT processing of a `RegisteredBean`.
interface BeanRegistrationExcludeFilter
{
    // port:pending org.springframework.beans.factory.aot.BeanRegistrationExcludeFilter#isExcludedFromAotProcessing(RegisteredBean): type org.springframework.beans.factory.support.RegisteredBean is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.BeanRegistrationsCode sha256:64a3521a35bd16d7a5b07f20f12f4b6aa68eeaec29961a9fa01e6b483ffb30ed
/// Interface that can be used to configure the code that will be generated to register beans.
interface BeanRegistrationsCode
{
    // port:pending org.springframework.beans.factory.aot.BeanRegistrationsCode#getClassName(): type ClassName does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.BeanRegistrationsCode#getMethods(): type org.springframework.aot.generate.GeneratedMethods is excluded (runtime-reflection)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.aot.CodeWarnings sha256:7116bc97a7322bdaecf4d1b8f815d0268e7213033506f82ed7472f625a6e96a0
/// Helper class to register warnings that the compiler may trigger on generated code.
class CodeWarnings
{
    private Set!(string) warnings;

    @disable this();

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#<init>(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#detectDeprecation(AnnotatedElement): varargs (R7)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#detectDeprecation(ResolvableType): type org.springframework.core.ResolvableType is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#detectDeprecation(Stream): generic type Stream<...>

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#generateValueCode(): type CodeBlock does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#getWarnings(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#register(Deprecated): type java.lang.Deprecated is not mapped to a D symbol

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#register(String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#registerDeprecationIfNecessary(AnnotatedElement): type java.lang.reflect.AnnotatedElement is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#suppress(Consumer): generic type Consumer<...>

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#suppress(MethodSpec.Builder): type MethodSpec.Builder does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#suppress(TypeSpec.Builder): type TypeSpec.Builder does not resolve to a pinned type

    // port:pending org.springframework.beans.factory.aot.CodeWarnings#toString(): the body is not written yet (--strip-pending)
}
// port:end
