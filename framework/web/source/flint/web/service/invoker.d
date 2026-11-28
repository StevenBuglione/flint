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
// Ported from spring-framework v7.1.0: spring-web/src/main/java/org/springframework/web/service/invoker/
// HttpExchangeAdapter.java, HttpMethodArgumentResolver.java, HttpServiceArgumentResolver.java,
// ReactorHttpExchangeAdapter.java, UriBuilderFactoryArgumentResolver.java, UrlArgumentResolver.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.web.service.invoker`.
module flint.web.service.invoker;

import flint.java.time : Duration;
import flint.http : HttpHeaders;
import flint.core : MethodParameter;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.HttpExchangeAdapter sha256:74897242af590a5e0d28e5896f5ef79380ff7ca19fc05e09239f8126bffc93bd
/// Contract to abstract an HTTP client from `HttpServiceProxyFactory` and make it pluggable. For reactive clients, see
/// `ReactorHttpExchangeAdapter`.
interface HttpExchangeAdapter
{
    /// Whether the underlying client supports use of request attributes.
    bool supportsRequestAttributes();

    // port:pending org.springframework.web.service.invoker.HttpExchangeAdapter#exchange(HttpRequestValues): type org.springframework.web.service.invoker.HttpRequestValues is not mapped to a D symbol

    // port:pending org.springframework.web.service.invoker.HttpExchangeAdapter#exchangeForBodilessEntity(HttpRequestValues): generic type ResponseEntity<...>

    // port:pending org.springframework.web.service.invoker.HttpExchangeAdapter#exchangeForBody(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.HttpExchangeAdapter#exchangeForEntity(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.HttpExchangeAdapter#exchangeForHeaders(HttpRequestValues): type org.springframework.web.service.invoker.HttpRequestValues is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.HttpMethodArgumentResolver sha256:391ef2f61fcf1bf83c6fc13dce98237c9eedc4a8074d854b1a2359c4b6338062
/// `HttpServiceArgumentResolver` that resolves the target request's HTTP method from an `HttpMethod` argument.
class HttpMethodArgumentResolver : HttpServiceArgumentResolver
{
    // port:pending org.springframework.web.service.invoker.HttpMethodArgumentResolver#logger: a constant whose initializer is not a literal

    // port:pending org.springframework.web.service.invoker.HttpMethodArgumentResolver#resolve(Object,MethodParameter,HttpRequestValues.Builder): type org.springframework.web.service.invoker.HttpRequestValues.Builder is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.HttpServiceArgumentResolver sha256:12b081f41f4f9c883734614306b90ba5f30e850a0c071019ebbc9ae2f11d0ab2
/// Resolve an argument from an `@HttpExchange`-annotated method to one or more HTTP request values.
interface HttpServiceArgumentResolver
{
    // port:pending org.springframework.web.service.invoker.HttpServiceArgumentResolver#resolve(Object,MethodParameter,HttpRequestValues.Builder): type org.springframework.web.service.invoker.HttpRequestValues.Builder is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.ReactorHttpExchangeAdapter sha256:88e1d9a5c69fc7a16e50d6215d0b43ef3dc135c75eb8382e77a37527b9b295fc
/// Contract to abstract a reactive, HTTP client from `HttpServiceProxyFactory` and make it pluggable.
interface ReactorHttpExchangeAdapter : HttpExchangeAdapter
{
    /// Return the configured time to block for the response from an HTTP service method with a synchronous (blocking)
    /// method signature. By default, not set in which case the behavior depends on connection and request timeout
    /// settings of the underlying HTTP client. We recommend configuring timeout values directly on the underlying HTTP
    /// client, which provides more control over such settings.
    Duration getBlockTimeout();

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForBodilessEntityMono(HttpRequestValues): type Mono does not resolve to a pinned type

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForBodyFlux(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForBodyMono(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForEntityFlux(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForEntityMono(HttpRequestValues,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForHeadersMono(HttpRequestValues): type Mono does not resolve to a pinned type

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#exchangeForMono(HttpRequestValues): type Mono does not resolve to a pinned type

    // port:pending org.springframework.web.service.invoker.ReactorHttpExchangeAdapter#getReactiveAdapterRegistry(): type org.springframework.core.ReactiveAdapterRegistry is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.UriBuilderFactoryArgumentResolver sha256:fe8afb77da8e1bc73e8e7a4c31266a14b3eccf2a7573a34f1b7bd0491cc7d299
/// An `HttpServiceArgumentResolver` that uses the provided `UriBuilderFactory` to expand the `UriTemplate`. Unlike with
/// the `UrlArgumentResolver`, if the `UriBuilderFactoryArgumentResolver` is provided, it will not override the entire
/// `URL`, but just the `baseUri`. This allows for dynamically setting the `baseUri`, while keeping the `path` specified
/// through class and method annotations.
class UriBuilderFactoryArgumentResolver : HttpServiceArgumentResolver
{
    // port:pending org.springframework.web.service.invoker.UriBuilderFactoryArgumentResolver#resolve(Object,MethodParameter,HttpRequestValues.Builder): type org.springframework.web.service.invoker.HttpRequestValues.Builder is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.web.service.invoker.UrlArgumentResolver sha256:55f1d16f8c9efb4c938818f434433ca99083731081a37c624c6853b4db24de9a
/// `HttpServiceArgumentResolver` that resolves the URL for the request from a `URI` argument.
class UrlArgumentResolver : HttpServiceArgumentResolver
{
    // port:pending org.springframework.web.service.invoker.UrlArgumentResolver#resolve(Object,MethodParameter,HttpRequestValues.Builder): type org.springframework.web.service.invoker.HttpRequestValues.Builder is not mapped to a D symbol
}
// port:end
