package com.example.notes;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Request bodies. Components are declared in the order their errors are reported. */
public final class Requests {

    private Requests() {
    }

    public record Registration(
            @NotNull @Pattern(regexp = "[a-z0-9_]{3,32}", message = "must be 3 to 32 characters from a-z, 0-9 and _")
            String username,
            @NotNull @Size(min = 8, message = "must be at least 8 characters") String password) {
    }

    public record Credentials(@NotNull String username, @NotNull String password) {
    }

    public record NoteInput(
            @NotNull @Size(min = 1, max = 100) String title,
            @NotNull @Size(max = 10000) String body) {
    }
}
