package com.example.notes;

import com.example.notes.Requests.NoteInput;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/notes")
public class NoteController {

    private final NoteRepository notes;

    public NoteController(NoteRepository notes) {
        this.notes = notes;
    }

    @GetMapping
    public List<Note> list(@RequestAttribute(BearerTokenInterceptor.USER_ID) long userId) {
        return notes.findAll(userId);
    }

    @PostMapping
    public ResponseEntity<Note> create(@RequestAttribute(BearerTokenInterceptor.USER_ID) long userId,
                                       @Valid @RequestBody NoteInput input) {
        return ResponseEntity.status(HttpStatus.CREATED).body(notes.create(userId, input.title(), input.body()));
    }

    @GetMapping("/{id}")
    public Note get(@RequestAttribute(BearerTokenInterceptor.USER_ID) long userId, @PathVariable long id) {
        return notes.find(userId, id).orElseThrow(NoteController::notFound);
    }

    @PutMapping("/{id}")
    public Note update(@RequestAttribute(BearerTokenInterceptor.USER_ID) long userId, @PathVariable long id,
                       @Valid @RequestBody NoteInput input) {
        if (!notes.update(userId, id, input.title(), input.body())) {
            throw notFound();
        }
        return new Note(id, input.title(), input.body());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@RequestAttribute(BearerTokenInterceptor.USER_ID) long userId,
                                       @PathVariable long id) {
        if (!notes.delete(userId, id)) {
            throw notFound();
        }
        return ResponseEntity.noContent().build();
    }

    private static ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "note not found");
    }
}
