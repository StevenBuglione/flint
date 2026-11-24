package main

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib" // database/sql over pgx
)

//go:embed schema.sql
var schemaSQL string

//go:embed data.sql
var dataSQL string

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC | log.Lmicroseconds)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx); err != nil {
		log.Printf("ERROR %v", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	started := time.Now()
	db, err := openDatabase()
	if err != nil {
		return err
	}
	defer db.Close()
	for _, script := range []string{schemaSQL, dataSQL} { // spring.sql.init.mode=always
		if err := executeScript(ctx, db, script); err != nil {
			return err
		}
	}

	listener, err := net.Listen("tcp", ":"+env("SERVER_PORT", "9966"))
	if err != nil {
		return err
	}
	server := &http.Server{
		Handler:           container(routes(&clinic{db: db})),
		ReadHeaderTimeout: 20 * time.Second, // Tomcat's connectionTimeout
	}
	served := make(chan error, 1)
	// ADR-033: Tomcat's 400 carries no reason phrase.
	go func() { served <- server.Serve(parityListener{listener, []int{http.StatusBadRequest}}) }()
	log.Printf("INFO petclinic-rest listening on %s (context path %s) after %s", listener.Addr(), contextPath,
		time.Since(started).Round(time.Millisecond))

	select {
	case err := <-served:
		return err
	case <-ctx.Done():
	}
	shutdown, cancel := context.WithTimeout(context.Background(), 30*time.Second) // server.shutdown=graceful
	defer cancel()
	if err := server.Shutdown(shutdown); err != nil {
		return err
	}
	if err := <-served; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// openDatabase opens the pool from the reference's settings: POSTGRES_URL is a JDBC URL
// (jdbc:postgresql://host[:port]/database), with POSTGRES_USER and POSTGRES_PASS.
func openDatabase() (*sql.DB, error) {
	jdbc := env("POSTGRES_URL", "jdbc:postgresql://localhost/petclinic")
	rest, found := strings.CutPrefix(jdbc, "jdbc:postgresql://")
	if !found {
		return nil, fmt.Errorf("POSTGRES_URL %q is not a jdbc:postgresql:// URL", jdbc)
	}
	parsed, err := url.Parse("postgres://" + rest)
	if err != nil {
		return nil, fmt.Errorf("POSTGRES_URL: %w", err)
	}
	parsed.User = url.UserPassword(env("POSTGRES_USER", "petclinic"), env("POSTGRES_PASS", "petclinic"))
	query := url.Values{}
	if mode := parsed.Query().Get("sslmode"); mode != "" { // the one JDBC parameter pgx shares
		query.Set("sslmode", mode)
	}
	parsed.RawQuery = query.Encode()
	config, err := pgx.ParseConfig(parsed.String())
	if err != nil {
		return nil, err
	}
	validation := newHikariValidation()
	db := stdlib.OpenDB(*config, stdlib.OptionAfterConnect(validation.connected),
		stdlib.OptionShouldPing(validation.borrowed))
	// HikariCP's defaults: a fixed pool of 10 connections, replaced after 30 minutes.
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(30 * time.Minute)
	return db, nil
}

// executeScript runs a SQL script statement by statement, as Spring's ScriptUtils does: statements end at a
// semicolon outside quotes and comments.
func executeScript(ctx context.Context, db *sql.DB, script string) error {
	for _, statement := range splitScript(script) {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("executing %q: %w", statement, err)
		}
	}
	return nil
}

func splitScript(script string) []string {
	var statements []string
	var current strings.Builder
	flush := func() {
		if s := strings.TrimSpace(current.String()); s != "" {
			statements = append(statements, s)
		}
		current.Reset()
	}
	// skipTo returns the index of the last byte of the first terminator at or after from, or the script's end.
	skipTo := func(from int, terminator string) int {
		if end := strings.Index(script[from:], terminator); end >= 0 {
			return from + end + len(terminator) - 1
		}
		return len(script) - 1
	}
	for i := 0; i < len(script); i++ {
		switch c := script[i]; {
		case c == '\'' || c == '"':
			end := skipTo(i+1, string(c))
			current.WriteString(script[i : end+1])
			i = end
		case strings.HasPrefix(script[i:], "--"):
			i = skipTo(i, "\n")
			current.WriteByte(' ')
		case strings.HasPrefix(script[i:], "/*"):
			i = skipTo(i+2, "*/")
			current.WriteByte(' ')
		case c == ';':
			flush()
		default:
			current.WriteByte(c)
		}
	}
	flush()
	return statements
}

// hikariValidation reproduces HikariCP's check on borrowing a connection (ADR-032: the comparator sends the
// reference's SQL): a connection unused for longer than aliveBypassWindowMs (500 ms) is validated with
// Connection.isValid, which pgjdbc sends as an empty query. pgx's own check (a "-- ping" after 1 s idle) is
// replaced. A new connection counts as just used, as Hikari's does; a failed validation lets pgx ping and discard it.
type hikariValidation struct {
	sync.Mutex
	lastUsed map[*pgx.Conn]time.Time
}

const aliveBypassWindow = 500 * time.Millisecond

func newHikariValidation() *hikariValidation {
	return &hikariValidation{lastUsed: map[*pgx.Conn]time.Time{}}
}

func (h *hikariValidation) connected(_ context.Context, conn *pgx.Conn) error {
	h.Lock()
	h.lastUsed[conn] = time.Now()
	h.Unlock()
	return nil
}

func (h *hikariValidation) borrowed(ctx context.Context, params stdlib.ShouldPingParams) bool {
	now := time.Now()
	h.Lock()
	last, known := h.lastUsed[params.Conn]
	h.lastUsed[params.Conn] = now
	h.Unlock()
	if known && now.Sub(last) <= aliveBypassWindow {
		return false
	}
	_, err := params.Conn.Exec(ctx, "")
	return err != nil
}
