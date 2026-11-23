// Command worker processes jobs from a spool-directory queue with bounded concurrency.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

func main() {
	flags := flag.NewFlagSet("worker", flag.ContinueOnError)
	spool := flags.String("spool", "", "the spool directory (required)")
	concurrency := flags.Int("concurrency", 4, "jobs run at the same time, 1 to 64")
	if err := flags.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}
	if *spool == "" || flags.NArg() > 0 {
		fmt.Fprintln(os.Stderr, "usage: worker --spool <dir> [--concurrency <n>]")
		os.Exit(2)
	}
	if *concurrency < 1 || *concurrency > 64 {
		fmt.Fprintln(os.Stderr, "worker: --concurrency must be from 1 to 64")
		os.Exit(2)
	}
	queue := Queue{Root: *spool}
	if err := queue.Create(); err != nil {
		fmt.Fprintln(os.Stderr, "worker:", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	run(ctx, queue, *concurrency, log.New(os.Stdout, "", 0))
}

// run polls the incoming directory until ctx is cancelled, then waits for the jobs it started.
func run(ctx context.Context, queue Queue, concurrency int, logger *log.Logger) {
	slots := make(chan struct{}, concurrency)
	var running sync.WaitGroup
	var mu sync.Mutex
	inFlight := map[string]bool{}

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		for _, name := range queue.Pending() {
			mu.Lock()
			busy := inFlight[name]
			inFlight[name] = true
			mu.Unlock()
			if busy {
				continue
			}
			select {
			case slots <- struct{}{}:
			case <-ctx.Done():
				running.Wait()
				return
			}
			running.Add(1)
			go func() {
				defer running.Done()
				queue.Process(name, logger)
				mu.Lock()
				delete(inFlight, name)
				mu.Unlock()
				<-slots
			}()
		}
		select {
		case <-ticker.C:
		case <-ctx.Done():
			running.Wait()
			return
		}
	}
}

// Queue is the spool directory.
type Queue struct {
	Root string
}

func (q Queue) dir(name string) string { return filepath.Join(q.Root, name) }

// Create makes the incoming, done and failed directories.
func (q Queue) Create() error {
	for _, name := range []string{"incoming", "done", "failed"} {
		if err := os.MkdirAll(q.dir(name), 0o755); err != nil {
			return err
		}
	}
	return nil
}

// Pending lists the job files in incoming, skipping temporary files that start with a dot.
func (q Queue) Pending() []string {
	entries, err := os.ReadDir(q.dir("incoming"))
	if err != nil {
		return nil
	}
	var names []string
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, ".") && strings.HasSuffix(name, ".json") && entry.Type().IsRegular() {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

// Process runs one job file and records its result in done or failed, then deletes it.
func (q Queue) Process(file string, logger *log.Logger) {
	incoming := filepath.Join(q.dir("incoming"), file)
	started := time.Now()
	content, err := os.ReadFile(incoming)
	if err != nil {
		return // already taken
	}
	id, result, err := Execute(content)
	if err != nil {
		name := strings.TrimSuffix(file, ".json")
		record := map[string]any{"file": file, "error": err.Error()}
		if writeErr := writeJSON(q.dir("failed"), name+".json", record); writeErr != nil {
			logger.Printf("error %s: %v", file, writeErr)
			return
		}
		os.Remove(incoming)
		logger.Printf("failed %s: %v", name, err)
		return
	}
	if err := writeJSON(q.dir("done"), id+".json", map[string]any{"id": id, "result": result}); err != nil {
		logger.Printf("error %s: %v", file, err)
		return
	}
	os.Remove(incoming)
	logger.Printf("done %s %dms", id, time.Since(started).Milliseconds())
}
