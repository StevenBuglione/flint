package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Metric is one named value, in the order it was first seen.
type Metric struct {
	Name  string
	Value float64
}

// Board is the dashboard's state.
type Board struct {
	Title    string
	Metrics  []Metric
	index    map[string]int
	Skipped  int
	Sorted   bool
	Selected int
}

// Apply takes one line of the file: a metric, a blank line, or a skipped line.
func (b *Board) Apply(line []byte) {
	var record struct {
		Name  *string  `json:"name"`
		Value *float64 `json:"value"`
	}
	if len(bytes.TrimSpace(line)) == 0 {
		return
	}
	if json.Unmarshal(line, &record) != nil || record.Name == nil || record.Value == nil {
		b.Skipped++
		return
	}
	if b.index == nil {
		b.index = map[string]int{}
	}
	if i, ok := b.index[*record.Name]; ok {
		b.Metrics[i].Value = *record.Value
		return
	}
	b.index[*record.Name] = len(b.Metrics)
	b.Metrics = append(b.Metrics, Metric{*record.Name, *record.Value})
}

// Move changes the selection by delta rows.
func (b *Board) Move(delta int) {
	b.Selected = max(0, min(len(b.Metrics)-1, b.Selected+delta))
}

// Rows are the metrics in display order.
func (b *Board) Rows() []Metric {
	rows := append([]Metric(nil), b.Metrics...)
	if b.Sorted {
		sort.SliceStable(rows, func(i, j int) bool { return rows[i].Value > rows[j].Value })
	}
	return rows
}

// FormatValue prints a value with up to two decimals: 3, 2.5, 0.33.
func FormatValue(v float64) string {
	return strconv.FormatFloat(math.Round(v*100)/100, 'f', -1, 64)
}

// Draw paints the whole screen.
func (b *Board) Draw(out io.Writer, width, height int) {
	fmt.Fprint(out, "\x1b[H\x1b[2J")
	fmt.Fprintf(out, "\x1b[1;1H\x1b[1m%s\x1b[0m", fit("Dashboard — "+b.Title, width))
	rows := b.Rows()
	visible := max(height-2, 1)
	first := max(0, b.Selected-visible+1)
	for line := 0; line < visible && first+line < len(rows); line++ {
		i := first + line
		value := FormatValue(rows[i].Value)
		nameWidth := max(width-len(value)-3, 1)
		text := fmt.Sprintf(" %-*s %s ", nameWidth, fit(rows[i].Name, nameWidth), value)
		if i == b.Selected {
			text = "\x1b[7m" + text + "\x1b[0m"
		}
		fmt.Fprintf(out, "\x1b[%d;1H%s", line+2, text)
	}
	footer := fmt.Sprintf("%d metrics, %d skipped — q quits, s sorts", len(b.Metrics), b.Skipped)
	fmt.Fprintf(out, "\x1b[%d;1H%s", height, fit(footer, width))
}

func fit(text string, width int) string {
	if utf8.RuneCountInString(text) <= width {
		return text
	}
	return string([]rune(text)[:max(width, 0)])
}

// Feed follows the source file, keeping a partial last line until it is complete.
type Feed struct {
	file    *os.File
	partial []byte
}

func OpenFeed(path string) (*Feed, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	return &Feed{file: file}, nil
}

func (f *Feed) Close() error { return f.file.Close() }

// Read applies the lines appended since the last call; it reports whether any arrived.
func (f *Feed) Read(board *Board) bool {
	data, err := io.ReadAll(f.file)
	if err != nil || len(data) == 0 {
		return false
	}
	data = append(f.partial, data...)
	end := bytes.LastIndexByte(data, '\n')
	f.partial = append([]byte(nil), data[end+1:]...)
	scanner := bufio.NewScanner(bytes.NewReader(data[:end+1]))
	scanner.Buffer(nil, len(data)+1)
	for scanner.Scan() {
		board.Apply(scanner.Bytes())
	}
	return end >= 0
}

// Key is a decoded key press.
type Key int

const (
	KeyNone Key = iota
	KeyQuit
	KeyUp
	KeyDown
	KeySort
)

// readKeys decodes raw terminal input into keys.
func readKeys(in io.Reader, keys chan<- Key) {
	buffer := make([]byte, 64)
	for {
		n, err := in.Read(buffer)
		if err != nil {
			keys <- KeyQuit
			return
		}
		input := string(buffer[:n])
		for len(input) > 0 {
			key, size := decode(input)
			if key != KeyNone {
				keys <- key
			}
			input = input[size:]
		}
	}
}

func decode(input string) (Key, int) {
	switch {
	case strings.HasPrefix(input, "\x1b[A"), strings.HasPrefix(input, "\x1bOA"):
		return KeyUp, 3
	case strings.HasPrefix(input, "\x1b[B"), strings.HasPrefix(input, "\x1bOB"):
		return KeyDown, 3
	case strings.HasPrefix(input, "\x1b["):
		return KeyNone, 3
	}
	switch input[0] {
	case 'q', 0x1b, 0x03:
		return KeyQuit, 1
	case 'k':
		return KeyUp, 1
	case 'j':
		return KeyDown, 1
	case 's':
		return KeySort, 1
	}
	return KeyNone, 1
}
