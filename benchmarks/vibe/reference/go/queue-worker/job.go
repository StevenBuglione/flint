package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var validID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// Job is a job file. The pointers tell a missing field from an empty one.
type Job struct {
	ID    *string          `json:"id"`
	Op    *string          `json:"op"`
	Input *json.RawMessage `json:"input"`
}

// Execute validates and runs a job; it returns the job's id and result.
func Execute(content []byte) (string, any, error) {
	var job Job
	if err := json.Unmarshal(content, &job); err != nil {
		return "", nil, fmt.Errorf("invalid JSON: %v", err)
	}
	if job.ID == nil || job.Op == nil || job.Input == nil {
		return "", nil, errors.New("a job needs id, op and input")
	}
	if !validID.MatchString(*job.ID) {
		return "", nil, fmt.Errorf("invalid id %q", *job.ID)
	}
	switch *job.Op {
	case "sha256", "wordcount":
		var input string
		if err := json.Unmarshal(*job.Input, &input); err != nil {
			return "", nil, fmt.Errorf("%s needs a string input", *job.Op)
		}
		if *job.Op == "sha256" {
			sum := sha256.Sum256([]byte(input))
			return *job.ID, hex.EncodeToString(sum[:]), nil
		}
		return *job.ID, len(strings.Fields(input)), nil
	case "sleep":
		var milliseconds float64
		if err := json.Unmarshal(*job.Input, &milliseconds); err != nil || milliseconds < 0 || milliseconds > 10000 {
			return "", nil, errors.New("sleep needs a number of milliseconds from 0 to 10000")
		}
		time.Sleep(time.Duration(milliseconds * float64(time.Millisecond)))
		return *job.ID, nil, nil
	default:
		return "", nil, fmt.Errorf("unknown op %q", *job.Op)
	}
}

// writeJSON writes dir/name atomically through a temporary name that starts with a dot.
func writeJSON(dir, name string, value any) error {
	content, err := json.Marshal(value)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(dir, "."+name+".*")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if _, err := temporary.Write(append(content, '\n')); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporary.Name(), filepath.Join(dir, name))
}
