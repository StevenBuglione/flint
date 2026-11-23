package com.example.todo;

/** An expected failure with its exit code: 1 for an unknown id, 3 for a configuration error. */
public class TodoException extends RuntimeException {

    private final int exitCode;

    public TodoException(int exitCode, String message) {
        super(message);
        this.exitCode = exitCode;
    }

    public static TodoException notFound(int id) {
        return new TodoException(1, "no item with id " + id);
    }

    public static TodoException configuration(String message) {
        return new TodoException(3, message);
    }

    public int exitCode() {
        return exitCode;
    }
}
