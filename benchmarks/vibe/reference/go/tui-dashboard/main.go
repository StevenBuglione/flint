// Command dash is a full-screen dashboard of the metrics in a JSON-lines file, following the file as it grows.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/term"
)

func main() {
	flags := flag.NewFlagSet("dash", flag.ContinueOnError)
	source := flags.String("source", "", "the metrics file (required)")
	if err := flags.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}
	if *source == "" {
		fmt.Fprintln(os.Stderr, "usage: dash --source <file>")
		os.Exit(2)
	}
	feed, err := OpenFeed(*source)
	if err != nil {
		fmt.Fprintln(os.Stderr, "dash:", err)
		os.Exit(2)
	}
	defer feed.Close()
	if err := run(feed, filepath.Base(*source)); err != nil {
		fmt.Fprintln(os.Stderr, "dash:", err)
		os.Exit(1)
	}
}

func run(feed *Feed, title string) error {
	in, out := int(os.Stdin.Fd()), bufio.NewWriter(os.Stdout)
	saved, err := term.MakeRaw(in)
	if err != nil {
		return err
	}
	defer term.Restore(in, saved)
	out.WriteString("\x1b[?1049h\x1b[?25l")
	defer func() {
		out.WriteString("\x1b[0m\x1b[?25h\x1b[?1049l")
		out.Flush()
	}()

	signals := make(chan os.Signal, 4)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGWINCH)
	keys := make(chan Key, 16)
	go readKeys(os.Stdin, keys)
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	board := &Board{Title: title}
	feed.Read(board)
	dirty := true
	for {
		if dirty {
			width, height, err := term.GetSize(int(os.Stdout.Fd()))
			if err != nil {
				width, height = 80, 24
			}
			board.Draw(out, width, height)
			out.Flush()
		}
		select {
		case key := <-keys:
			switch key {
			case KeyQuit:
				return nil
			case KeyUp:
				board.Move(-1)
			case KeyDown:
				board.Move(1)
			case KeySort:
				board.Sorted = !board.Sorted
			}
			dirty = true
		case sig := <-signals:
			if sig != syscall.SIGWINCH {
				return nil
			}
			dirty = true
		case <-ticker.C:
			dirty = feed.Read(board)
		}
	}
}
