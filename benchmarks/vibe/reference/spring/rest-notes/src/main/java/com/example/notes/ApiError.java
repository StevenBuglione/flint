package com.example.notes;

/** A 400 body. field names the first invalid field, or is null for malformed JSON. */
public record ApiError(String error, String field) {
}
