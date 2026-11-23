package com.example.notes;

import com.example.notes.Requests.Credentials;
import com.example.notes.Requests.Registration;
import jakarta.validation.Valid;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api")
public class AuthController {

    private final UserRepository users;
    private final PasswordEncoder passwords;
    private final SecureRandom random = new SecureRandom();

    public AuthController(UserRepository users, PasswordEncoder passwords) {
        this.users = users;
        this.passwords = passwords;
    }

    @PostMapping("/users")
    public ResponseEntity<Map<String, Object>> register(@Valid @RequestBody Registration request) {
        if (users.existsByUsername(request.username())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "username taken");
        }
        long id = users.create(request.username(), passwords.encode(request.password()));
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id", id, "username", request.username()));
    }

    @PostMapping("/login")
    public Map<String, String> login(@Valid @RequestBody Credentials request) {
        UserRepository.User user = users.findByUsername(request.username())
                .filter(found -> passwords.matches(request.password(), found.passwordHash()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "wrong username or password"));
        byte[] secret = new byte[32];
        random.nextBytes(secret);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
        users.saveToken(token, user.id());
        return Map.of("token", token);
    }
}
