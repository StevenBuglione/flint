package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"mime"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	contextPath = "/petclinic" // server.servlet.context-path

	errorUnexpected    = "An unexpected error occurred while processing your request"
	errorDataIntegrity = "The requested resource could not be processed due to a data constraint violation"
	errorInvalid       = "The request contains invalid or missing parameters"

	// servletAllow is the Allow header the servlet container's OPTIONS handling writes.
	servletAllow = "GET, HEAD, PATCH, POST, PUT, DELETE, OPTIONS, TRACE"

	// tomcatNotFound is Tomcat's error page for a path outside the application's context path.
	tomcatNotFound = `<!doctype html><html lang="en"><head><title>HTTP Status 404 – Not Found</title><style type="text/css">` +
		`body {font-family:Tahoma,Arial,sans-serif;} h1, h2, h3, b {color:white;background-color:#525D76;} ` +
		`h1 {font-size:22px;} h2 {font-size:16px;} h3 {font-size:14px;} p {font-size:12px;} a {color:black;} ` +
		`.line {height:1px;background-color:#525D76;border:none;}</style></head><body><h1>HTTP Status 404 – Not Found</h1>` +
		`</body></html>`
)

// securityHeaders are the headers Spring Security's default header writers add to every response.
var securityHeaders = [...][2]string{
	{"X-Content-Type-Options", "nosniff"},
	{"X-Xss-Protection", "0"},
	{"Cache-Control", "no-cache, no-store, max-age=0, must-revalidate"},
	{"Pragma", "no-cache"},
	{"Expires", "0"},
	{"X-Frame-Options", "SAMEORIGIN"},
}

// ---------------------------------------------------------------------------------------------------------------
// Errors, rendered as the application's ExceptionControllerAdvice renders them

// requestError is a failure with the status, title and detail the advice gives it. The title is the simple name
// of the exception Spring would have raised, because the advice reports exactly that.
type requestError struct {
	status     int
	title      string
	detail     string
	violations []validationMessage
}

func (e *requestError) Error() string { return e.title }

// unexpected is the advice's catch-all: a 500 named after the exception.
func unexpected(title string) *requestError {
	return &requestError{status: http.StatusInternalServerError, title: title, detail: errorUnexpected}
}

var (
	errNoResource       = unexpected("NoResourceFoundException")
	errMethod           = unexpected("HttpRequestMethodNotSupportedException")
	errMediaType        = unexpected("HttpMediaTypeNotSupportedException")
	errTypeMismatch     = unexpected("MethodArgumentTypeMismatchException")
	errNotReadable      = unexpected("HttpMessageNotReadableException")
	errConstraint       = unexpected("ConstraintViolationException")
	errIllegalArgument  = unexpected("IllegalArgumentException")
	errNullPointer      = unexpected("NullPointerException")
	errJdbcConnection   = unexpected("CannotGetJdbcConnectionException")
	errUncategorizedSQL = unexpected("UncategorizedSQLException")
)

type validationMessage struct {
	Message        string `json:"message"`
	Field          string `json:"field"`
	DefaultMessage string `json:"defaultMessage"`
	RejectedValue  string `json:"rejectedValue"`
}

type problemDetail struct {
	Detail                 string              `json:"detail"`
	Status                 int                 `json:"status"`
	Title                  string              `json:"title"`
	Type                   string              `json:"type"`
	Timestamp              string              `json:"timestamp"`
	SchemaValidationErrors []validationMessage `json:"schemaValidationErrors"`
}

// sqlStateError is implemented by the driver's server errors (*pgconn.PgError).
type sqlStateError interface {
	SQLState() string
}

