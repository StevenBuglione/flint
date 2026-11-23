// Command gs-rest-service is the Go comparator for the Spring guide of the same name (ADR-030 section 8):
// GET /greeting returns {"id":N,"content":"Hello, <name>!"} with a request counter, and the responses Spring MVC
// gives around it (406, 405, OPTIONS, HEAD and Boot's JSON and Whitelabel error bodies) are reproduced, so the
// black-box suite in benchmarks/spring/suites scores it like the Java reference.
//
// It is written the way a Go developer would write the service with the standard library only.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

type greeting struct {
	ID      int64  `json:"id"`
	Content string `json:"content"`
}

// errorBody is Spring Boot's default error attributes (BasicErrorController).
type errorBody struct {
	Timestamp string `json:"timestamp"`
	Status    int    `json:"status"`
	Error     string `json:"error"`
	Path      string `json:"path"`
}

const whitelabel = "<html><body><h1>Whitelabel Error Page</h1><p>This application has no explicit mapping for " +
	"/error, so you are seeing this as a fallback.</p><div id='created'>%s</div><div>There was an unexpected " +
	"error (type=%s, status=%d).</div></body></html>"

type server struct {
	counter atomic.Int64
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(value)
}

// acceptsJSON reports whether an Accept header admits application/json, as Spring's content negotiation does.
func acceptsJSON(accept string) bool {
	if accept == "" {
		return true
	}
	for _, item := range strings.Split(accept, ",") {
		mediaType := strings.TrimSpace(strings.SplitN(item, ";", 2)[0])
		switch mediaType {
		case "*/*", "application/*", "application/json", "application/*+json":
			return true
		}
	}
	return false
}

func wantsHTML(accept string) bool {
	for _, item := range strings.Split(accept, ",") {
		if strings.TrimSpace(strings.SplitN(item, ";", 2)[0]) == "text/html" {
			return true
		}
	}
	return false
}

func writeError(w http.ResponseWriter, r *http.Request, status int) {
	now := time.Now()
	if wantsHTML(r.Header.Get("Accept")) {
		w.Header().Set("Content-Type", "text/html;charset=UTF-8")
		w.Header().Set("Content-Language", "en-US")
		w.WriteHeader(status)
		created := now.UTC().Format("Mon Jan 02 15:04:05 MST 2006")
		_, _ = w.Write([]byte(fmt.Sprintf(whitelabel, created, http.StatusText(status), status)))
		return
	}
	writeJSON(w, status, errorBody{
		Timestamp: now.UTC().Format("2006-01-02T15:04:05.000Z07:00"),
		Status:    status,
		Error:     http.StatusText(status),
		Path:      r.URL.Path,
	})
}

func (s *server) greeting(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet, http.MethodHead:
	case http.MethodOptions:
		w.Header().Set("Allow", "GET,HEAD,OPTIONS")
		w.Header().Set("Accept-Patch", "")
		w.Header().Set("Accept-Query", "")
		w.Header().Set("Content-Length", "0")
		w.WriteHeader(http.StatusOK)
		return
	default:
		w.Header().Set("Allow", "GET")
		writeError(w, r, http.StatusMethodNotAllowed)
		return
	}
	// Spring invokes the handler before it negotiates the response type, so a 406 still consumes an id.
	id := s.counter.Add(1)
	if !acceptsJSON(r.Header.Get("Accept")) {
		w.Header().Set("Accept", "application/json, application/*+json")
		w.Header().Set("Content-Length", "0")
		w.WriteHeader(http.StatusNotAcceptable)
		return
	}
	name := strings.Join(r.URL.Query()["name"], ",")
	if name == "" {
		name = "World"
	}
	writeJSON(w, http.StatusOK, greeting{ID: id, Content: "Hello, " + name + "!"})
}

func notFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, r, http.StatusNotFound)
}

func main() {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}
	s := &server{}
	mux := http.NewServeMux()
	mux.HandleFunc("/greeting", s.greeting)
	mux.HandleFunc("/", notFound)
	httpServer := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 10 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdown)
	}()
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
