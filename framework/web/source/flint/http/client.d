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
// Ported from spring-framework v7.1.0: spring-web/src/main/java/org/springframework/http/client/
// AbstractClientHttpRequest.java, AbstractClientHttpRequestFactoryWrapper.java, ClientHttpRequest.java,
// ClientHttpRequestExecution.java, ClientHttpRequestFactory.java, ClientHttpRequestInitializer.java,
// ClientHttpRequestInterceptor.java, ClientHttpResponse.java
// Licensed under the Apache License, Version 2.0
// Modified by the Flint authors.

/// The Java package `org.springframework.http.client`.
module flint.http.client;

import flint.java.io.closeable : Closeable;
import flint.http : HttpHeaders;
import flint.http : HttpInputMessage;
import flint.http : HttpMethod;
import flint.http : HttpOutputMessage;
import flint.http : HttpRequest;
import flint.http : HttpStatusCode;
import flint.java.net : URI;
import std.typecons : Nullable;
import flint.java.util : Map;
import flint.engine.aot.any : Any;

@safe:

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.AbstractClientHttpRequest sha256:ece79e2faf72818b53467e3b0b18449c9e7cd76fcf1bcd221b8d7962e8fac769
/// Abstract base for `ClientHttpRequest` that makes sure that headers and body are not written multiple times.
abstract class AbstractClientHttpRequest : ClientHttpRequest
{
    private HttpHeaders headers;
    private bool executed = false;
    private Nullable!(HttpHeaders) readOnlyHeaders;
    private Map!(string, Any) attributes;

    @disable this();

    /// Abstract template method that writes the given headers and content to the HTTP request.
    protected abstract ClientHttpResponse executeInternal(HttpHeaders headers);

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#<init>(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#assertNotExecuted(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#execute(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#getAttributes(): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#getBody(): type java.io.OutputStream is not mapped to a D symbol

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#getBodyInternal(HttpHeaders): type java.io.OutputStream is not mapped to a D symbol

    // port:pending org.springframework.http.client.AbstractClientHttpRequest#getHeaders(): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.AbstractClientHttpRequestFactoryWrapper sha256:4f6f37b9c82ce7601866027a397092b8d9a7aadb42d2e9dcb4b6d8bc651bdcde
/// Abstract base class for `ClientHttpRequestFactory` implementations that decorate another delegate request factory.
abstract class AbstractClientHttpRequestFactoryWrapper : ClientHttpRequestFactory
{
    private ClientHttpRequestFactory requestFactory;

    @disable this();

    /// Return the delegate request factory.
    ClientHttpRequestFactory getDelegate()
    {
        return this.requestFactory;
    }

    /// Create a new `ClientHttpRequest` for the specified URI and HTTP method by using the passed-on request factory.
    /// Called from `HttpMethod)`.
    protected abstract ClientHttpRequest createRequest(URI uri, HttpMethod httpMethod, ClientHttpRequestFactory requestFactory);

    // port:pending org.springframework.http.client.AbstractClientHttpRequestFactoryWrapper#<init>(ClientHttpRequestFactory): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.AbstractClientHttpRequestFactoryWrapper#createRequest(URI,HttpMethod): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpRequest sha256:ae7c411b87ff771de7ba3d881d6d1e1ec778c915f0770a16e6ef6429b2e438c0
/// Represents a client-side HTTP request. Created via an implementation of the `ClientHttpRequestFactory`. A
/// `ClientHttpRequest` can be `executed`, receiving a `ClientHttpResponse` which can be read from.
interface ClientHttpRequest : HttpRequest, HttpOutputMessage
{
    /// Execute this request, resulting in a `ClientHttpResponse` that can be read.
    ClientHttpResponse execute();
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpRequestExecution sha256:93ecd6c9d9668cf7d700940901aad13a5855b47f3f3ebcd25d09117d34c671b5
/// Represents the context of a client-side HTTP request execution. Used to invoke the next interceptor in the
/// interceptor chain, or - if the calling interceptor is last - execute the request itself.
interface ClientHttpRequestExecution
{
    /// Execute the request with the given request attributes and body, and return the response.
    ClientHttpResponse execute(HttpRequest request, byte[] body_);
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpRequestFactory sha256:214f357bf046bd73503d9d780127eb0057c9a7d40e0dcfbf3563a1ac6571ed0f
/// Factory for `ClientHttpRequest` objects. Requests are created by the `HttpMethod)` method.
interface ClientHttpRequestFactory
{
    /// Create a new `ClientHttpRequest` for the specified URI and HTTP method. The returned request can be written to,
    /// and then executed by calling `ClientHttpRequest.execute()`.
    ClientHttpRequest createRequest(URI uri, HttpMethod httpMethod);
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpRequestInitializer sha256:db0f4165614fb7639ca2c3aae6cc7c0c4c1938e5391b561b724eae23a8bb8694
/// Callback interface for initializing a `ClientHttpRequest` prior to it being used. Typically used with `HttpAccessor`
/// and subclasses such as `RestTemplate` to apply consistent settings or headers to each request. Unlike
/// `ClientHttpRequestInterceptor`, this interface can apply customizations without needing to read the entire request
/// body into memory.
interface ClientHttpRequestInitializer
{
    /// Initialize the given client HTTP request.
    void initialize(ClientHttpRequest request);
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpRequestInterceptor sha256:32707cf61dce692efc843fc51d5e46bc082dd052b6554254197bc70cc3f3117d
/// Contract to intercept client-side HTTP requests. Implementations can be registered with
/// `org.springframework.web.client.RestClient` or `org.springframework.web.client.RestTemplate` to modify the outgoing
/// request and/or the incoming response.
interface ClientHttpRequestInterceptor
{
    /// Intercept the given request, and return a response. The given `ClientHttpRequestExecution` allows the
    /// interceptor to pass on the request and response to the next entity in the chain. A typical implementation of
    /// this method would follow the following pattern: Examine the `request` and body. Optionally `wrap` the request to
    /// filter HTTP attributes. Optionally modify the body of the request. either execute the request using `byte[])` or
    /// do not execute the request to block the execution altogether Optionally wrap the response to filter HTTP
    /// attributes. Note: if the interceptor throws an exception after receiving a response, it must close the response
    /// via `ClientHttpResponse.close()`.
    ClientHttpResponse intercept(HttpRequest request, byte[] body_, ClientHttpRequestExecution execution);

    // port:pending org.springframework.http.client.ClientHttpRequestInterceptor#andThen(ClientHttpRequestInterceptor): the body is not written yet (--strip-pending)

    // port:pending org.springframework.http.client.ClientHttpRequestInterceptor#apply(ClientHttpRequestExecution): the body is not written yet (--strip-pending)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.http.client.ClientHttpResponse sha256:89a6e2a03626c7556269eacf3e08953d69660f6a5d0578caf7dbfe2793001adb
/// Represents a client-side HTTP response. Obtained via an invocation of `ClientHttpRequest.execute()`. A
/// `ClientHttpResponse` must be `closed`, typically in a `finally` block.
interface ClientHttpResponse : HttpInputMessage, Closeable
{
    /// Get the HTTP status code as an `HttpStatusCode`.
    HttpStatusCode getStatusCode();

    /// Get the HTTP status text of the response.
    string getStatusText();

    /// Close this response, freeing any resources created.
    void close();
}
// port:end