// translateSQL maps a PostgreSQL error the way Spring's SQLErrorCodeSQLExceptionTranslator does with the
// PostgreSQL error codes, falling back on SQLStateSQLExceptionTranslator's classes. Integrity violations are 404s
// in the reference's advice; everything else is a 500 named after the exception.
func translateSQL(state string) *requestError {
	integrity := func(title string) *requestError {
		return &requestError{status: http.StatusNotFound, title: title, detail: errorDataIntegrity}
	}
	switch state {
	case "23505", "21000":
		return integrity("DuplicateKeyException")
	case "23000", "23502", "23503", "23514":
		return integrity("DataIntegrityViolationException")
	case "03000", "42000", "42601", "42602", "42622", "42804", "42P01":
		return unexpected("BadSqlGrammarException")
	case "53000", "53100", "53200", "53300":
		return unexpected("DataAccessResourceFailureException")
	case "55P03":
		return unexpected("CannotAcquireLockException")
	case "40001":
		return unexpected("CannotSerializeTransactionException")
	case "40P01":
		return unexpected("DeadlockLoserDataAccessException")
	}
	if len(state) < 2 {
		return errUncategorizedSQL
	}
	switch state[:2] {
	case "07", "21", "2A", "37", "42", "65":
		return unexpected("BadSqlGrammarException")
	case "01", "02", "22", "23", "27", "44":
		return integrity("DataIntegrityViolationException")
	case "08", "53", "54", "57", "58":
		return unexpected("DataAccessResourceFailureException")
	case "40", "61":
		return unexpected("PessimisticLockingFailureException")
	}
	return errUncategorizedSQL
}

// fail renders err as the advice would.
func fail(w http.ResponseWriter, r *http.Request, err error) {
	var re *requestError
	var missing *missingError
	var state sqlStateError
	switch {
	case errors.As(err, &re):
	case errors.As(err, &missing):
		re = unexpected(missing.title)
	case errors.As(err, &state):
		re = translateSQL(state.SQLState())
	case errors.Is(err, sql.ErrNoRows):
		re = unexpected("EmptyResultDataAccessException")
	default:
		re = errJdbcConnection
	}
	if re.status >= http.StatusInternalServerError {
		log.Printf("ERROR unexpected error at %s %s: %v", r.Method, r.URL.RequestURI(), err)
	}
	violations := re.violations
	if violations == nil {
		violations = []validationMessage{}
	}
	writeJSON(w, re.status, "application/problem+json", problemDetail{
		Detail: re.detail, Status: re.status, Title: re.title, Type: requestURL(r),
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano), SchemaValidationErrors: violations,
	})
}

// requestURL is HttpServletRequest.getRequestURL: scheme, host and the undecoded path, without the query.
func requestURL(r *http.Request) string {
	path := r.RequestURI
	if i := strings.IndexByte(path, '?'); i >= 0 {
		path = path[:i]
	}
	return "http://" + r.Host + path
}

// ---------------------------------------------------------------------------------------------------------------
// Responses

// writeJSON writes a JSON response as Spring MVC's message converters do on Tomcat (ADR-033): streamed, so chunked,
// and after a 400 or a 500 Tomcat closes the connection.
func writeJSON(w http.ResponseWriter, status int, contentType string, value any) {
	writeJSONFramed(w, status, contentType, value, true)
}

// writeJSONLength writes a JSON response with Content-Length, as Tomcat frames a body written whole (the actuator's
// link index).
func writeJSONLength(w http.ResponseWriter, status int, contentType string, value any) {
	writeJSONFramed(w, status, contentType, value, false)
}

