package main

import (
	"cmp"
	"database/sql/driver"
	"fmt"
	"slices"
	"time"
	"unicode"
	"unicode/utf8"
)

// The resources, laid out as the API renders them: struct field order is the JSON key order of the generated
// Spring DTOs (OwnerDto, PetDto, ...).

// Owner is a pet owner with the pets the JDBC layer loads with it.
type Owner struct {
	FirstName string `json:"firstName"`
	LastName  string `json:"lastName"`
	Address   string `json:"address"`
	City      string `json:"city"`
	Telephone string `json:"telephone"`
	Pets      []*Pet `json:"pets"`
	ID        int    `json:"id"`
}

// Pet is a pet with its type and visits. typeID is the pets.type_id column, resolved against the pet types.
type Pet struct {
	Name      string  `json:"name"`
	BirthDate Date    `json:"birthDate"`
	Type      PetType `json:"type"`
	ID        int     `json:"id"`
	Visits    []Visit `json:"visits"`
	OwnerID   int     `json:"ownerId"`
	typeID    int
}

// PetType is a kind of pet.
type PetType struct {
	Name string `json:"name"`
	ID   int    `json:"id"`
}

// Visit is a booking for a pet.
type Visit struct {
	Date        Date   `json:"date"`
	Description string `json:"description"`
	ID          int    `json:"id"`
	PetID       int    `json:"petId"`
}

// Specialty is a vet's specialty.
type Specialty struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

// Vet is a veterinarian with specialties.
type Vet struct {
	FirstName   string      `json:"firstName"`
	LastName    string      `json:"lastName"`
	Specialties []Specialty `json:"specialties"`
	ID          int         `json:"id"`
}

// User is an account with roles; the nullable fields render as JSON null, as Jackson does.
type User struct {
	Username string  `json:"username"`
	Enabled  *bool   `json:"enabled"`
	Password *string `json:"password"`
	Roles    []Role  `json:"roles"`
}

// Role is a user's role.
type Role struct {
	Name string `json:"name"`
}

// Page is the v2 paged listing (OwnerPageDto, PetPageDto).
type Page[T any] struct {
	Content       []T   `json:"content"`
	Page          int   `json:"page"`
	Size          int   `json:"size"`
	TotalElements int64 `json:"totalElements"`
	TotalPages    int   `json:"totalPages"`
}

// newPage computes the totals as Spring Data's PageImpl does.
func newPage[T any](content []T, page, size int, total int64) Page[T] {
	offset := int64(page) * int64(size)
	if len(content) > 0 && offset+int64(size) > total {
		total = offset + int64(len(content))
	}
	return Page[T]{Content: content, Page: page, Size: size, TotalElements: total,
		TotalPages: int((total + int64(size) - 1) / int64(size))}
}

// Date is a calendar date (java.time.LocalDate), rendered as YYYY-MM-DD.
type Date struct {
	time.Time
}

const dateLayout = "2006-01-02"

func (d Date) String() string { return d.Format(dateLayout) }

// MarshalJSON renders the ISO local date.
func (d Date) MarshalJSON() ([]byte, error) {
	return []byte(`"` + d.String() + `"`), nil
}

// Scan reads a PostgreSQL DATE.
func (d *Date) Scan(src any) error {
	t, ok := src.(time.Time)
	if !ok {
		return fmt.Errorf("cannot scan %T into a date", src)
	}
	d.Time = t
	return nil
}

// Value writes a PostgreSQL DATE.
func (d Date) Value() (driver.Value, error) { return d.Time, nil }

// sortPets orders an owner's pets by name, case-insensitively (Owner.getPets).
func sortPets(pets []*Pet) {
	slices.SortStableFunc(pets, func(a, b *Pet) int { return compareFold(a.Name, b.Name) })
}

// sortVisits orders a pet's visits by date, latest first (Pet.getVisits).
func sortVisits(visits []Visit) {
	slices.SortStableFunc(visits, func(a, b Visit) int { return b.Date.Compare(a.Date.Time) })
}

// sortSpecialties orders a vet's specialties by name, case-insensitively (Vet.getSpecialties).
func sortSpecialties(specialties []Specialty) {
	slices.SortStableFunc(specialties, func(a, b Specialty) int { return compareFold(a.Name, b.Name) })
}

// compareFold is Java's String.CASE_INSENSITIVE_ORDER.
func compareFold(a, b string) int {
	for a != "" && b != "" {
		ra, na := utf8.DecodeRuneInString(a)
		rb, nb := utf8.DecodeRuneInString(b)
		if ra != rb {
			ca, cb := unicode.ToLower(unicode.ToUpper(ra)), unicode.ToLower(unicode.ToUpper(rb))
			if ca != cb {
				return cmp.Compare(ca, cb)
			}
		}
		a, b = a[na:], b[nb:]
	}
	return cmp.Compare(len(a), len(b))
}
