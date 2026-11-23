package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// Item is one to-do item.
type Item struct {
	ID       int    `json:"id"`
	Text     string `json:"text"`
	Priority string `json:"priority"`
	Done     bool   `json:"done"`
}

// Data is the content of the data file. NextID keeps ids from being reused after a removal.
type Data struct {
	NextID int    `json:"next_id"`
	Items  []Item `json:"items"`
}

// Store reads and writes the data file.
type Store struct {
	Path string
}

func notFound(id int) error {
	return &exitError{1, fmt.Sprintf("no item with id %d", id)}
}

func (s Store) Load() (Data, error) {
	data := Data{NextID: 1}
	content, err := os.ReadFile(s.Path)
	if errors.Is(err, fs.ErrNotExist) {
		return data, nil
	}
	if err != nil {
		return data, err
	}
	if err := json.Unmarshal(content, &data); err != nil {
		return data, fmt.Errorf("%s: %w", s.Path, err)
	}
	return data, nil
}

// Save writes the data file atomically, creating its directory.
func (s Store) Save(data Data) error {
	if err := os.MkdirAll(filepath.Dir(s.Path), 0o755); err != nil {
		return err
	}
	content, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	temporary := s.Path + ".tmp"
	if err := os.WriteFile(temporary, append(content, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(temporary, s.Path)
}

func (s Store) Add(text, priority string) (int, error) {
	data, err := s.Load()
	if err != nil {
		return 0, err
	}
	id := data.NextID
	data.Items = append(data.Items, Item{ID: id, Text: text, Priority: priority})
	data.NextID++
	return id, s.Save(data)
}

func (s Store) Done(id int) error {
	return s.update(id, func(data *Data, index int) { data.Items[index].Done = true })
}

func (s Store) Remove(id int) error {
	return s.update(id, func(data *Data, index int) {
		data.Items = append(data.Items[:index], data.Items[index+1:]...)
	})
}

func (s Store) update(id int, change func(*Data, int)) error {
	data, err := s.Load()
	if err != nil {
		return err
	}
	for index, item := range data.Items {
		if item.ID == id {
			change(&data, index)
			return s.Save(data)
		}
	}
	return notFound(id)
}
