# Notes REST API with login

Build an HTTP service that stores notes for registered users in SQLite.

## Running

- The service listens on `127.0.0.1` at the port in the `PORT` environment variable (default 8080).
- It stores everything in the SQLite database file named by `DATABASE_PATH` (default `notes.db`), and creates the file if it is missing.
- On startup it applies the schema as versioned migrations kept in the project. It must also start against a database that an earlier run of the same program created, keeping its data.
- Passwords are never stored in plain text.
- All request and response bodies are JSON with `Content-Type: application/json`.

## Endpoints

| Method and path | Body | Success | Errors |
| --- | --- | --- | --- |
| `POST /api/users` | `{"username": "...", "password": "..."}` | 201 `{"id": <int>, "username": "..."}` | 400 invalid, 409 username taken |
| `POST /api/login` | `{"username": "...", "password": "..."}` | 200 `{"token": "..."}` | 400 invalid, 401 wrong credentials |
| `GET /api/notes` | none | 200 `[note, ...]`: the caller's notes, oldest first | 401 |
| `POST /api/notes` | `{"title": "...", "body": "..."}` | 201 note | 400 invalid, 401 |
| `GET /api/notes/{id}` | none | 200 note | 401, 404 |
| `PUT /api/notes/{id}` | `{"title": "...", "body": "..."}` | 200 note | 400 invalid, 401, 404 |
| `DELETE /api/notes/{id}` | none | 204, empty body | 401, 404 |

A note is `{"id": <int>, "title": "...", "body": "..."}`.

## Rules

- Validation:
  - `username`: 3 to 32 characters from `a-z`, `0-9` and `_`;
  - `password`: at least 8 characters;
  - `title`: 1 to 100 characters;
  - `body`: at most 10000 characters and may be empty.
  A missing field, a wrong type or malformed JSON is invalid.
- An invalid request gets 400 with a JSON body `{"error": "...", "field": "<name>"}` naming the first invalid field, or `"field": null` for malformed JSON.
- `/api/notes` requires `Authorization: Bearer <token>` with a token from `/api/login`. A token stays valid across restarts of the service.
- A user only ever sees their own notes. Another user's note is 404, exactly like a note that does not exist.
- Every other error body is `{"error": "..."}`.
