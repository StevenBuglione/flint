package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
)

func main() {
	name := flag.String("name", "world", "Name to greet")
	flag.Parse()
	data, err := os.ReadFile("application.json")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(3)
	}
	var settings struct {
		Hello struct {
			Greeting string `json:"greeting"`
		} `json:"hello"`
	}
	if err = json.Unmarshal(data, &settings); err != nil || settings.Hello.Greeting == "" {
		fmt.Fprintln(os.Stderr, "invalid greeting configuration")
		os.Exit(3)
	}
	fmt.Printf("%s, %s!\n", settings.Hello.Greeting, *name)
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	logger.Info("greeting completed")
}
