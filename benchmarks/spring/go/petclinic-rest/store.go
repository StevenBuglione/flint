package main

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"strings"
	"sync"
)

// The data access mirrors the reference's repository/jdbc classes statement for statement: the same queries, in
// the same order, with the same per-row follow-up queries. Rows are read to the end before a follow-up query
// runs, so a transaction (one connection) never has two result sets open.

// querier is what *sql.DB and *sql.Tx have in common.
type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// missingError is a row that refers to an entity that is not there: Spring's ObjectRetrievalFailureException or
// EmptyResultDataAccessException. The find-by-id service methods turn it into "not found"; elsewhere it is a 500.
type missingError struct{ title string }

func (e *missingError) Error() string { return e.title }

var (
	errRetrieval  = &missingError{"ObjectRetrievalFailureException"}
	errEmptyQuery = &missingError{"EmptyResultDataAccessException"}
)

// absent reports whether a find-by-id should answer "not found" for err (ClinicServiceImpl.findEntityById).
func absent(err error) bool {
	var missing *missingError
	return errors.Is(err, sql.ErrNoRows) || errors.As(err, &missing)
}

// inTx runs fn in a transaction, as the reference's @Transactional service and controller methods do.
func inTx(ctx context.Context, db *sql.DB, fn func(tx *sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// readOnly runs fn in a read-only transaction, as the reference's @Transactional(readOnly = true) service finders
// do (ClinicServiceImpl): every service call the reference's controller makes is one transaction (ADR-032). A
// finder that finds nothing commits, as the reference's does; any other error rolls back.
func readOnly[T any](ctx context.Context, db *sql.DB, fn func(q querier) (T, error)) (T, error) {
	var zero T
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return zero, err
	}
	value, err := fn(tx)
	if err != nil && !absent(err) {
		_ = tx.Rollback()
		return zero, err
	}
	if commitErr := tx.Commit(); commitErr != nil {
		return zero, commitErr
	}
	return value, err
}

// The two catalog queries pgjdbc's DatabaseMetaData sends when Spring's SimpleJdbcInsert compiles, on the first
// insert into each table (getTables, then getColumns with the schema it returned), copied from the reference's
// statement log (ADR-032: the comparator sends the reference's SQL, first-use statements included).
const (
	metadataTables  = `SELECT current_database() AS "TABLE_CAT", n.nspname AS "TABLE_SCHEM", c.relname AS "TABLE_NAME",  CASE n.nspname ~ '^pg_' OR n.nspname = 'information_schema'  WHEN true THEN CASE  WHEN n.nspname = 'pg_catalog' OR n.nspname = 'information_schema' THEN CASE c.relkind   WHEN 'r' THEN 'SYSTEM TABLE'   WHEN 'v' THEN 'SYSTEM VIEW'   WHEN 'i' THEN 'SYSTEM INDEX'   ELSE NULL   END  WHEN n.nspname = 'pg_toast' THEN CASE c.relkind   WHEN 'r' THEN 'SYSTEM TOAST TABLE'   WHEN 'i' THEN 'SYSTEM TOAST INDEX'   ELSE NULL   END  ELSE CASE c.relkind   WHEN 'r' THEN 'TEMPORARY TABLE'   WHEN 'p' THEN 'TEMPORARY TABLE'   WHEN 'i' THEN 'TEMPORARY INDEX'   WHEN 'S' THEN 'TEMPORARY SEQUENCE'   WHEN 'v' THEN 'TEMPORARY VIEW'   ELSE NULL   END  END  WHEN false THEN CASE c.relkind  WHEN 'r' THEN 'TABLE'  WHEN 'p' THEN 'PARTITIONED TABLE'  WHEN 'i' THEN 'INDEX'  WHEN 'P' then 'PARTITIONED INDEX'  WHEN 'S' THEN 'SEQUENCE'  WHEN 'v' THEN 'VIEW'  WHEN 'c' THEN 'TYPE'  WHEN 'f' THEN 'FOREIGN TABLE'  WHEN 'm' THEN 'MATERIALIZED VIEW'  ELSE NULL  END  ELSE NULL  END  AS "TABLE_TYPE", d.description AS "REMARKS",  '' as "TYPE_CAT", '' as "TYPE_SCHEM", '' as "TYPE_NAME", '' AS "SELF_REFERENCING_COL_NAME", '' AS "REF_GENERATION"  FROM pg_catalog.pg_namespace n, pg_catalog.pg_class c  LEFT JOIN pg_catalog.pg_description d ON (c.oid = d.objoid AND d.objsubid = 0  and d.classoid = 'pg_class'::regclass)  WHERE c.relnamespace = n.oid  AND c.relname LIKE $1 ORDER BY "TABLE_TYPE","TABLE_SCHEM","TABLE_NAME" `
	metadataColumns = `SELECT * FROM (SELECT current_database() AS current_database, n.nspname,c.relname,a.attname,a.atttypid,a.attnotnull  OR (t.typtype = 'd' AND t.typnotnull) AS attnotnull,a.atttypmod,a.attlen,t.typtypmod,row_number() OVER (PARTITION BY a.attrelid ORDER BY a.attnum) AS attnum, nullif(a.attidentity, '') as attidentity,nullif(a.attgenerated, '') as attgenerated,pg_catalog.pg_get_expr(def.adbin, def.adrelid) AS adsrc,dsc.description,t.typbasetype,t.typtype  FROM pg_catalog.pg_namespace n  JOIN pg_catalog.pg_class c ON (c.relnamespace = n.oid)  JOIN pg_catalog.pg_attribute a ON (a.attrelid=c.oid)  JOIN pg_catalog.pg_type t ON (a.atttypid = t.oid)  LEFT JOIN pg_catalog.pg_attrdef def ON (a.attrelid=def.adrelid AND a.attnum = def.adnum)  LEFT JOIN pg_catalog.pg_description dsc ON (c.oid=dsc.objoid AND a.attnum = dsc.objsubid)  LEFT JOIN pg_catalog.pg_class dc ON (dc.oid=dsc.classoid AND dc.relname='pg_class')  LEFT JOIN pg_catalog.pg_namespace dn ON (dc.relnamespace=dn.oid AND dn.nspname='pg_catalog')  WHERE c.relkind in ('r','p','v','f','m') and a.attnum > 0 AND NOT a.attisdropped  AND n.nspname LIKE $1 AND c.relname LIKE $2) c WHERE true  ORDER BY nspname,c.relname,attnum `
)

var described = struct {
	sync.Mutex
	tables map[string]bool
}{tables: map[string]bool{}}

// describeTable sends the reference's first-insert metadata queries for table, once per process, inside the
// caller's transaction, as SimpleJdbcInsert does just before its first INSERT.
func describeTable(ctx context.Context, q querier, table string) error {
	described.Lock()
	defer described.Unlock()
	if described.tables[table] {
		return nil
	}
	rows, err := q.QueryContext(ctx, metadataTables, table)
	if err != nil {
		return err
	}
	names, err := rows.Columns()
	if err != nil {
		rows.Close()
		return err
	}
	schema := ""
	for rows.Next() {
		values := make([]any, len(names))
		pointers := make([]any, len(values))
		for i := range values {
			pointers[i] = &values[i]
		}
		if err := rows.Scan(pointers...); err != nil {
			rows.Close()
			return err
		}
		if s, ok := values[1].(string); ok && schema == "" {
			schema = s
		}
	}
	if err := rows.Close(); err != nil {
		return err
	}
	columns, err := q.QueryContext(ctx, metadataColumns, schema, table)
	if err != nil {
		return err
	}
	for columns.Next() {
	}
	if err := columns.Close(); err != nil {
		return err
	}
	described.tables[table] = true
	return nil
}

// collect reads every row of a query.
func collect[T any](ctx context.Context, q querier, scan func(*sql.Rows) (T, error), query string, args ...any) ([]T, error) {
	rows, err := q.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []T
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func count(ctx context.Context, q querier, query string, args ...any) (int64, error) {
	var n int64
	err := q.QueryRowContext(ctx, query, args...).Scan(&n)
	return n, err
}

// ---------------------------------------------------------------------------------------------------------------
// Owners (JdbcOwnerRepositoryImpl)

const selectOwners = "SELECT id, first_name, last_name, address, city, telephone FROM owners"

func scanOwner(rows interface{ Scan(...any) error }) (*Owner, error) {
	o := &Owner{Pets: []*Pet{}}
	err := rows.Scan(&o.ID, &o.FirstName, &o.LastName, &o.Address, &o.City, &o.Telephone)
	return o, err
}

func scanOwnerRow(rows *sql.Rows) (*Owner, error) { return scanOwner(rows) }

// findOwner is ClinicService.findOwnerById: nil when there is no such owner.
func findOwner(ctx context.Context, q querier, id int) (*Owner, error) {
	o, err := scanOwner(q.QueryRowContext(ctx, selectOwners+" WHERE id= $1", id))
	if err == nil {
		err = loadPetsAndVisits(ctx, q, o)
	}
	if absent(err) {
		return nil, nil
	}
	return o, err
}

func findAllOwners(ctx context.Context, q querier) ([]*Owner, error) {
	owners, err := collect(ctx, q, scanOwnerRow, selectOwners)
	if err != nil {
		return nil, err
	}
	return owners, loadOwnersPetsAndVisits(ctx, q, owners)
}

func findOwnersByLastName(ctx context.Context, q querier, lastName string) ([]*Owner, error) {
	owners, err := collect(ctx, q, scanOwnerRow, selectOwners+" WHERE last_name like $1", lastName+"%")
	if err != nil {
		return nil, err
	}
	return owners, loadOwnersPetsAndVisits(ctx, q, owners)
}

// findOwnersPage is ClinicService.findOwners: by last name prefix when lastName is given, else all, ordered by id.
func findOwnersPage(ctx context.Context, q querier, lastName *string, page, size int) (Page[*Owner], error) {
	offset := int64(page) * int64(size)
	var owners []*Owner
	var total int64
	var err error
	if lastName != nil {
		pattern := *lastName + "%"
		owners, err = collect(ctx, q, scanOwnerRow,
			selectOwners+" WHERE last_name like $1 ORDER BY id LIMIT $2 OFFSET $3", pattern, size, offset)
		if err == nil {
			err = loadOwnersPetsAndVisits(ctx, q, owners)
		}
		if err == nil {
			total, err = count(ctx, q, "SELECT COUNT(*) FROM owners WHERE last_name like $1", pattern)
		}
	} else {
		owners, err = collect(ctx, q, scanOwnerRow, selectOwners+" ORDER BY id LIMIT $1 OFFSET $2", size, offset)
		if err == nil {
			err = loadOwnersPetsAndVisits(ctx, q, owners)
		}
		if err == nil {
			total, err = count(ctx, q, "SELECT COUNT(*) FROM owners")
		}
	}
	if err != nil {
		return Page[*Owner]{}, err
	}
	if owners == nil {
		owners = []*Owner{}
	}
	return newPage(owners, page, size, total), nil
}

func loadOwnersPetsAndVisits(ctx context.Context, q querier, owners []*Owner) error {
	for _, o := range owners {
		if err := loadPetsAndVisits(ctx, q, o); err != nil {
			return err
		}
	}
	return nil
}

// loadPetsAndVisits loads an owner's pets with their visits in one outer join (JdbcPetVisitExtractor), then the
// pet types, as JdbcOwnerRepositoryImpl.loadPetsAndVisits does.
func loadPetsAndVisits(ctx context.Context, q querier, owner *Owner) error {
	rows, err := q.QueryContext(ctx, "SELECT pets.id as pets_id, name, birth_date, type_id, owner_id, visits.id as visit_id, "+
		"visit_date, description, visits.pet_id as visits_pet_id FROM pets LEFT OUTER JOIN visits ON pets.id = visits.pet_id "+
		"WHERE owner_id=$1 ORDER BY pets.id", owner.ID)
	if err != nil {
		return err
	}
	var pets []*Pet
	err = func() error {
		defer rows.Close()
		var current *Pet
		for rows.Next() {
			var pet Pet
			var visitID, visitPetID sql.NullInt64
			var visitDate sql.NullTime
			var description sql.NullString
			if err := rows.Scan(&pet.ID, &pet.Name, &pet.BirthDate, &pet.typeID, &pet.OwnerID, &visitID, &visitDate,
				&description, &visitPetID); err != nil {
				return err
			}
			if current == nil || current.ID != pet.ID {
				pet.Visits = []Visit{}
				current = &pet
				pets = append(pets, current)
			}
			if visitPetID.Valid {
				current.Visits = append(current.Visits, Visit{ID: int(visitID.Int64), Date: Date{visitDate.Time},
					Description: description.String, PetID: current.ID})
			}
		}
		return rows.Err()
	}()
	if err != nil {
		return err
	}
	types, err := petTypesByName(ctx, q)
	if err != nil {
		return err
	}
	for _, pet := range pets {
		if pet.Type, err = petTypeByID(types, pet.typeID); err != nil {
			return err
		}
		pet.OwnerID = owner.ID
		sortVisits(pet.Visits)
	}
	sortPets(pets)
	if pets != nil {
		owner.Pets = pets
	}
	return nil
}

func petTypesByName(ctx context.Context, q querier) ([]PetType, error) {
	return collect(ctx, q, scanPetType, "SELECT id, name FROM types ORDER BY name")
}

// petTypeByID is EntityUtils.getById over the pet types.
func petTypeByID(types []PetType, id int) (PetType, error) {
	for _, t := range types {
		if t.ID == id {
			return t, nil
		}
	}
	return PetType{}, errRetrieval
}

func saveOwner(ctx context.Context, q querier, o *Owner) error {
	if o.ID == 0 {
		if err := describeTable(ctx, q, "owners"); err != nil {
			return err
		}
		return q.QueryRowContext(ctx, "INSERT INTO owners (first_name, last_name, address, city, telephone) "+
			"VALUES ($1, $2, $3, $4, $5) RETURNING id", o.FirstName, o.LastName, o.Address, o.City, o.Telephone).Scan(&o.ID)
	}
	_, err := q.ExecContext(ctx, "UPDATE owners SET first_name=$1, last_name=$2, address=$3, city=$4, telephone=$5 WHERE id=$6",
		o.FirstName, o.LastName, o.Address, o.City, o.Telephone, o.ID)
	return err
}

// deleteOwner deletes the owner's visits and pets one by one, then the owner.
func deleteOwner(ctx context.Context, q querier, o *Owner) error {
	for _, pet := range o.Pets {
		if err := deletePet(ctx, q, pet); err != nil {
			return err
		}
	}
	_, err := q.ExecContext(ctx, "DELETE FROM owners WHERE id=$1", o.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Pets (JdbcPetRepositoryImpl)

func scanPetRow(rows *sql.Rows) (*Pet, error) {
	pet := &Pet{Visits: []Visit{}}
	err := rows.Scan(&pet.ID, &pet.Name, &pet.BirthDate, &pet.typeID, &pet.OwnerID)
	return pet, err
}

// findPet is ClinicService.findPetById: the pet's owner id, then the owner with all its pets.
func findPet(ctx context.Context, q querier, id int) (*Pet, error) {
	var ownerID int
	if err := q.QueryRowContext(ctx, "SELECT owner_id FROM pets WHERE id=$1", id).Scan(&ownerID); err != nil {
		if absent(err) {
			return nil, nil
		}
		return nil, err
	}
	owner, err := findOwner(ctx, q, ownerID)
	if err != nil || owner == nil {
		return nil, err
	}
	for _, pet := range owner.Pets {
		if pet.ID == id {
			return pet, nil
		}
	}
	return nil, nil
}

// resolvePets sets each pet's type and owner from the full lists, as JdbcPetRepositoryImpl.findAll does.
func resolvePets(ctx context.Context, q querier, pets []*Pet) error {
	types, err := petTypesByName(ctx, q)
	if err != nil {
		return err
	}
	owners, err := collect(ctx, q, scanOwnerRow, selectOwners+" ORDER BY last_name")
	if err != nil {
		return err
	}
	for _, pet := range pets {
		if pet.Type, err = petTypeByID(types, pet.typeID); err != nil {
			return err
		}
		found := false
		for _, o := range owners {
			if o.ID == pet.OwnerID {
				found = true
				break
			}
		}
		if !found {
			return errRetrieval
		}
	}
	return nil
}

func findAllPets(ctx context.Context, q querier) ([]*Pet, error) {
	pets, err := collect(ctx, q, scanPetRow, "SELECT pets.id as pets_id, name, birth_date, type_id, owner_id FROM pets")
	if err != nil {
		return nil, err
	}
	return pets, resolvePets(ctx, q, pets)
}

func findPetsPage(ctx context.Context, q querier, page, size int) (Page[*Pet], error) {
	pets, err := collect(ctx, q, scanPetRow,
		"SELECT pets.id as pets_id, name, birth_date, type_id, owner_id FROM pets ORDER BY id LIMIT $1 OFFSET $2",
		size, int64(page)*int64(size))
	if err == nil {
		err = resolvePets(ctx, q, pets)
	}
	var total int64
	if err == nil {
		total, err = count(ctx, q, "SELECT count(*) FROM pets")
	}
	if err != nil {
		return Page[*Pet]{}, err
	}
	if pets == nil {
		pets = []*Pet{}
	}
	return newPage(pets, page, size, total), nil
}

// savePet resolves the pet's type (ClinicServiceImpl.savePet), then inserts or updates the pet. It runs in a
// transaction, as the service method does.
func savePet(ctx context.Context, q querier, pet *Pet) error {
	t, err := findPetType(ctx, q, pet.Type.ID)
	if err != nil {
		return err
	}
	if t == nil {
		return errNullPointer // ClinicServiceImpl.savePet dereferences the missing type
	}
	pet.Type = *t
	if pet.ID == 0 {
		if err := describeTable(ctx, q, "pets"); err != nil {
			return err
		}
		return q.QueryRowContext(ctx, "INSERT INTO pets (name, birth_date, type_id, owner_id) VALUES ($1, $2, $3, $4) RETURNING id",
			pet.Name, pet.BirthDate, pet.Type.ID, pet.OwnerID).Scan(&pet.ID)
	}
	_, err = q.ExecContext(ctx, "UPDATE pets SET name=$1, birth_date=$2, type_id=$3, owner_id=$4 WHERE id=$5",
		pet.Name, pet.BirthDate, pet.Type.ID, pet.OwnerID, pet.ID)
	return err
}

// deletePet deletes the pet's visits one by one, then the pet.
func deletePet(ctx context.Context, q querier, pet *Pet) error {
	for _, v := range pet.Visits {
		if _, err := q.ExecContext(ctx, "DELETE FROM visits WHERE id=$1", v.ID); err != nil {
			return err
		}
	}
	_, err := q.ExecContext(ctx, "DELETE FROM pets WHERE id=$1", pet.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Visits (JdbcVisitRepositoryImpl)

func scanVisitRow(rows *sql.Rows) (Visit, error) {
	var v Visit
	err := rows.Scan(&v.ID, &v.PetID, &v.Date, &v.Description)
	return v, err
}

// completeVisit runs JdbcVisitRowMapperExt's per-row queries: the pet, its type and its owner.
func completeVisit(ctx context.Context, q querier, v *Visit) error {
	var pet Pet
	err := q.QueryRowContext(ctx, "SELECT pets.id as pets_id, name, birth_date, type_id, owner_id FROM pets WHERE pets.id=$1",
		v.PetID).Scan(&pet.ID, &pet.Name, &pet.BirthDate, &pet.typeID, &pet.OwnerID)
	if err == nil {
		err = q.QueryRowContext(ctx, "SELECT id, name FROM types WHERE id= $1", pet.typeID).Scan(&pet.Type.ID, &pet.Type.Name)
	}
	if err == nil {
		_, err = scanOwner(q.QueryRowContext(ctx, selectOwners+" WHERE id= $1", pet.OwnerID))
	}
	if errors.Is(err, sql.ErrNoRows) {
		return errEmptyQuery
	}
	v.PetID = pet.ID
	return err
}

// findVisit is ClinicService.findVisitById.
func findVisit(ctx context.Context, q querier, id int) (*Visit, error) {
	var v Visit
	err := q.QueryRowContext(ctx, "SELECT id as visit_id, visits.pet_id as pets_id, visit_date, description FROM visits WHERE id= $1",
		id).Scan(&v.ID, &v.PetID, &v.Date, &v.Description)
	if err == nil {
		err = completeVisit(ctx, q, &v)
	}
	if absent(err) {
		return nil, nil
	}
	return &v, err
}

func findAllVisits(ctx context.Context, q querier) ([]Visit, error) {
	visits, err := collect(ctx, q, scanVisitRow, "SELECT visits.id as visit_id, pets.id as pets_id, visit_date, description "+
		"FROM visits LEFT JOIN pets ON visits.pet_id = pets.id")
	if err != nil {
		return nil, err
	}
	for i := range visits {
		if err := completeVisit(ctx, q, &visits[i]); err != nil {
			return nil, err
		}
	}
	return visits, nil
}

func saveVisit(ctx context.Context, q querier, v *Visit) error {
	if v.ID == 0 {
		if err := describeTable(ctx, q, "visits"); err != nil {
			return err
		}
		return q.QueryRowContext(ctx, "INSERT INTO visits (pet_id, visit_date, description) VALUES ($1, $2, $3) RETURNING id",
			v.PetID, v.Date, v.Description).Scan(&v.ID)
	}
	_, err := q.ExecContext(ctx, "UPDATE visits SET visit_date=$1, description=$2, pet_id=$3 WHERE id=$4 ",
		v.Date, v.Description, v.PetID, v.ID)
	return err
}

func deleteVisit(ctx context.Context, q querier, v *Visit) error {
	_, err := q.ExecContext(ctx, "DELETE FROM visits WHERE id=$1", v.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Pet types (JdbcPetTypeRepositoryImpl)

func scanPetType(rows *sql.Rows) (PetType, error) {
	var t PetType
	err := rows.Scan(&t.ID, &t.Name)
	return t, err
}

func findPetType(ctx context.Context, q querier, id int) (*PetType, error) {
	var t PetType
	err := q.QueryRowContext(ctx, "SELECT id, name FROM types WHERE id= $1", id).Scan(&t.ID, &t.Name)
	if absent(err) {
		return nil, nil
	}
	return &t, err
}

func findAllPetTypes(ctx context.Context, q querier) ([]PetType, error) {
	return collect(ctx, q, scanPetType, "SELECT id, name FROM types")
}

func savePetType(ctx context.Context, q querier, t *PetType) error {
	if t.ID == 0 {
		if err := describeTable(ctx, q, "types"); err != nil {
			return err
		}
		return q.QueryRowContext(ctx, "INSERT INTO types (name) VALUES ($1) RETURNING id", t.Name).Scan(&t.ID)
	}
	_, err := q.ExecContext(ctx, "UPDATE types SET name=$1 WHERE id=$2", t.Name, t.ID)
	return err
}

// deletePetType deletes the pets of the type with their visits, one by one, then the type.
func deletePetType(ctx context.Context, q querier, t *PetType) error {
	petIDs, err := collect(ctx, q, func(rows *sql.Rows) (int, error) {
		var pet Pet
		err := rows.Scan(&pet.ID, &pet.Name, &pet.BirthDate, &pet.typeID, &pet.OwnerID)
		return pet.ID, err
	}, "SELECT pets.id, name, birth_date, type_id, owner_id FROM pets WHERE type_id=$1", t.ID)
	if err != nil {
		return err
	}
	for _, petID := range petIDs {
		visits, err := collect(ctx, q, func(rows *sql.Rows) (Visit, error) {
			var v Visit
			err := rows.Scan(&v.ID, &v.PetID, &v.Date, &v.Description)
			return v, err
		}, "SELECT id, pet_id, visit_date, description FROM visits WHERE pet_id = $1", petID)
		if err != nil {
			return err
		}
		if err := deletePet(ctx, q, &Pet{ID: petID, Visits: visits}); err != nil {
			return err
		}
	}
	_, err = q.ExecContext(ctx, "DELETE FROM types WHERE id=$1", t.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Specialties (JdbcSpecialtyRepositoryImpl)

func scanSpecialty(rows *sql.Rows) (Specialty, error) {
	var s Specialty
	err := rows.Scan(&s.ID, &s.Name)
	return s, err
}

func findSpecialty(ctx context.Context, q querier, id int) (*Specialty, error) {
	var s Specialty
	err := q.QueryRowContext(ctx, "SELECT id, name FROM specialties WHERE id= $1", id).Scan(&s.ID, &s.Name)
	if absent(err) {
		return nil, nil
	}
	return &s, err
}

func findAllSpecialties(ctx context.Context, q querier) ([]Specialty, error) {
	return collect(ctx, q, scanSpecialty, "SELECT id, name FROM specialties")
}

// findSpecialtiesByNameIn expands the name list into placeholders, as NamedParameterJdbcTemplate does.
func findSpecialtiesByNameIn(ctx context.Context, q querier, names []string) ([]Specialty, error) {
	var query strings.Builder
	query.WriteString("SELECT id, name FROM specialties WHERE specialties.name IN (")
	args := make([]any, len(names))
	for i, name := range names {
		if i > 0 {
			query.WriteString(", ")
		}
		query.WriteString("$" + strconv.Itoa(i+1))
		args[i] = name
	}
	query.WriteString(")")
	return collect(ctx, q, scanSpecialty, query.String(), args...)
}

func saveSpecialty(ctx context.Context, q querier, s *Specialty) error {
	if s.ID == 0 {
		if err := describeTable(ctx, q, "specialties"); err != nil {
			return err
		}
		return q.QueryRowContext(ctx, "INSERT INTO specialties (name) VALUES ($1) RETURNING id", s.Name).Scan(&s.ID)
	}
	_, err := q.ExecContext(ctx, "UPDATE specialties SET name=$1 WHERE id=$2", s.Name, s.ID)
	return err
}

func deleteSpecialty(ctx context.Context, q querier, s *Specialty) error {
	if _, err := q.ExecContext(ctx, "DELETE FROM vet_specialties WHERE specialty_id=$1", s.ID); err != nil {
		return err
	}
	_, err := q.ExecContext(ctx, "DELETE FROM specialties WHERE id=$1", s.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Vets (JdbcVetRepositoryImpl)

func scanVet(rows interface{ Scan(...any) error }) (*Vet, error) {
	v := &Vet{Specialties: []Specialty{}}
	err := rows.Scan(&v.ID, &v.FirstName, &v.LastName)
	return v, err
}

func scanVetRow(rows *sql.Rows) (*Vet, error) { return scanVet(rows) }

func scanInt(rows *sql.Rows) (int, error) {
	var n int
	err := rows.Scan(&n)
	return n, err
}

// loadVetSpecialties reads the vet's specialty ids and resolves them against all specialties.
func loadVetSpecialties(ctx context.Context, q querier, vet *Vet, all []Specialty) error {
	ids, err := collect(ctx, q, scanInt, "SELECT specialty_id FROM vet_specialties WHERE vet_id=$1", vet.ID)
	if err != nil {
		return err
	}
	for _, id := range ids {
		found := false
		for _, s := range all {
			if s.ID == id {
				vet.Specialties = append(vet.Specialties, s)
				found = true
				break
			}
		}
		if !found {
			return errRetrieval
		}
	}
	sortSpecialties(vet.Specialties)
	return nil
}

func findAllVets(ctx context.Context, q querier) ([]*Vet, error) {
	vets, err := collect(ctx, q, scanVetRow, "SELECT id, first_name, last_name FROM vets ORDER BY last_name,first_name")
	if err != nil {
		return nil, err
	}
	all, err := findAllSpecialties(ctx, q)
	if err != nil {
		return nil, err
	}
	for _, vet := range vets {
		if err := loadVetSpecialties(ctx, q, vet, all); err != nil {
			return nil, err
		}
	}
	return vets, nil
}

func findVet(ctx context.Context, q querier, id int) (*Vet, error) {
	vet, err := scanVet(q.QueryRowContext(ctx, "SELECT id, first_name, last_name FROM vets WHERE id= $1", id))
	if err == nil {
		var all []Specialty
		if all, err = findAllSpecialties(ctx, q); err == nil {
			err = loadVetSpecialties(ctx, q, vet, all)
		}
	}
	if absent(err) {
		return nil, nil
	}
	return vet, err
}

// saveVet inserts or updates the vet, then replaces its specialty links.
func saveVet(ctx context.Context, q querier, vet *Vet) error {
	var err error
	if vet.ID == 0 {
		if err := describeTable(ctx, q, "vets"); err != nil {
			return err
		}
		err = q.QueryRowContext(ctx, "INSERT INTO vets (first_name, last_name) VALUES ($1, $2) RETURNING id",
			vet.FirstName, vet.LastName).Scan(&vet.ID)
	} else {
		_, err = q.ExecContext(ctx, "UPDATE vets SET first_name=$1, last_name=$2 WHERE id=$3", vet.FirstName, vet.LastName, vet.ID)
	}
	if err != nil {
		return err
	}
	if _, err := q.ExecContext(ctx, "DELETE FROM vet_specialties WHERE vet_id=$1", vet.ID); err != nil {
		return err
	}
	for _, s := range vet.Specialties {
		if s.ID == 0 {
			continue
		}
		if _, err := q.ExecContext(ctx, "INSERT INTO vet_specialties VALUES ($1, $2)", vet.ID, s.ID); err != nil {
			return err
		}
	}
	return nil
}

func deleteVet(ctx context.Context, q querier, vet *Vet) error {
	if _, err := q.ExecContext(ctx, "DELETE FROM vet_specialties WHERE vet_id=$1", vet.ID); err != nil {
		return err
	}
	_, err := q.ExecContext(ctx, "DELETE FROM vets WHERE id=$1", vet.ID)
	return err
}

// ---------------------------------------------------------------------------------------------------------------
// Users (JdbcUserRepositoryImpl)

// saveUser updates the user when the username exists and inserts it otherwise, then, as the reference's finally
// block does whether or not that succeeded, replaces the user's roles.
func saveUser(ctx context.Context, q querier, u *User) error {
	var username, password string
	var enabled bool
	err := q.QueryRowContext(ctx, "SELECT * FROM users WHERE username=$1", u.Username).Scan(&username, &password, &enabled)
	switch {
	case err == nil:
		_, err = q.ExecContext(ctx, "UPDATE users SET password=$1, enabled=$2 WHERE username=$3", u.Password, u.Enabled, u.Username)
	case errors.Is(err, sql.ErrNoRows):
		if err := describeTable(ctx, q, "users"); err != nil {
			return err
		}
		_, err = q.ExecContext(ctx, "INSERT INTO users (username, password, enabled) VALUES ($1, $2, $3)",
			u.Username, u.Password, u.Enabled)
	}
	if rolesErr := updateUserRoles(ctx, q, u); rolesErr != nil {
		return rolesErr
	}
	return err
}

func updateUserRoles(ctx context.Context, q querier, u *User) error {
	if _, err := q.ExecContext(ctx, "DELETE FROM roles WHERE username=$1", u.Username); err != nil {
		return err
	}
	for _, role := range u.Roles {
		if _, err := q.ExecContext(ctx, "INSERT INTO roles(username, role) VALUES ($1, $2)", u.Username, role.Name); err != nil {
			return err
		}
	}
	return nil
}
