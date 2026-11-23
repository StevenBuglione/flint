package com.example.worker;

/** A job that cannot run: invalid JSON, a missing field, an invalid id, an unknown op or an invalid input. */
public class JobFailure extends Exception {

    public JobFailure(String message) {
        super(message);
    }
}
