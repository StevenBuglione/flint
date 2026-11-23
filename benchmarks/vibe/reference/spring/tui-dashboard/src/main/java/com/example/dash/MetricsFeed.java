package com.example.dash;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Follows the source file, keeping a partial last line until it is complete. */
public class MetricsFeed implements AutoCloseable {

    private final RandomAccessFile file;
    private final JsonMapper json;
    private String partial = "";

    public MetricsFeed(Path path, JsonMapper json) throws IOException {
        this.file = new RandomAccessFile(path.toFile(), "r");
        this.json = json;
    }

    /** Applies the lines appended since the last call; reports whether any arrived. */
    public boolean read(Board board) {
        try {
            long available = file.length() - file.getFilePointer();
            if (available <= 0) {
                return false;
            }
            byte[] bytes = new byte[(int) available];
            file.readFully(bytes);
            String text = partial + new String(bytes, StandardCharsets.UTF_8);
            int end = text.lastIndexOf('\n');
            partial = text.substring(end + 1);
            if (end < 0) {
                return false;
            }
            for (String line : text.substring(0, end).split("\n")) {
                apply(board, line);
            }
            return true;
        } catch (IOException error) {
            throw new UncheckedIOException(error);
        }
    }

    private void apply(Board board, String line) {
        if (line.isBlank()) {
            return;
        }
        try {
            JsonNode node = json.readTree(line);
            if (node.isObject() && node.path("name").isString() && node.path("value").isNumber()) {
                board.put(node.get("name").stringValue(), node.get("value").doubleValue());
                return;
            }
        } catch (JacksonException malformed) {
            // counted as skipped below
        }
        board.skip();
    }

    @Override
    public void close() throws IOException {
        file.close();
    }
}
