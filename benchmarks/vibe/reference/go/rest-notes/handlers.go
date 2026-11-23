package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

var validUsername = regexp.MustCompile(`^[a-z0-9_]{3,32}$`)

// Routes is the API.
func Routes(store *Store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/users", func(w http.ResponseWriter, r *http.Request) {
		fields, problem := decode(r, []field{
			{"username", func(s string) bool { return validUsername.MatchString(s) },
				"username must be 3 to 32 characters from a-z, 0-9 and _"},
			{"password", func(s string) bool { return utf8.RuneCountInString(s) >= 8 },
				"password must be at least 8 characters"},
		})
		if problem != nil {
			writeJSON(w, http.StatusBadRequest, problem)
			return
		}
		id, err := store.Register(fields["username"], fields["password"])
		switch {
		case errors.Is(err, ErrTaken):
			writeError(w, http.StatusConflict, "username taken")
		case err != nil:
			serverError(w, err)
		default:
			writeJSON(w, http.StatusCreated, map[string]any{"id": id, "username": fields["username"]})
		}
	})
	mux.HandleFunc("POST /api/login", func(w http.ResponseWriter, r *http.Request) {
		fields, problem := decode(r, []field{
			{"username", nonEmpty, "username is required"},
			{"password", nonEmpty, "password is required"},
		})
		if problem != nil {
			writeJSON(w, http.StatusBadRequest, problem)
			return
		}
		token, err := store.Login(fields["username"], fields["password"])
		switch {
		case errors.Is(err, ErrNotFound):
			writeError(w, http.StatusUnauthorized, "wrong username or password")
		case err != nil:
			serverError(w, err)
		default:
			writeJSON(w, http.StatusOK, map[string]string{"token": token})
		}
	})
	mux.Handle("GET /api/notes", authenticated(store, func(w http.ResponseWriter, r *http.Request, user int64) {
		notes, err := store.Notes(user)
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, notes)
	}))
	mux.Handle("POST /api/notes", authenticated(store, func(w http.ResponseWriter, r *http.Request, user int64) {
		fields, problem := decode(r, noteFields)
		if problem != nil {
			writeJSON(w, http.StatusBadRequest, problem)
			return
		}
		note, err := store.CreateNote(user, fields["title"], fields["body"])
		respond(w, http.StatusCreated, note, err)
	}))
	mux.Handle("GET /api/notes/{id}", authenticated(store, func(w http.ResponseWriter, r *http.Request, user int64) {
		id, ok := noteID(w, r)
		if ok {
			note, err := store.Note(user, id)
			respond(w, http.StatusOK, note, err)
		}
	}))
	mux.Handle("PUT /api/notes/{id}", authenticated(store, func(w http.ResponseWriter, r *http.Request, user int64) {
		id, ok := noteID(w, r)
		if !ok {
			return
		}
		fields, problem := decode(r, noteFields)
		if problem != nil {
			writeJSON(w, http.StatusBadRequest, problem)
			return
		}
		note, err := store.UpdateNote(user, id, fields["title"], fields["body"])
		respond(w, http.StatusOK, note, err)
	}))
	mux.Handle("DELETE /api/notes/{id}", authenticated(store, func(w http.ResponseWriter, r *http.Request, user int64) {
		id, ok := noteID(w, r)
		if !ok {
			return
		}
		if err := store.DeleteNote(user, id); err != nil {
			respond(w, 0, nil, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	return mux
}

var noteFields = []field{
	{"title", func(s string) bool { n := utf8.RuneCountInString(s); return n >= 1 && n <= 100 },
		"title must be 1 to 100 characters"},
	{"body", func(s string) bool { return utf8.RuneCountInString(s) <= 10000 },
		"body must be at most 10000 characters"},
}

func nonEmpty(s string) bool { return s != "" }

// authenticated resolves the bearer token to a user, or answers 401.
func authenticated(store *Store, next func(http.ResponseWriter, *http.Request, int64)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || token == "" {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		user, err := store.UserFor(token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		next(w, r, user)
	})
}

func noteID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusNotFound, "note not found")
		return 0, false
	}
	return id, true
}

// field is one required string field of a request body and its rule.
type field struct {
	name    string
	valid   func(string) bool
	message string
}

// Problem is a 400 body; Field is null for malformed JSON.
type Problem struct {
	Error string  `json:"error"`
	Field *string `json:"field"`
}

// decode reads a JSON object and checks its fields in order, returning the first problem.
func decode(r *http.Request, fields []field) (map[string]string, *Problem) {
	content, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	var object map[string]json.RawMessage
	if err != nil || json.Unmarshal(content, &object) != nil || object == nil {
		return nil, &Problem{Error: "malformed JSON"}
	}
	values := map[string]string{}
	for _, f := range fields {
		var value string
		raw, present := object[f.name]
		if !present || json.Unmarshal(raw, &value) != nil || !f.valid(value) {
			return nil, &Problem{Error: f.message, Field: &f.name}
		}
		values[f.name] = value
	}
	return values, nil
}

func respond(w http.ResponseWriter, status int, value any, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		writeError(w, http.StatusNotFound, "note not found")
	case err != nil:
		serverError(w, err)
	default:
		writeJSON(w, status, value)
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func serverError(w http.ResponseWriter, err error) {
	log.Printf("error: %v", err)
	writeError(w, http.StatusInternalServerError, "internal error")
}