func writeJSONFramed(w http.ResponseWriter, status int, contentType string, value any, chunked bool) {
	body, err := json.Marshal(value)
	if err != nil {
		log.Printf("ERROR encoding a response: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", contentType)
	if chunked {
		w.Header().Set("Transfer-Encoding", "chunked")
	}
	if status == http.StatusBadRequest || status == http.StatusInternalServerError {
		w.Header().Set("Connection", "close")
	}
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func ok(w http.ResponseWriter, value any) { writeJSON(w, http.StatusOK, "application/json", value) }

func created(w http.ResponseWriter, location string, value any) {
	if location != "" {
		w.Header().Set("Location", location)
	}
	writeJSON(w, http.StatusCreated, "application/json", value)
}

// noContent is a 204. A controller that returns a body with 204 still gets the JSON content type from Spring,
// though the body itself is dropped.
func noContent(w http.ResponseWriter, withBodyType bool) {
	if withBodyType {
		w.Header().Set("Content-Type", "application/json")
	}
	w.WriteHeader(http.StatusNoContent)
}

func notFound(w http.ResponseWriter) { w.WriteHeader(http.StatusNotFound) }

// ---------------------------------------------------------------------------------------------------------------
// Request parameters, converted as Spring's conversion service converts them

// parseJavaInt is Spring's NumberUtils.parseNumber for Integer: whitespace removed, then Integer.decode for hex
// (0x, 0X, #, optionally negative) and Integer.valueOf otherwise.
func parseJavaInt(text string) (int, bool) {
	s := strings.Map(func(r rune) rune {
		if strings.ContainsRune(" \t\n\r\f\v", r) {
			return -1
		}
		return r
	}, text)
	digits, sign, base := s, "", 10
	if rest, negative := strings.CutPrefix(s, "-"); negative {
		digits, sign = rest, "-"
	}
	for _, prefix := range []string{"0x", "0X", "#"} {
		if rest, hex := strings.CutPrefix(digits, prefix); hex {
			if rest == "" || rest[0] == '+' || rest[0] == '-' {
				return 0, false
			}
			s, base = sign+rest, 16
			break
		}
	}
	n, err := strconv.ParseInt(s, base, 32)
	return int(n), err == nil
}

// pathInt converts an Integer path variable; a failure is a MethodArgumentTypeMismatchException.
func pathInt(r *http.Request, name string) (int, error) {
	n, valid := parseJavaInt(r.PathValue(name))
	if !valid {
		return 0, errTypeMismatch
	}
	return n, nil
}

// queryParam is a String @RequestParam: repeated values are joined with commas, as Spring converts String[].
func queryParam(r *http.Request, name string) (string, bool) {
	values, present := r.URL.Query()[name]
	return strings.Join(values, ","), present
}

// queryInt is an Integer @RequestParam with a default value, which Spring also applies to an empty value.
func queryInt(r *http.Request, name string, fallback int) (int, error) {
	value, _ := queryParam(r, name)
	if value == "" {
		return fallback, nil
	}
	n, valid := parseJavaInt(value)
	if !valid {
		return 0, errTypeMismatch
	}
	return n, nil
}

// splitAccept lists the media types an Accept header admits (quality above zero), lower-cased and without
// parameters.
func splitAccept(accept string) []string {
	var types []string
	for _, item := range strings.Split(accept, ",") {
		mediaType, params, err := mime.ParseMediaType(strings.TrimSpace(item))
		if err != nil {
			continue
		}
		if q, err := strconv.ParseFloat(params["q"], 64); err == nil && q <= 0 {
			continue
		}
		types = append(types, mediaType)
	}
	return types
}

// minZero is the @Min(0) on the path variables, checked by method validation after the body is validated.
func minZero(ids ...int) error {
	for _, id := range ids {
		if id < 0 {
			return errConstraint
		}
	}
	return nil
}

// consumesJSON is the consumes = "application/json" condition; a request without a content type is
// application/octet-stream to Spring.
func consumesJSON(r *http.Request) bool {
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	return err == nil && mediaType == "application/json"
}

// readBody reads a required @RequestBody into dst (a pointer to a pointer, so a JSON null is detected).
func readBody[T any](r *http.Request, dst **T) error {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil || *dst == nil {
		return errNotReadable
	}
	return nil
}

// ---------------------------------------------------------------------------------------------------------------
// CORS: @CrossOrigin(exposedHeaders = "errors, content-type") on every controller

func addVary(h http.Header) {
	h.Add("Vary", "Origin")
	h.Add("Vary", "Access-Control-Request-Method")
	h.Add("Vary", "Access-Control-Request-Headers")
}

// crossOrigin reports whether the request carries an Origin other than the server's own (CorsUtils.isCorsRequest).
func crossOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return false
	}
	parsed, err := url.Parse(origin)
	if err != nil {
		return true
	}
	defaultPort := func(scheme, port string) string {
		if port != "" {
			return port
		}
		if scheme == "https" {
			return "443"
		}
		return "80"
	}
	host := &url.URL{Host: r.Host}
	return !strings.EqualFold(parsed.Scheme, "http") || !strings.EqualFold(parsed.Hostname(), host.Hostname()) ||
		defaultPort(strings.ToLower(parsed.Scheme), parsed.Port()) != defaultPort("http", host.Port())
}

// cors processes an actual request to a handler with a CORS configuration (DefaultCorsProcessor). allowed lists
// the methods the configuration admits.
func cors(w http.ResponseWriter, r *http.Request, allowed ...string) bool {
	h := w.Header()
	addVary(h)
	if !crossOrigin(r) {
		return true
	}
	if !methodAllowed(r.Method, allowed) {
		w.Header().Set("Content-Type", "text/plain;charset=ISO-8859-1")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("Invalid CORS request"))
		return false
	}
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Expose-Headers", "errors, content-type")
	return true
}

