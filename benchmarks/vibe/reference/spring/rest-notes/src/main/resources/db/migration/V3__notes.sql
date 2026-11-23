CREATE TABLE notes (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    title   TEXT    NOT NULL,
    body    TEXT    NOT NULL
);
CREATE INDEX notes_by_user ON notes(user_id, id);
