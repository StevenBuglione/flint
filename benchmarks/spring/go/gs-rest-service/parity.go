package main

// HTTP parity on the gated error paths (ADR-033, owner decision 118b4482): the comparator matches the Java
// reference's framing, connection lifetime and reason phrase there. Tomcat sends no reason phrase, while net/http
// always writes the status text, so the listener's connections drop it from the status line of the gated statuses
// as it is written. How the bytes are produced stays free.

import (
	"net"
	"net/http"
)

// parityListener wraps each accepted connection so the status line of a gated status goes out without its reason.
type parityListener struct {
	net.Listener
	statuses []int
}

func (l parityListener) Accept() (net.Conn, error) {
	conn, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &parityConn{Conn: conn, statuses: l.statuses}, nil
}

type parityConn struct {
	net.Conn
	statuses []int
	buffer   []byte
}

// Write sends p, with "HTTP/1.1 404 Not Found\r\n" as "HTTP/1.1 404 \r\n" when p starts a response of a gated
// status. net/http flushes its buffered writer at the end of every response, so a response head always starts a
// Write; a body never starts with "HTTP/1.1 ".
func (c *parityConn) Write(p []byte) (int, error) {
	reason := reasonLength(p, c.statuses)
	if reason == 0 {
		return c.Conn.Write(p)
	}
	c.buffer = append(append(c.buffer[:0], p[:len("HTTP/1.1 404 ")]...), p[len("HTTP/1.1 404 ")+reason:]...)
	if _, err := c.Conn.Write(c.buffer); err != nil {
		return 0, err
	}
	return len(p), nil
}

// reasonLength is the length of the reason phrase p's status line carries, when p starts the status line of one of
// statuses with net/http's status text; 0 otherwise.
func reasonLength(p []byte, statuses []int) int {
	const prefix = len("HTTP/1.1 404 ")
	if len(p) < prefix || string(p[:9]) != "HTTP/1.1 " || p[12] != ' ' {
		return 0
	}
	code := int(p[9]-'0')*100 + int(p[10]-'0')*10 + int(p[11]-'0')
	for _, status := range statuses {
		if status != code {
			continue
		}
		text := http.StatusText(code)
		if len(p) >= prefix+len(text)+2 && string(p[prefix:prefix+len(text)]) == text && p[prefix+len(text)] == '\r' {
			return len(text)
		}
	}
	return 0
}
