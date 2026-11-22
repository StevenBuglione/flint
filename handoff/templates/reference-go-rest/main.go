package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const jsonBody = `{"message":"hello","n":42}`

func handler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	switch r.URL.Path {
	case "/health":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("ok\n"))
	case "/json":
		w.Header().Set("Content-Type", "application/json")
		body, err := json.Marshal(struct {
			Message string `json:"message"`
			N       int    `json:"n"`
		}{"hello", 42})
		if err != nil {
			http.Error(w, "encoding failed", 500)
			return
		}
		_, _ = w.Write(body)
	default:
		http.NotFound(w, r)
	}
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8081", "HTTP listen address")
	flag.Parse()
	server := &http.Server{
		Addr: *listen, Handler: http.HandlerFunc(handler),
		ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 5 * time.Second,
		IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192,
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		<-ctx.Done()
		deadline, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		if err := server.Shutdown(deadline); err != nil {
			_ = server.Close()
		}
	}()
	err := server.ListenAndServe()
	cancel()
	<-finished
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
