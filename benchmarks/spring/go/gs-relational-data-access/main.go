// Command gs-relational-data-access is the Go comparator for the Spring guide of the same name (ADR-030 section
// 8): it creates a customers table in an in-memory database, batch-inserts four customers, queries the two named
// Josh and logs each step, then exits.
//
// The guide uses H2, which Go cannot reach; SQLite in memory is the embedded database a Go developer would pick,
// through database/sql and the pure-Go modernc.org/sqlite driver. Log lines use Spring Boot's console pattern, the
// observable contract of the black-box suite in benchmarks/spring/suites.
package main

import (
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const logger = "c.e.r.RelationalDataAccessApplication"

var pid = os.Getpid()

// info writes one line in Spring Boot's default console pattern.
func info(format string, args ...any) {
	stamp := time.Now().UTC().Format("2006-01-02T15:04:05.000Z07:00")
	fmt.Printf("%s  INFO %d --- [%15.15s] %-40.40s : %s\n", stamp, pid, "main", logger, fmt.Sprintf(format, args...))
}

type customer struct {
	id        int64
	firstName string
	lastName  string
}

func (c customer) String() string {
	return fmt.Sprintf("Customer[id=%d, firstName='%s', lastName='%s']", c.id, c.firstName, c.lastName)
}

func run(db *sql.DB) error {
	info("Creating tables")
	if _, err := db.Exec("DROP TABLE IF EXISTS customers"); err != nil {
		return err
	}
	if _, err := db.Exec("CREATE TABLE customers(id INTEGER PRIMARY KEY, first_name VARCHAR(255), last_name VARCHAR(255))"); err != nil {
		return err
	}

	var names [][]string
	for _, name := range []string{"John Woo", "Jeff Dean", "Josh Bloch", "Josh Long"} {
		names = append(names, strings.Split(name, " "))
	}
	for _, name := range names {
		info("Inserting customer record for %s %s", name[0], name[1])
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	insert, err := tx.Prepare("INSERT INTO customers(first_name, last_name) VALUES (?,?)")
	if err != nil {
		_ = tx.Rollback()
		return err
	}
	for _, name := range names {
		if _, err := insert.Exec(name[0], name[1]); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	if err := insert.Close(); err != nil {
		_ = tx.Rollback()
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	info("Querying for customer records where first_name = 'Josh':")
	rows, err := db.Query("SELECT id, first_name, last_name FROM customers WHERE first_name = ?", "Josh")
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var c customer
		if err := rows.Scan(&c.id, &c.firstName, &c.lastName); err != nil {
			return err
		}
		info("%s", c)
	}
	return rows.Err()
}

func main() {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	// Each connection to ":memory:" is its own database, so the pool holds exactly one.
	db.SetMaxOpenConns(1)
	err = run(db)
	if closeErr := db.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
