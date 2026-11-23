package com.example.notes;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

@Repository
public class UserRepository {

    public record User(long id, String username, String passwordHash) {
    }

    private final JdbcClient jdbc;

    public UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public boolean existsByUsername(String username) {
        return jdbc.sql("SELECT COUNT(*) FROM users WHERE username = ?").param(username).query(Long.class).single() > 0;
    }

    public long create(String username, String passwordHash) {
        GeneratedKeyHolder key = new GeneratedKeyHolder();
        jdbc.sql("INSERT INTO users (username, password_hash) VALUES (?, ?)").params(username, passwordHash)
                .update(key);
        return key.getKey().longValue();
    }

    public Optional<User> findByUsername(String username) {
        return jdbc.sql("SELECT id, username, password_hash FROM users WHERE username = ?").param(username)
                .query(User.class).optional();
    }

    /** Stores a token for the user; only its SHA-256 is kept. */
    public void saveToken(String token, long userId) {
        jdbc.sql("INSERT INTO tokens (token_hash, user_id) VALUES (?, ?)").params(sha256(token), userId).update();
    }

    public Optional<Long> findUserByToken(String token) {
        return jdbc.sql("SELECT user_id FROM tokens WHERE token_hash = ?").param(sha256(token)).query(Long.class)
                .optional();
    }

    private static String sha256(String token) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }
}
