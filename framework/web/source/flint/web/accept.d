/++
`org.springframework.web.accept`: content negotiation from the `Accept` header and configured defaults.

Ported from spring-projects/spring-framework v7.1.0, spring-web/src/main/java/org/springframework/web/accept/
(ContentNegotiationStrategy.java, ContentNegotiationManager.java, FixedContentNegotiationStrategy.java,
HeaderContentNegotiationStrategy.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook. Spring Boot's default manager has only the
header strategy.
+/
module flint.web.accept;

import flint.http : HttpHeaders, InvalidMediaTypeException, MediaType;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Collections, List;
import flint.util : InvalidMimeTypeException, MimeTypeUtils;
import flint.web : HttpMediaTypeNotAcceptableException;
import flint.web.context.request : NativeWebRequest;

@safe:

/// `ContentNegotiationStrategy`.
interface ContentNegotiationStrategy
{
    /// `*/*`, the result when a request states no preference.
    static MediaType[] MEDIA_TYPE_ALL_LIST() pure nothrow
    {
        return [MediaType.ALL];
    }

    /// The requested media types, most preferred first.
    MediaType[] resolveMediaTypes(NativeWebRequest webRequest);
}

/// `FixedContentNegotiationStrategy`: supplies configured media types in preference order.
class FixedContentNegotiationStrategy : ContentNegotiationStrategy
{
    private List!MediaType contentTypes;

    /// One default media type.
    this(MediaType contentType)
    {
        contentTypes = List!MediaType.of(contentType);
    }

    /// An unmodifiable view of the ordered defaults (R10).
    this(List!MediaType contentTypes)
    {
        if (contentTypes is null)
            throw new IllegalArgumentException("'contentTypes' must not be null");
        this.contentTypes = Collections.unmodifiableList(contentTypes);
    }

    /// The configured defaults.
    List!MediaType getContentTypes() pure nothrow @nogc
    {
        return contentTypes;
    }

    /// Returns a copy for the existing array-based negotiation interface (R10).
    MediaType[] resolveMediaTypes(NativeWebRequest request)
    {
        return contentTypes.toArray();
    }
}

/// `HeaderContentNegotiationStrategy`: the `Accept` header.
class HeaderContentNegotiationStrategy : ContentNegotiationStrategy
{
    MediaType[] resolveMediaTypes(NativeWebRequest request)
    {
        return resolveHeaderValues(request.getHeaderValues(HttpHeaders.ACCEPT));
    }

    /++
    Flint: the media types of the given `Accept` values (null when the request has none), as `resolveMediaTypes`
    reads them from a request. A caller that holds the request itself, such as `ProducesRequestCondition`'s
    lookup with Spring's default manager, uses it without wrapping the request or building a manager.
    +/
    static MediaType[] resolveHeaderValues(string[] headerValueArray)
    {
        if (headerValueArray is null)
            return MEDIA_TYPE_ALL_LIST();
        try
        {
            auto mediaTypes = MediaType.parseMediaTypes(headerValueArray);
            MimeTypeUtils.sortBySpecificity(mediaTypes);
            return mediaTypes.length != 0 ? mediaTypes : MEDIA_TYPE_ALL_LIST();
        }
        catch (InvalidMediaTypeException ex)
            throw new HttpMediaTypeNotAcceptableException(
                    "Could not parse 'Accept' header " ~ headersText(headerValueArray) ~ ": " ~ ex.getMessage());
        catch (InvalidMimeTypeException ex)
            throw new HttpMediaTypeNotAcceptableException(
                    "Could not parse 'Accept' header " ~ headersText(headerValueArray) ~ ": " ~ ex.getMessage());
    }

    private static string headersText(string[] values) pure nothrow
    {
        string text = "[";
        foreach (i, v; values)
            text ~= (i == 0 ? "" : ", ") ~ v;
        return text ~ "]";
    }
}

/// `ContentNegotiationManager`: consults its strategies in order.
class ContentNegotiationManager : ContentNegotiationStrategy
{
    private ContentNegotiationStrategy[] strategies;

    /// With `strategies`; the header strategy when none are given.
    this(ContentNegotiationStrategy[] strategies...)
    {
        this.strategies = strategies.length != 0 ? strategies.dup
            : [cast(ContentNegotiationStrategy) new HeaderContentNegotiationStrategy];
    }

    /// The strategies.
    ContentNegotiationStrategy[] getStrategies() pure nothrow @nogc
    {
        return strategies;
    }

    MediaType[] resolveMediaTypes(NativeWebRequest request)
    {
        MediaType[] all;
        foreach (strategy; strategies)
        {
            auto mediaTypes = strategy.resolveMediaTypes(request);
            // Spring compares with MEDIA_TYPE_ALL_LIST; comparing in place saves building that list per request.
            if (mediaTypes.length == 1 && mediaTypes[0] == MediaType.ALL)
            {
                all = mediaTypes;
                continue;
            }
            return mediaTypes;
        }
        return all !is null ? all : MEDIA_TYPE_ALL_LIST();
    }
}
