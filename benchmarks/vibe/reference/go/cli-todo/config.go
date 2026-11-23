package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"
)

// Config is the [todo] table of the configuration file.
type Config struct {
	DataFile        string `toml:"data_file"`
	DefaultPriority string `toml:"default_priority"`
}

func validPriority(p string) bool {
	return p == "low" || p == "normal" || p == "high"
}

func configError(format string, a ...any) error {
	return &exitError{3, fmt.Sprintf(format, a...)}
}

func loadConfig() (Config, error) {
	home, _ := os.UserHomeDir()
	cfg := Config{
		DataFile:        filepath.Join(home, ".local", "share", "todo", "todos.json"),
		DefaultPriority: "normal",
	}
	path := os.Getenv("TODO_CONFIG")
	if path == "" {
		path = filepath.Join(home, ".config", "todo", "config.toml")
	}
	var file struct {
		Todo Config `toml:"todo"`
	}
	file.Todo = cfg
	meta, err := toml.DecodeFile(path, &file)
	if errors.Is(err, fs.ErrNotExist) {
		return cfg, nil
	}
	if err != nil {
		return cfg, configError("%s: %v", path, err)
	}
	if undecoded := meta.Undecoded(); len(undecoded) > 0 {
		keys := make([]string, len(undecoded))
		for i, key := range undecoded {
			keys[i] = key.String()
		}
		return cfg, configError("%s: unknown key %s", path, strings.Join(keys, ", "))
	}
	if !validPriority(file.Todo.DefaultPriority) {
		return cfg, configError("%s: default_priority must be low, normal or high, not %q", path, file.Todo.DefaultPriority)
	}
	if file.Todo.DataFile == "" {
		return cfg, configError("%s: data_file must not be empty", path)
	}
	return file.Todo, nil
}
