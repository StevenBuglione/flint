package com.example.notes;

import java.lang.reflect.RecordComponent;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.exc.MismatchedInputException;

@RestControllerAdvice
public class ApiExceptionHandler {

    /** A constraint failed: name the first invalid field in the order the request declares them. */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Object> invalid(MethodArgumentNotValidException error) {
        List<String> order = Arrays.stream(error.getParameter().getParameterType().getRecordComponents())
                .map(RecordComponent::getName).toList();
        FieldError first = error.getFieldErrors().stream()
                .min(Comparator.comparingInt(field -> order.indexOf(field.getField()))).orElseThrow();
        return badRequest(first.getField() + " " + first.getDefaultMessage(), first.getField());
    }

    /** Malformed JSON has no field; a value of the wrong type names its field. */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<Object> unreadable(HttpMessageNotReadableException error) {
        if (error.getCause() instanceof MismatchedInputException mismatch && !mismatch.getPath().isEmpty()
                && mismatch.getPath().getFirst().getPropertyName() != null) {
            String field = mismatch.getPath().getFirst().getPropertyName();
            return badRequest(field + " has the wrong type", field);
        }
        return badRequest("malformed JSON", null);
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<Object> status(ResponseStatusException error) {
        return ResponseEntity.status(error.getStatusCode()).body(Map.of("error", error.getReason()));
    }

    private static ResponseEntity<Object> badRequest(String message, String field) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new ApiError(message, field));
    }
}
