// Command todo keeps a to-do list in a JSON file.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const usage = `Usage: todo <command> [options]

Commands:
  add <text...> [--priority low|normal|high]   Add an item
  list [--all] [--json]                        List open items
  done <id>                                    Mark an item done
  remove <id>                                  Delete an item

Options:
  --help       Show this help
  --version    Print the version
`

var commandHelp = map[string]string{
	"add":    "Usage: todo add <text...> [--priority low|normal|high]\n\n  -p, --priority   low, normal or high (default: default_priority)\n",
	"list":   "Usage: todo list [--all] [--json]\n\n  --all    Include done items\n  --json   Print a JSON array\n",
	"done":   "Usage: todo done <id>\n\nMarks an item done.\n",
	"remove": "Usage: todo remove <id>\n\nDeletes an item.\n",
}

// exitError carries an exit code and a message for standard error.
type exitError struct {
	code    int
	message string
}

func (e *exitError) Error() string { return e.message }

func usageError(format string, a ...any) error {
	return &exitError{2, fmt.Sprintf(format, a...)}
}

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		var exit *exitError
		if errors.As(err, &exit) {
			fmt.Fprintln(os.Stderr, "todo:", exit.message)
			os.Exit(exit.code)
		}
		fmt.Fprintln(os.Stderr, "todo:", err)
		os.Exit(4)
	}
}

func run(args []string, out io.Writer) error {
	if len(args) == 0 {
		return usageError("missing command; see todo --help")
	}
	switch args[0] {
	case "--help", "-h", "help":
		fmt.Fprint(out, usage)
		return nil
	case "--version":
		fmt.Fprintln(out, "todo 1.0.0")
		return nil
	}
	command, rest := args[0], args[1:]
	if _, ok := commandHelp[command]; !ok {
		return usageError("unknown command %q", command)
	}
	var priority string
	var all, asJSON bool
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	switch command {
	case "add":
		flags.StringVar(&priority, "priority", "", "")
		flags.StringVar(&priority, "p", "", "")
	case "list":
		flags.BoolVar(&all, "all", false, "")
		flags.BoolVar(&asJSON, "json", false, "")
	}
	positional, err := parseInterspersed(flags, rest)
	if errors.Is(err, flag.ErrHelp) {
		fmt.Fprint(out, commandHelp[command])
		return nil
	}
	if err != nil {
		return usageError("%v", err)
	}

	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	store := Store{Path: cfg.DataFile}

	switch command {
	case "add":
		if len(positional) == 0 {
			return usageError("add needs the text of the item")
		}
		p := cfg.DefaultPriority
		if priority != "" {
			if !validPriority(priority) {
				return usageError("invalid priority %q: use low, normal or high", priority)
			}
			p = priority
		}
		id, err := store.Add(strings.Join(positional, " "), p)
		if err != nil {
			return err
		}
		fmt.Fprintf(out, "added %d\n", id)
	case "list":
		if len(positional) != 0 {
			return usageError("list takes no arguments")
		}
		return list(out, store, all, asJSON)
	case "done", "remove":
		id, err := parseID(positional)
		if err != nil {
			return err
		}
		if command == "done" {
			err = store.Done(id)
		} else {
			err = store.Remove(id)
		}
		if err != nil {
			return err
		}
		verb := map[string]string{"done": "done", "remove": "removed"}[command]
		fmt.Fprintf(out, "%s %d\n", verb, id)
	}
	return nil
}

// parseInterspersed parses flags that may come before, between or after the positional arguments.
func parseInterspersed(flags *flag.FlagSet, args []string) ([]string, error) {
	var positional []string
	for {
		if err := flags.Parse(args); err != nil {
			return nil, err
		}
		args = flags.Args()
		if len(args) == 0 {
			return positional, nil
		}
		positional = append(positional, args[0])
		args = args[1:]
	}
}

func parseID(positional []string) (int, error) {
	if len(positional) != 1 {
		return 0, usageError("expected exactly one id")
	}
	id, err := strconv.Atoi(positional[0])
	if err != nil || id < 1 {
		return 0, usageError("invalid id %q", positional[0])
	}
	return id, nil
}

func list(out io.Writer, store Store, all, asJSON bool) error {
	data, err := store.Load()
	if err != nil {
		return err
	}
	items := make([]Item, 0, len(data.Items))
	for _, item := range data.Items {
		if all || !item.Done {
			items = append(items, item)
		}
	}
	if asJSON {
		encoded, err := json.Marshal(items)
		if err != nil {
			return err
		}
		fmt.Fprintln(out, string(encoded))
		return nil
	}
	for _, item := range items {
		mark := " "
		if item.Done {
			mark = "x"
		}
		fmt.Fprintf(out, "%d [%s] %s %s\n", item.ID, mark, item.Priority, item.Text)
	}
	return nil
}
