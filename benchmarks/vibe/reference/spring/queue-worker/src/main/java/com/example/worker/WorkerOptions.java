package com.example.worker;

import java.nio.file.Path;

/** `worker --spool <dir> [--concurrency <n>]`. */
public record WorkerOptions(Path spool, int concurrency) {

    public static WorkerOptions parse(String[] args) {
        String spool = null;
        int concurrency = 4;
        for (int i = 0; i < args.length; i++) {
            String name = args[i];
            String value = null;
            int equals = name.indexOf('=');
            if (equals > 0) {
                value = name.substring(equals + 1);
                name = name.substring(0, equals);
            } else if (i + 1 < args.length) {
                value = args[++i];
            }
            if (value == null) {
                throw new IllegalArgumentException(name + " needs a value");
            }
            switch (name) {
                case "--spool" -> spool = value;
                case "--concurrency" -> {
                    try {
                        concurrency = Integer.parseInt(value);
                    } catch (NumberFormatException error) {
                        concurrency = 0;
                    }
                    if (concurrency < 1 || concurrency > 64) {
                        throw new IllegalArgumentException("--concurrency must be from 1 to 64");
                    }
                }
                default -> throw new IllegalArgumentException("unknown option " + name);
            }
        }
        if (spool == null) {
            throw new IllegalArgumentException("--spool is required");
        }
        return new WorkerOptions(Path.of(spool), concurrency);
    }
}
