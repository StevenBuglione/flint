/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/web/multipart/
(MultipartException.java, MaxUploadSizeExceededException.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. Java default methods use the ErrorResponse mixin.
+/
module flint.web.multipart;

import flint.core : NestedRuntimeException;
import flint.engine.aot.text : decimal;
import flint.http : HttpStatus, HttpStatusCode, ProblemDetail;
import flint.web : ErrorResponse;

@safe:

/// Thrown when multipart resolution fails.
class MultipartException : NestedRuntimeException
{
    this(string message) pure nothrow
    {
        super(message);
    }

    this(string message, Throwable cause) pure nothrow
    {
        super(message, cause);
    }
}

/// Thrown when a multipart upload exceeds its size limit.
class MaxUploadSizeExceededException : MultipartException, ErrorResponse
{
    mixin ErrorResponse.Defaults;

    private long maxUploadSize;
    private ProblemDetail body;

    this(long maxUploadSize)
    {
        this(maxUploadSize, null);
    }

    this(long maxUploadSize, Throwable cause)
    {
        super(maxUploadSize >= 0
                ? "Maximum upload size of " ~ decimal(
                    maxUploadSize) ~ " bytes exceeded" : "Maximum upload size exceeded", cause);
        this.maxUploadSize = maxUploadSize;
        body = ProblemDetail.forStatusAndDetail(HttpStatus.CONTENT_TOO_LARGE, "Maximum upload size exceeded");
    }

    /// Returns the configured size limit, or -1 if it is unknown.
    long getMaxUploadSize()
    {
        return maxUploadSize;
    }

    HttpStatusCode getStatusCode()
    {
        return HttpStatus.CONTENT_TOO_LARGE;
    }

    ProblemDetail getBody()
    {
        return
        body;
    }
}
