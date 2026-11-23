package main

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

// ErrNotFound is a missing row, or a row that belongs to another user.
var ErrNotFound = errors.New("not found")

// ErrTaken is a username that is already registered.
var ErrTaken = errors.New("username taken")

// Note is a note as the API returns it.
type Note struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	Body  string `json:"body"`
}

// Store holds the users, tokens and notes.
type Store struct {
	db *sql.DB
}

func (s *Store) Register(username, password string) (int64, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return 0, err
	}
	result, err := s.db.Exec(`INSERT INTO users (username, password_hash) VALUES (?, ?)`, username, string(hash))
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return 0, ErrTaken
		}
		return 0, err
	}
	return result.LastInsertId()
}

// Login checks the credentials and issues a token; only the token's SHA-256 is stored.
func (s *Store) Login(username, password string) (string, error) {
	var id int64
	var hash string
	err := s.db.QueryRow(`SELECT id, password_hash FROM users WHERE username = ?`, username).Scan(&id, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", ErrNotFound
	}
	secret := make([]byte, 32)
	rand.Read(secret)
	token := hex.EncodeToString(secret)
	if _, err := s.db.Exec(`INSERT INTO tokens (token_hash, user_id) VALUES (?, ?)`, digest(token), id); err != nil {
		return "", err
	}
	return token, nil
}

// UserFor returns the user a token belongs to.
func (s *Store) UserFor(token string) (int64, error) {
	var id int64
	err := s.db.QueryRow(`SELECT user_id FROM tokens WHERE token_hash = ?`, digest(token)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNotFound
	}
	return id, err
}

func digest(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) Notes(user int64) ([]Note, error) {
	rows, err := s.db.Query(`SELECT id, title, body FROM notes WHERE user_id = ? ORDER BY id`, user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	notes := []Note{}
	for rows.Next() {
		var note Note
		if err := rows.Scan(&note.ID, &note.Title, &note.Body); err != nil {
			return nil, err
		}
		notes = append(notes, note)
	}
	return notes, rows.Err()
}

func (s *Store) Note(user, id int64) (Note, error) {
	note := Note{ID: id}
	err := s.db.QueryRow(`SELECT title, body FROM notes WHERE id = ? AND user_id = ?`, id, user).
		Scan(&note.Title, &note.Body)
	if errors.Is(err, sql.ErrNoRows) {
		return note, ErrNotFound
	}
	return note, err
}

func (s *Store) CreateNote(user int64, title, body string) (Note, error) {
	result, err := s.db.Exec(`INSERT INTO notes (user_id, title, body) VALUES (?, ?, ?)`, user, title, body)
	if err != nil {
		return Note{}, err
	}
	id, err := result.LastInsertId()
	return Note{ID: id, Title: title, Body: body}, err
}

func (s *Store) UpdateNote(user, id int64, title, body string) (Note, error) {
	result, err := s.db.Exec(`UPDATE notes SET title = ?, body = ? WHERE id = ? AND user_id = ?`, title, body, id, user)
	if err != nil {
		return Note{}, err
	}
	if changed, _ := result.RowsAffected(); changed == 0 {
		return Note{}, ErrNotFound
	}
	return Note{ID: id, Title: title, Body: body}, nil
}

func (s *Store) DeleteNote(user, id int64) error {
	result, err := s.db.Exec(`DELETE FROM notes WHERE id = ? AND user_id = ?`, id, user)
	if err != nil {
		return err
	}
	if changed, _ := result.RowsAffected(); changed == 0 {
		return ErrNotFound
	}
	return nil
}