func methodAllowed(method string, allowed []string) bool {
	for _, m := range allowed {
		if m == method || (method == http.MethodHead && m == http.MethodGet) {
			return true
		}
	}
	return false
}

func isPreflight(r *http.Request) bool {
	return r.Method == http.MethodOptions && r.Header.Get("Origin") != "" &&
		r.Header.Get("Access-Control-Request-Method") != ""
}

// preflight answers a preflight request for a handler whose configuration admits allowed; the servlet's OPTIONS
// handling then adds its Allow header.
func preflight(w http.ResponseWriter, r *http.Request, allowed ...string) {
	h := w.Header()
	addVary(h)
	if crossOrigin(r) {
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Methods", strings.Join(allowed, ","))
		var requested []string
		for _, name := range strings.Split(r.Header.Get("Access-Control-Request-Headers"), ",") {
			if name = strings.TrimSpace(name); name != "" {
				requested = append(requested, name)
			}
		}
		if len(requested) > 0 {
			h.Set("Access-Control-Allow-Headers", strings.Join(requested, ", "))
		}
		h.Set("Access-Control-Expose-Headers", "errors, content-type")
		h.Set("Access-Control-Max-Age", "1800")
	}
	options(w)
}

// options is the servlet container's answer to OPTIONS.
func options(w http.ResponseWriter) {
	w.Header().Set("Allow", servletAllow)
	w.WriteHeader(http.StatusOK)
}

// ---------------------------------------------------------------------------------------------------------------
// Routing

// handler is an endpoint; a returned error is rendered by the advice.
type handler func(w http.ResponseWriter, r *http.Request) error

// endpoint is one request mapping of a path.
type endpoint struct {
	method   string
	consumes bool // consumes = "application/json"
	handle   handler
}

func onGet(h handler) endpoint    { return endpoint{http.MethodGet, false, h} }
func onPost(h handler) endpoint   { return endpoint{http.MethodPost, true, h} }
func onPut(h handler) endpoint    { return endpoint{http.MethodPut, true, h} }
func onDelete(h handler) endpoint { return endpoint{http.MethodDelete, false, h} }

// api registers a controller path under the context path: one pattern per mapped method, and a pattern without
// a method that answers preflight requests, OPTIONS and the methods the path does not map.
func api(mux *http.ServeMux, path string, endpoints ...endpoint) {
	var methods []string
	for _, ep := range endpoints {
		methods = append(methods, ep.method)
		mux.HandleFunc(ep.method+" "+contextPath+path, func(w http.ResponseWriter, r *http.Request) {
			if ep.consumes && !consumesJSON(r) {
				fail(w, r, errMediaType) // raised by the handler mapping, before CORS processing
				return
			}
			if !cors(w, r, ep.method) {
				return
			}
			if err := ep.handle(w, r); err != nil {
				fail(w, r, err)
			}
		})
	}
	mux.HandleFunc(contextPath+path, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case isPreflight(r):
			requested := r.Header.Get("Access-Control-Request-Method")
			for _, m := range methods {
				if methodAllowed(requested, []string{m}) {
					preflight(w, r, m)
					return
				}
			}
			options(w)
		case r.Method == http.MethodOptions:
			options(w)
		default:
			fail(w, r, errMethod)
		}
	})
}

// actuator registers a read-only actuator endpoint: no CORS configuration, other methods unsupported.
func actuator(mux *http.ServeMux, path string, h handler) {
	mux.HandleFunc(http.MethodGet+" "+contextPath+path, func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			fail(w, r, err)
		}
	})
	mux.HandleFunc(contextPath+path, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			options(w)
			return
		}
		fail(w, r, errMethod)
	})
}

// container is the servlet container in front of the application: Tomcat answers outside the context path, and
// Spring Security writes its headers on everything inside it.
func container(app http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch path := r.URL.Path; {
		case path == contextPath:
			location := contextPath + "/"
			if r.URL.RawQuery != "" {
				location += "?" + r.URL.RawQuery
			}
			w.Header().Set("Location", location)
			w.WriteHeader(http.StatusFound)
		case !strings.HasPrefix(path, contextPath+"/"):
			h := w.Header()
			h.Set("Content-Type", "text/html;charset=utf-8")
			h.Set("Content-Language", "en")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(tomcatNotFound))
		default:
			h := w.Header()
			for _, header := range securityHeaders {
				h.Set(header[0], header[1])
			}
			app.ServeHTTP(w, r)
		}
	})
}
