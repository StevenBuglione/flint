package com.example.todo;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import org.springframework.stereotype.Component;
import tools.jackson.core.JacksonException;
import tools.jackson.dataformat.toml.TomlMapper;

/** The [todo] table of the configuration file: TODO_CONFIG, else ~/.config/todo/config.toml. */
@Component
public class TodoSettings {

    private final Path home = Path.of(System.getenv().getOrDefault("HOME", System.getProperty("user.home")));
    private Path dataFile;
    private Priority defaultPriority;

    public Path dataFile() {
        load();
        return dataFile;
    }

    public Priority defaultPriority() {
        load();
        return defaultPriority;
    }

    private void load() {
        if (dataFile != null) {
            return;
        }
        dataFile = home.resolve(".local/share/todo/todos.json");
        defaultPriority = Priority.normal;
        String configured = System.getenv("TODO_CONFIG");
        Path path = configured != null && !configured.isEmpty()
                ? Path.of(configured) : home.resolve(".config/todo/config.toml");
        if (!Files.isRegularFile(path)) {
            return;
        }
        Map<String, Object> file;
        try {
            file = new TomlMapper().readValue(path.toFile(), Map.class);
        } catch (JacksonException error) {
            throw TodoException.configuration(path + ": " + error.getOriginalMessage());
        }
        for (Map.Entry<String, Object> table : file.entrySet()) {
            if (!table.getKey().equals("todo") || !(table.getValue() instanceof Map<?, ?> values)) {
                throw TodoException.configuration(path + ": unknown key " + table.getKey());
            }
            for (Map.Entry<?, ?> entry : values.entrySet()) {
                String key = String.valueOf(entry.getKey());
                Object value = entry.getValue();
                switch (key) {
                    case "data_file" -> {
                        if (!(value instanceof String text) || text.isEmpty()) {
                            throw TodoException.configuration(path + ": data_file must be a path");
                        }
                        dataFile = Path.of(text);
                    }
                    case "default_priority" -> defaultPriority = parsePriority(path, value);
                    default -> throw TodoException.configuration(path + ": unknown key todo." + key);
                }
            }
        }
    }

    private static Priority parsePriority(Path path, Object value) {
        try {
            return Priority.valueOf(String.valueOf(value));
        } catch (IllegalArgumentException error) {
            throw TodoException.configuration(path + ": default_priority must be low, normal or high, not " + value);
        }
    }
}
