package com.example.notes;

import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

/** Notes, always scoped to their owner: another user's note does not exist. */
@Repository
public class NoteRepository {

    private final JdbcClient jdbc;

    public NoteRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Note> findAll(long userId) {
        return jdbc.sql("SELECT id, title, body FROM notes WHERE user_id = ? ORDER BY id").param(userId)
                .query(Note.class).list();
    }

    public Optional<Note> find(long userId, long id) {
        return jdbc.sql("SELECT id, title, body FROM notes WHERE id = ? AND user_id = ?").params(id, userId)
                .query(Note.class).optional();
    }

    public Note create(long userId, String title, String body) {
        GeneratedKeyHolder key = new GeneratedKeyHolder();
        jdbc.sql("INSERT INTO notes (user_id, title, body) VALUES (?, ?, ?)").params(userId, title, body).update(key);
        return new Note(key.getKey().longValue(), title, body);
    }

    public boolean update(long userId, long id, String title, String body) {
        return jdbc.sql("UPDATE notes SET title = ?, body = ? WHERE id = ? AND user_id = ?")
                .params(title, body, id, userId).update() > 0;
    }

    public boolean delete(long userId, long id) {
        return jdbc.sql("DELETE FROM notes WHERE id = ? AND user_id = ?").params(id, userId).update() > 0;
    }
}
