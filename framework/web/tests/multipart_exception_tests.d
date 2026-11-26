module flint.web.multipart_exception_tests;

import flint.web : ErrorResponse;
import flint.web.multipart : MaxUploadSizeExceededException, MultipartException;

@safe:

@("MultipartException.preservesParserCause")
unittest
{
    auto cause = new Exception("parser failed");
    auto error = new MultipartException("Multipart resolution failed", cause);

    assert(error.getMessage() == "Multipart resolution failed");
    assert(error.getCause() is cause);
    assert(error.getRootCause() is cause);
    assert((new MultipartException("No cause")).getCause() is null);
}

@("MaxUploadSizeExceededException.knownLimit")
unittest
{
    auto cause = new Exception("parser limit");
    auto error = new MaxUploadSizeExceededException(long.max, cause);
    ErrorResponse response = error;

    assert(error.getMaxUploadSize() == long.max);
    assert(error.getMessage() == "Maximum upload size of 9223372036854775807 bytes exceeded");
    assert(error.getCause() is cause);
    assert(response.getStatusCode().value() == 413);
    assert(response.getBody().getStatus() == 413);
    assert(response.getBody().getDetail() == "Maximum upload size exceeded");
    assert(response.getBody() is response.getBody());
}

@("MaxUploadSizeExceededException.unknownLimit")
unittest
{
    auto error = new MaxUploadSizeExceededException(-1);

    assert(error.getMaxUploadSize() == -1);
    assert(error.getCause() is null);
    assert(error.getMessage() == "Maximum upload size exceeded");

    auto another = new MaxUploadSizeExceededException(0);
    assert(another.getMessage() == "Maximum upload size of 0 bytes exceeded");
    assert(error.getBody() !is another.getBody());
}
