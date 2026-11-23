package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
)

// Request bodies. The DTOs generated from openapi.yml are bound by Jackson, which coerces scalars (a number into a
// String field, a numeric string into an Integer field) and leaves a missing or null field null; then Bean
// Validation checks the constraints the generator put on the fields. The types below do the same.

var errCoercion = errors.New("cannot coerce the JSON value")

// optString is a String field.
type optString struct {
	value string
	set   bool
}

func (s *optString) UnmarshalJSON(b []byte) error {
	switch {
	case bytes.Equal(b, []byte("null")):
		*s = optString{}
	case b[0] == '"':
		s.set = true
		return json.Unmarshal(b, &s.value)
	case b[0] == '{' || b[0] == '[':
		return errCoercion
	default: // numbers and booleans become their text
		*s = optString{string(b), true}
	}
	return nil
}

func (s optString) rejected() string {
	if !s.set {
		return "null"
	}
	return s.value
}

// optInt is an Integer field: floats are truncated and numeric strings parsed, as Jackson does by default.
type optInt struct {
	value int
	set   bool
}

func (n *optInt) UnmarshalJSON(b []byte) error {
	text := string(b)
	switch {
	case text == "null":
		*n = optInt{}
		return nil
	case b[0] == '"':
		if err := json.Unmarshal(b, &text); err != nil {
			return err
		}
		if text = strings.TrimSpace(text); text == "" {
			*n = optInt{}
			return nil
		}
	case b[0] == '{' || b[0] == '[' || b[0] == 't' || b[0] == 'f':
		return errCoercion
	}
	if i, err := strconv.ParseInt(text, 10, 32); err == nil {
		*n = optInt{int(i), true}
		return nil
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil || f >= math.MaxInt32+1 || f <= math.MinInt32-1 || b[0] == '"' {
		return errCoercion
	}
	*n = optInt{int(f), true}
	return nil
}

func (n optInt) rejected() string {
	if !n.set {
		return "null"
	}
	return strconv.Itoa(n.value)
}

// optBool is a Boolean field.
type optBool struct {
	value bool
	set   bool
}

func (v *optBool) UnmarshalJSON(b []byte) error {
	switch strings.ToLower(strings.Trim(string(b), `"`)) {
	case "null", "":
		*v = optBool{}
	case "true":
		*v = optBool{true, true}
	case "false":
		*v = optBool{false, true}
	default:
		return errCoercion
	}
	return nil
}

func (v optBool) ptr() *bool {
	if !v.set {
		return nil
	}
	return &v.value
}

// optDate is a LocalDate field in ISO form; an empty string is null.
type optDate struct {
	value Date
	set   bool
}

func (d *optDate) UnmarshalJSON(b []byte) error {
	if bytes.Equal(b, []byte("null")) {
		*d = optDate{}
		return nil
	}
	var text string
	if err := json.Unmarshal(b, &text); err != nil {
		return err
	}
	if text = strings.TrimSpace(text); text == "" {
		*d = optDate{}
		return nil
	}
	t, err := time.Parse(dateLayout, text)
	if err != nil {
		return err
	}
	*d = optDate{Date{t}, true}
	return nil
}

func (d optDate) rejected() string {
	if !d.set {
		return "null"
	}
	return d.value.String()
}

type ownerFields struct {
	FirstName optString `json:"firstName"`
	LastName  optString `json:"lastName"`
	Address   optString `json:"address"`
	City      optString `json:"city"`
	Telephone optString `json:"telephone"`
}

type petTypeBody struct {
	Name optString `json:"name"`
	ID   optInt    `json:"id"`
}

type petFields struct {
	Name      optString    `json:"name"`
	BirthDate optDate      `json:"birthDate"`
	Type      *petTypeBody `json:"type"`
}

// petBody is PetDto, the body of PUT /pets/{petId}.
type petBody struct {
	petFields
	ID      optInt        `json:"id"`
	OwnerID optInt        `json:"ownerId"`
	Visits  *[]*visitBody `json:"visits"`
}

type visitFields struct {
	Date        optDate   `json:"date"`
	Description optString `json:"description"`
}

// visitBody is VisitDto, the body of POST /visits.
type visitBody struct {
	visitFields
	ID    optInt `json:"id"`
	PetID optInt `json:"petId"`
}

type petTypeFields struct {
	Name optString `json:"name"`
}

type specialtyBody struct {
	ID   optInt    `json:"id"`
	Name optString `json:"name"`
}

type vetBody struct {
	FirstName   optString         `json:"firstName"`
	LastName    optString         `json:"lastName"`
	Specialties *[]*specialtyBody `json:"specialties"`
	ID          optInt            `json:"id"`
}

type roleBody struct {
	Name optString `json:"name"`
}

type userBody struct {
	Username optString    `json:"username"`
	Password optString    `json:"password"`
	Enabled  optBool      `json:"enabled"`
	Roles    *[]*roleBody `json:"roles"`
}

// ---------------------------------------------------------------------------------------------------------------
// Bean Validation

// pattern is a @Pattern constraint: the regular expression as the annotation spells it (Java syntax, quoted in
// the message) and its RE2 equivalent, matched against the whole value as Matcher.matches() does. Java's \s is
// [ \t\n\x0B\f\r], so the RE2 forms spell that class out.
type pattern struct {
	java string
	re   *regexp.Regexp
}

func newPattern(java, re2 string) pattern {
	return pattern{java, regexp.MustCompile(`^(?:` + re2 + `)$`)}
}

var (
	firstNamePattern = newPattern(`^[\p{L}]+([ '-][\p{L}]+){0,2}$`, `[\p{L}]+([ '-][\p{L}]+){0,2}`)
	lastNamePattern  = newPattern(`^[\p{L}]+([ '-][\p{L}]+){0,2}\.?$`, `[\p{L}]+([ '-][\p{L}]+){0,2}\.?`)
	notBlankPattern  = newPattern(`[\s\S]*\S[\s\S]*`, `(?s:.)*[^\t\n\v\f\r ](?s:.)*`)
	telephonePattern = newPattern(`^[0-9]{10}$`, `[0-9]{10}`)
	petTypePattern   = newPattern(`^[\p{L}][\p{L}\s\-']{0,79}$`, `[\p{L}][\p{L}\t\n\v\f\r \-']{0,79}`)
	specialtyPattern = newPattern(`^[\p{L}][\p{L}\s\-&/]{0,79}$`, `[\p{L}][\p{L}\t\n\v\f\r \-&/]{0,79}`)
	rolePattern      = newPattern(`^ROLE_[A-Z][A-Z0-9_]{1,74}$`, `ROLE_[A-Z][A-Z0-9_]{1,74}`)
)

// violations collects field errors for a MethodArgumentNotValidException.
type violations []validationMessage

func (v *violations) add(field, message, rejected string) {
	*v = append(*v, validationMessage{
		Message: "Field '" + field + "' " + message + " (rejected value: " + rejected + ")",
		Field:   field, DefaultMessage: message, RejectedValue: rejected,
	})
}

// text checks @NotNull (when required), @Pattern (when given) and @Size(min, max) on a String field.
func (v *violations) text(field string, s optString, required bool, p *pattern, min, max int) {
	if !s.set {
		if required {
			v.add(field, "must not be null", "null")
		}
		return
	}
	if p != nil && !p.re.MatchString(s.value) {
		v.add(field, `must match "`+p.java+`"`, s.value)
	}
	if n := len(utf16.Encode([]rune(s.value))); n < min || n > max { // String.length() counts UTF-16 units
		v.add(field, "size must be between "+strconv.Itoa(min)+" and "+strconv.Itoa(max), s.value)
	}
}

// integer checks @NotNull (when required) and @Min(0) on an Integer field.
func (v *violations) integer(field string, n optInt, required bool) {
	switch {
	case !n.set && required:
		v.add(field, "must not be null", "null")
	case n.set && n.value < 0:
		v.add(field, "must be greater than or equal to 0", n.rejected())
	}
}

func (v *violations) notNull(field string, present bool) {
	if !present {
		v.add(field, "must not be null", "null")
	}
}

// birthDate checks @NotNull and @PetAgeValidation (PetAgeValidator, against today's date in the local zone).
func (v *violations) birthDate(field string, d optDate) {
	if !d.set {
		v.add(field, "must not be null", "null")
		return
	}
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	born := time.Date(d.value.Year(), d.value.Month(), d.value.Day(), 0, 0, 0, 0, time.UTC)
	switch {
	case born.After(today):
		v.add(field, "Birth date cannot be in the future", d.rejected())
	case born.Before(minusYears(today, 50)):
		v.add(field, "Birth date cannot be older than 50 years", d.rejected())
	}
}

// minusYears is LocalDate.minusYears: the day is clamped to the end of a shorter month (29 February).
func minusYears(t time.Time, years int) time.Time {
	year, month, day := t.Year()-years, t.Month(), t.Day()
	if last := time.Date(year, month+1, 0, 0, 0, 0, 0, time.UTC).Day(); day > last {
		day = last
	}
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

func (v violations) err() error {
	if len(v) == 0 {
		return nil
	}
	return &requestError{status: http.StatusBadRequest, title: "MethodArgumentNotValidException", detail: errorInvalid,
		violations: v}
}

func indexed(prefix string, i int, field string) string {
	return prefix + "[" + strconv.Itoa(i) + "]." + field
}

func (b *ownerFields) validate() error {
	var v violations
	v.text("firstName", b.FirstName, true, &firstNamePattern, 1, 30)
	v.text("lastName", b.LastName, true, &lastNamePattern, 1, 30)
	v.text("address", b.Address, true, &notBlankPattern, 1, 255)
	v.text("city", b.City, true, &notBlankPattern, 1, 80)
	v.text("telephone", b.Telephone, true, &telephonePattern, 10, 10)
	return v.err()
}

func (b *petFields) check(v *violations) {
	v.text("name", b.Name, true, &notBlankPattern, 1, 30)
	v.birthDate("birthDate", b.BirthDate)
	v.notNull("type", b.Type != nil)
	if b.Type != nil {
		v.text("type.name", b.Type.Name, true, &petTypePattern, 1, 80)
		v.integer("type.id", b.Type.ID, true)
	}
}

func (b *petFields) validate() error {
	var v violations
	b.check(&v)
	return v.err()
}

func (b *visitFields) check(v *violations, prefix string) {
	v.notNull(prefix+"date", b.Date.set)
	v.text(prefix+"description", b.Description, true, &notBlankPattern, 1, 255)
}

func (b *visitFields) validate() error {
	var v violations
	b.check(&v, "")
	return v.err()
}

func (b *visitBody) check(v *violations, prefix string) {
	b.visitFields.check(v, prefix)
	v.integer(prefix+"id", b.ID, false)
	v.integer(prefix+"petId", b.PetID, true)
}

func (b *visitBody) validate() error {
	var v violations
	b.check(&v, "")
	return v.err()
}

func (b *petBody) validate() error {
	var v violations
	b.petFields.check(&v)
	v.integer("id", b.ID, false)
	v.integer("ownerId", b.OwnerID, false)
	if b.Visits != nil {
		for i, visit := range *b.Visits {
			if visit != nil {
				visit.check(&v, indexed("visits", i, ""))
			}
		}
	}
	return v.err()
}

func (b *petTypeFields) validate() error {
	var v violations
	v.text("name", b.Name, true, &petTypePattern, 1, 80)
	return v.err()
}

func (b *petTypeBody) validate() error {
	var v violations
	v.text("name", b.Name, true, &petTypePattern, 1, 80)
	v.integer("id", b.ID, true)
	return v.err()
}

func (b *specialtyBody) check(v *violations, prefix string) {
	v.integer(prefix+"id", b.ID, false)
	v.text(prefix+"name", b.Name, true, &specialtyPattern, 1, 80)
}

func (b *specialtyBody) validate() error {
	var v violations
	b.check(&v, "")
	return v.err()
}

func (b *vetBody) validate() error {
	var v violations
	v.text("firstName", b.FirstName, true, &firstNamePattern, 1, 30)
	v.text("lastName", b.LastName, true, &lastNamePattern, 1, 30)
	v.notNull("specialties", b.Specialties != nil)
	if b.Specialties != nil {
		for i, s := range *b.Specialties {
			if s != nil {
				s.check(&v, indexed("specialties", i, ""))
			}
		}
	}
	v.integer("id", b.ID, false)
	return v.err()
}

func (b *userBody) validate() error {
	var v violations
	v.text("username", b.Username, true, nil, 1, 80)
	v.text("password", b.Password, false, nil, 1, 80)
	if b.Roles != nil {
		for i, role := range *b.Roles {
			if role != nil {
				v.text(indexed("roles", i, "name"), role.Name, true, &rolePattern, 1, 80)
			}
		}
	}
	return v.err()
}
