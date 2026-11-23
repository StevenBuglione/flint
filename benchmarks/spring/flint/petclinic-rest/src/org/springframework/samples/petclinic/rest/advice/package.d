/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.advice`,
ported to Flint. Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- Java → D syntax, one module per Java package (R1); `Exception.class` is `classOf!Exception` (R4).
- `BindingErrorsResponse`, which the validation handler fills but never writes, is omitted.
- Flint's `HashMap` keeps insertion order, while Java's prints `field`, `defaultMessage`, `rejectedValue` for these
  three keys; the additional properties go in that order, so the body is the same.
- `String.valueOf` of a rejected value is `valueOf`: a boxed `LocalDate` (the only non-scalar one the DTOs reject)
  prints its ISO text, which `Any.toString` replaces by the type name.
+/
module org.springframework.samples.petclinic.rest.advice;

import flint.dao : DataIntegrityViolationException;
import flint.http : HttpStatus, ProblemDetail, ResponseEntity;
import flint.jakarta.servlet.http : HttpServletRequest;
import flint.java.lang : classOf;
import flint.java.net : URI;
import flint.engine.aot.any : Any;
import flint.java.time : Instant, LocalDate;
import flint.java.util : ArrayList, List;
import flint.slf4j : Logger, LoggerFactory;
import flint.web.bind : MethodArgumentNotValidException;
import flint.web.bind.annotation : ControllerAdvice, ExceptionHandler, ResponseBody;
import org.springframework.samples.petclinic.rest.dto : ValidationMessageDto;

@safe:

/// Global Exception handler for REST controllers: returns the exceptions thrown by REST controllers to the client
/// as problem details.
@ControllerAdvice
class ExceptionControllerAdvice
{
    private enum ERROR_UNEXPECTED = "An unexpected error occurred while processing your request";
    private enum ERROR_DATA_INTEGRITY = "The requested resource could not be processed due to a data "
        ~ "constraint violation";
    private enum ERROR_INVALID_REQUEST = "The request contains invalid or missing parameters";

    private static Logger logger()
    {
        return LoggerFactory.getLogger!ExceptionControllerAdvice();
    }

    // The ProblemDetail for `e`, with the request URL as its type.
    private ProblemDetail detailBuild(Exception e, HttpStatus status, string url, string detail)
    {
        ProblemDetail problemDetail = ProblemDetail.forStatus(status);
        problemDetail.setType(URI.create(url));
        problemDetail.setTitle(simpleName(e));
        problemDetail.setDetail(detail);
        problemDetail.setProperty("timestamp", Instant.now());
        problemDetail.setProperty("schemaValidationErrors", List!ValidationMessageDto.of());
        return problemDetail;
    }

    /// Handles all general exceptions by returning a 500 Internal Server Error status with error details.
    @ExceptionHandler(classOf!Exception)
    @ResponseBody
    ResponseEntity handleGeneralException(Exception e, HttpServletRequest request)
    {
        logger().error("Unexpected error at {} {}", request.getMethod(), request.getRequestURI(), e);
        HttpStatus status = HttpStatus.INTERNAL_SERVER_ERROR;
        ProblemDetail detail = this.detailBuild(e, status, request.getRequestURL(), ERROR_UNEXPECTED);
        return ResponseEntity.status(status).body(detail);
    }

    /// Handles `DataIntegrityViolationException`, which typically indicates database constraint violations: 404.
    // dfmt off
    @ExceptionHandler(classOf!DataIntegrityViolationException) @ResponseBody
    ResponseEntity handleDataIntegrityViolationException(
            DataIntegrityViolationException e, HttpServletRequest request)
    {
        logger().warn("Data integrity violation at {} {}: {}", request.getMethod(),
                request.getRequestURI(), e.getMessage());
        logger().debug_("Data integrity violation stacktrace", e);
        HttpStatus status = HttpStatus.NOT_FOUND;
        ProblemDetail detail = this.detailBuild(e, status, request.getRequestURL(), ERROR_DATA_INTEGRITY);
        return ResponseEntity.status(status).body(detail);
    }
    // dfmt on

    /// Handles exception thrown by Bean Validation on controller methods parameters: 400.
    // dfmt off
    @ExceptionHandler(classOf!MethodArgumentNotValidException) @ResponseBody
    ResponseEntity handleMethodArgumentNotValidException(
            MethodArgumentNotValidException e, HttpServletRequest request)
    {
        HttpStatus status = HttpStatus.BAD_REQUEST;
        auto bindingResult = e.getBindingResult();
        ProblemDetail detail = this.detailBuild(e, status, request.getRequestURL(), ERROR_INVALID_REQUEST);
        if (bindingResult.hasErrors())
        {
            auto schemaValidationErrors = new ArrayList!ValidationMessageDto();
            foreach (fieldError; bindingResult.getFieldErrors())
            {
                auto rejected = fieldError.getRejectedValue();
                string rejectedValue = valueOf(rejected);
                string defaultMessage = fieldError.getDefaultMessage() is null
                    ? "Validation failed" : fieldError.getDefaultMessage();
                string message = "Field '" ~ fieldError.getField() ~ "' " ~ defaultMessage
                    ~ " (rejected value: " ~ rejectedValue ~ ")";
                schemaValidationErrors.add(new ValidationMessageDto(message)
                        .putAdditionalProperty("field", fieldError.getField())
                        .putAdditionalProperty("defaultMessage",
                            defaultMessage).putAdditionalProperty("rejectedValue", rejectedValue));
            }
            logger().debug_("Validation error at {} {}: {}", request.getMethod(),
                    request.getRequestURI(), bindingResult.getFieldErrors());
            detail.setProperty("schemaValidationErrors", cast(List!ValidationMessageDto) schemaValidationErrors);
            return ResponseEntity.status(status).body(detail);
        }
        return ResponseEntity.status(status).body(detail);
    }
    // dfmt on

    // Java's `getClass().getSimpleName()`.
    private static string simpleName(Exception e)
    {
        import std.string : lastIndexOf;

        const name = typeid(e).name;
        const dot = name.lastIndexOf('.');
        return dot < 0 ? name : name[dot + 1 .. $];
    }
}

/// Java's `String.valueOf(Object)` for a rejected value: `"null"`, a `LocalDate`'s ISO text, or the value's text.
private string valueOf(const Any value)
{
    if (value.isNull)
        return "null";
    if (value.holds!LocalDate)
        return value.get!LocalDate.toString();
    return value.toString();
}
