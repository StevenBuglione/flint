package com.example.worker;

import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** The spool directory: incoming, done and failed. */
@Repository
public class SpoolQueue {

    private final Path incoming;
    private final Path done;
    private final Path failed;
    private final JsonMapper json;

    public SpoolQueue(WorkerOptions options, JsonMapper json) throws IOException {
        this.incoming = Files.createDirectories(options.spool().resolve("incoming"));
        this.done = Files.createDirectories(options.spool().resolve("done"));
        this.failed = Files.createDirectories(options.spool().resolve("failed"));
        this.json = json;
    }

    /** The job files in incoming, skipping temporary files that start with a dot. */
    public List<Path> pending() {
        List<Path> files = new ArrayList<>();
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(incoming, "[!.]*.json")) {
            stream.forEach(files::add);
        } catch (IOException error) {
            return List.of();
        }
        files.sort(null);
        return files;
    }

    public void writeDone(String id, Object result, Path job) throws IOException {
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("id", id);
        record.put("result", result);
        write(done, id + ".json", record);
        Files.deleteIfExists(job);
    }

    public void writeFailed(Path job, String error) throws IOException {
        String file = job.getFileName().toString();
        write(failed, file, Map.of("file", file, "error", error));
        Files.deleteIfExists(job);
    }

    /** Writes directory/name atomically through a temporary name that starts with a dot. */
    private void write(Path directory, String name, Object value) throws IOException {
        Path temporary = Files.createTempFile(directory, "." + name, ".tmp");
        try {
            Files.write(temporary, json.writeValueAsBytes(value));
            Files.move(temporary, directory.resolve(name), StandardCopyOption.ATOMIC_MOVE);
        } finally {
            Files.deleteIfExists(temporary);
        }
    }
}
