package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestContract(t *testing.T) {
	for _, tc := range []struct {
		method, path string
		status       int
		body         string
	}{
		{"GET", "/health", 200, "ok\n"},
		{"GET", "/json", 200, jsonBody},
		{"POST", "/json", 405, "method not allowed\n"},
		{"GET", "/missing", 404, "404 page not found\n"},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler(response, httptest.NewRequest(tc.method, tc.path, nil))
			if response.Code != tc.status || response.Body.String() != tc.body {
				t.Fatalf("got %d %q; want %d %q", response.Code, response.Body.String(), tc.status, tc.body)
			}
			if tc.status == http.StatusMethodNotAllowed && response.Header().Get("Allow") != "GET" {
				t.Fatal("missing Allow")
			}
		})
	}
}
