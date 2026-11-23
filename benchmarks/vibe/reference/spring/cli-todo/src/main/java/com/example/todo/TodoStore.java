package com.example.todo;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** The data file. nextId keeps ids from being reused after a removal. */
@Repository
public class TodoStore {

    public record Data(int nextId, List<Item> items) {
    }

    private final TodoSettings settings;
    private final JsonMapper json;

    public TodoStore(TodoSettings settings, JsonMapper json) {
        this.settings = settings;
        this.json = json;
    }

    public List<Item> items() {
        return load().items();
    }

    public int add(String text, Priority priority) {
        Data data = load();
        List<Item> items = new ArrayList<>(data.items());
        items.add(new Item(data.nextId(), text, priority, false));
        save(new Data(data.nextId() + 1, items));
        return data.nextId();
    }

    public void done(int id) {
        Data data = load();
        List<Item> items = new ArrayList<>(data.items());
        int index = indexOf(items, id);
        items.set(index, items.get(index).markDone());
        save(new Data(data.nextId(), items));
    }

    public void remove(int id) {
        Data data = load();
        List<Item> items = new ArrayList<>(data.items());
        items.remove(indexOf(items, id));
        save(new Data(data.nextId(), items));
    }

    private static int indexOf(List<Item> items, int id) {
        for (int i = 0; i < items.size(); i++) {
            if (items.get(i).id() == id) {
                return i;
            }
        }
        throw TodoException.notFound(id);
    }

    private Data load() {
        Path path = settings.dataFile();
        if (!Files.exists(path)) {
            return new Data(1, List.of());
        }
        return json.readValue(path.toFile(), Data.class);
    }

    private void save(Data data) {
        Path path = settings.dataFile();
        try {
            Files.createDirectories(path.toAbsolutePath().getParent());
            Path temporary = path.resolveSibling(path.getFileName() + ".tmp");
            json.writerWithDefaultPrettyPrinter().writeValue(temporary.toFile(), data);
            Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException error) {
            throw new UncheckedIOException(error);
        }
    }
}
