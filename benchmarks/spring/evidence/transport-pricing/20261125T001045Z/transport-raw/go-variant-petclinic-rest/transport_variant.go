package main

// Diagnostic only (tools/spring_transport.py); never part of the registered comparator.

import (
	"net/http"
	"os"
	"strconv"
)

var transportChunked = os.Getenv("GO_TRANSPORT_CHUNKED") == "1"

var transportCloseStatus = func() int {
	status, _ := strconv.Atoi(os.Getenv("GO_TRANSPORT_CLOSE_STATUS"))
	return status
}()

func transportVariant(w http.ResponseWriter, status int) {
	if transportChunked {
		w.Header().Set("Transfer-Encoding", "chunked")
	}
	if transportCloseStatus != 0 && status == transportCloseStatus {
		w.Header().Set("Connection", "close")
	}
}
