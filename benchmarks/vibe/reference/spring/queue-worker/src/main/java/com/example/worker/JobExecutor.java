package com.example.worker;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Validates and runs one job. */
@Service
public class JobExecutor {

    /** A finished job. A null result is JSON null. */
    public record Outcome(String id, Object result) {
    }

    private static final Pattern ID = Pattern.compile("[A-Za-z0-9_-]{1,64}");

    private final JsonMapper json;

    public JobExecutor(JsonMapper json) {
        this.json = json;
    }

    public Outcome execute(byte[] content) throws JobFailure, InterruptedException {
        JsonNode job;
        try {
            job = json.readTree(content);
        } catch (JacksonException error) {
            throw new JobFailure("invalid JSON: " + error.getOriginalMessage());
        }
        if (job == null || !job.isObject() || !job.has("id") || !job.has("op") || !job.has("input")) {
            throw new JobFailure("a job needs id, op and input");
        }
        JsonNode id = job.get("id");
        JsonNode input = job.get("input");
        if (!id.isString() || !ID.matcher(id.stringValue()).matches()) {
            throw new JobFailure("invalid id " + id);
        }
        String op = job.get("op").isString() ? job.get("op").stringValue() : String.valueOf(job.get("op"));
        return switch (op) {
            case "sha256" -> new Outcome(id.stringValue(), sha256(text(op, input)));
            case "wordcount" -> new Outcome(id.stringValue(), wordCount(text(op, input)));
            case "sleep" -> {
                if (!input.isNumber() || input.doubleValue() < 0 || input.doubleValue() > 10000) {
                    throw new JobFailure("sleep needs a number of milliseconds from 0 to 10000");
                }
                Thread.sleep(Math.round(input.doubleValue()));
                yield new Outcome(id.stringValue(), null);
            }
            default -> throw new JobFailure("unknown op " + op);
        };
    }

    private static String text(String op, JsonNode input) throws JobFailure {
        if (!input.isString()) {
            throw new JobFailure(op + " needs a string input");
        }
        return input.stringValue();
    }

    private static String sha256(String input) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(input.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }

    private static int wordCount(String input) {
        String trimmed = input.strip();
        return trimmed.isEmpty() ? 0 : trimmed.split("\\s+").length;
    }
}
