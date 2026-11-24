package main

import (
	"database/sql"
	"net/http"
	"strconv"
)

// The REST controllers (rest/controller/v1 and v2). Each handler follows the order in which Spring resolves the
// arguments and runs the method: path variables are converted, the body is read and validated, method validation
// checks the @Min constraints, then the controller and service logic run.

type clinic struct {
	db *sql.DB
}

func routes(c *clinic) *http.ServeMux {
	mux := http.NewServeMux()
	api(mux, "/api/owners", onGet(c.listOwners), onPost(c.addOwner))
	api(mux, "/api/owners/{ownerId}", onGet(c.getOwner), onPut(c.updateOwner), onDelete(c.deleteOwner))
	api(mux, "/api/owners/{ownerId}/pets", onPost(c.addPetToOwner))
	api(mux, "/api/owners/{ownerId}/pets/{petId}", onGet(c.getOwnersPet), onPut(c.updateOwnersPet))
	api(mux, "/api/owners/{ownerId}/pets/{petId}/visits", onPost(c.addVisitToOwner))
	api(mux, "/api/v2/owners", onGet(c.listOwnersPage))
	api(mux, "/api/pets", onGet(c.listPets))
	api(mux, "/api/pets/{petId}", onGet(c.getPet), onPut(c.updatePet), onDelete(c.deletePet))
	api(mux, "/api/v2/pets", onGet(c.listPetsPage))
	api(mux, "/api/visits", onGet(c.listVisits), onPost(c.addVisit))
	api(mux, "/api/visits/{visitId}", onGet(c.getVisit), onPut(c.updateVisit), onDelete(c.deleteVisit))
	api(mux, "/api/pettypes", onGet(c.listPetTypes), onPost(c.addPetType))
	api(mux, "/api/pettypes/{petTypeId}", onGet(c.getPetType), onPut(c.updatePetType), onDelete(c.deletePetType))
	api(mux, "/api/specialties", onGet(c.listSpecialties), onPost(c.addSpecialty))
	api(mux, "/api/specialties/{specialtyId}", onGet(c.getSpecialty), onPut(c.updateSpecialty), onDelete(c.deleteSpecialty))
	api(mux, "/api/vets", onGet(c.listVets), onPost(c.addVet))
	api(mux, "/api/vets/{vetId}", onGet(c.getVet), onPut(c.updateVet), onDelete(c.deleteVet))
	api(mux, "/api/users", onPost(c.addUser))
	actuator(mux, "/actuator", c.actuatorLinks)
	actuator(mux, "/actuator/health", c.health)
	actuator(mux, "/actuator/health/{path...}", c.healthGroup)
	mux.HandleFunc(contextPath+"/{$}", rootRedirect)
	mux.HandleFunc(contextPath+"/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			options(w)
			return
		}
		fail(w, r, errNoResource) // the static resource handler finds nothing
	})
	return mux
}

// rootRedirect is RootRestControllerV1: every method on / redirects to the Swagger UI. Its CORS configuration
// admits the default methods, GET, HEAD and POST.
func rootRedirect(w http.ResponseWriter, r *http.Request) {
	allowed := []string{http.MethodGet, http.MethodHead, http.MethodPost}
	switch {
	case isPreflight(r):
		if methodAllowed(r.Header.Get("Access-Control-Request-Method"), allowed) {
			preflight(w, r, allowed...)
		} else {
			options(w)
		}
		return
	case r.Method == http.MethodOptions:
		options(w)
		return
	}
	if cors(w, r, allowed...) {
		w.Header().Set("Location", contextPath+"/swagger-ui/index.html")
		w.WriteHeader(http.StatusFound)
	}
}

func location(collection string, id int) string { return "/api/" + collection + "/" + strconv.Itoa(id) }

// ---------------------------------------------------------------------------------------------------------------
// Owners

func (c *clinic) listOwners(w http.ResponseWriter, r *http.Request) error {
	var owners []*Owner
	var err error
	if lastName, present := queryParam(r, "lastName"); present {
		owners, err = readOnly(r.Context(), c.db, func(q querier) ([]*Owner, error) { return findOwnersByLastName(r.Context(), q, lastName) })
	} else {
		owners, err = readOnly(r.Context(), c.db, func(q querier) ([]*Owner, error) { return findAllOwners(r.Context(), q) })
	}
	if err != nil {
		return err
	}
	if len(owners) == 0 {
		notFound(w)
		return nil
	}
	ok(w, owners)
	return nil
}

func (c *clinic) getOwner(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	if err := minZero(ownerID); err != nil {
		return err
	}
	owner, err := readOnly(r.Context(), c.db, func(q querier) (*Owner, error) { return findOwner(r.Context(), q, ownerID) })
	if err != nil {
		return err
	}
	if owner == nil {
		notFound(w)
		return nil
	}
	ok(w, owner)
	return nil
}

func (c *clinic) addOwner(w http.ResponseWriter, r *http.Request) error {
	var body *ownerFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	owner := &Owner{FirstName: body.FirstName.value, LastName: body.LastName.value, Address: body.Address.value,
		City: body.City.value, Telephone: body.Telephone.value, Pets: []*Pet{}}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveOwner(r.Context(), tx, owner) }); err != nil {
		return err
	}
	created(w, location("owners", owner.ID), owner)
	return nil
}

func (c *clinic) updateOwner(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	var body *ownerFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(ownerID); err != nil {
		return err
	}
	owner, err := readOnly(r.Context(), c.db, func(q querier) (*Owner, error) { return findOwner(r.Context(), q, ownerID) })
	if err != nil {
		return err
	}
	if owner == nil {
		notFound(w)
		return nil
	}
	owner.Address, owner.City = body.Address.value, body.City.value
	owner.FirstName, owner.LastName = body.FirstName.value, body.LastName.value
	owner.Telephone = body.Telephone.value
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveOwner(r.Context(), tx, owner) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deleteOwner(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	if err := minZero(ownerID); err != nil {
		return err
	}
	found := false
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error {
		owner, err := findOwner(r.Context(), tx, ownerID)
		if err != nil || owner == nil {
			return err
		}
		found = true
		return deleteOwner(r.Context(), tx, owner)
	})
	return finishDelete(w, found, err)
}

// finishDelete answers a delete: 204, or an empty 404 when the entity was not there.
func finishDelete(w http.ResponseWriter, found bool, err error) error {
	switch {
	case err != nil:
		return err
	case !found:
		notFound(w)
	default:
		noContent(w, false)
	}
	return nil
}

func (c *clinic) addPetToOwner(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	var body *petFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(ownerID); err != nil {
		return err
	}
	owner, err := readOnly(r.Context(), c.db, func(q querier) (*Owner, error) { return findOwner(r.Context(), q, ownerID) })
	if err != nil {
		return err
	}
	if owner == nil {
		notFound(w)
		return nil
	}
	pet := &Pet{Name: body.Name.value, BirthDate: body.BirthDate.value, Type: PetType{ID: body.Type.ID.value},
		Visits: []Visit{}, OwnerID: owner.ID}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return savePet(r.Context(), tx, pet) }); err != nil {
		return err
	}
	created(w, location("pets", pet.ID), pet)
	return nil
}

func (c *clinic) getOwnersPet(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	if err := minZero(ownerID, petID); err != nil {
		return err
	}
	owner, err := readOnly(r.Context(), c.db, func(q querier) (*Owner, error) { return findOwner(r.Context(), q, ownerID) })
	if err != nil {
		return err
	}
	if owner != nil {
		for _, pet := range owner.Pets {
			if pet.ID == petID {
				ok(w, pet)
				return nil
			}
		}
	}
	notFound(w)
	return nil
}

func (c *clinic) updateOwnersPet(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	var body *petFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(ownerID, petID); err != nil {
		return err
	}
	owner, err := readOnly(r.Context(), c.db, func(q querier) (*Owner, error) { return findOwner(r.Context(), q, ownerID) })
	if err != nil || owner == nil {
		return notFoundUnless(w, err)
	}
	pet, err := readOnly(r.Context(), c.db, func(q querier) (*Pet, error) { return findPet(r.Context(), q, petID) })
	if err != nil || pet == nil {
		return notFoundUnless(w, err)
	}
	pet.BirthDate, pet.Name, pet.Type = body.BirthDate.value, body.Name.value, PetType{ID: body.Type.ID.value}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return savePet(r.Context(), tx, pet) }); err != nil {
		return err
	}
	noContent(w, false)
	return nil
}

// notFoundUnless returns err, or answers an empty 404 when there is none.
func notFoundUnless(w http.ResponseWriter, err error) error {
	if err == nil {
		notFound(w)
	}
	return err
}

func (c *clinic) addVisitToOwner(w http.ResponseWriter, r *http.Request) error {
	ownerID, err := pathInt(r, "ownerId")
	if err != nil {
		return err
	}
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	var body *visitFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(ownerID, petID); err != nil {
		return err
	}
	visit := &Visit{Date: body.Date.value, Description: body.Description.value, PetID: petID}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveVisit(r.Context(), tx, visit) }); err != nil {
		return err
	}
	created(w, location("visits", visit.ID), visit)
	return nil
}

func (c *clinic) listOwnersPage(w http.ResponseWriter, r *http.Request) error {
	var lastName *string
	if value, present := queryParam(r, "lastName"); present {
		lastName = &value
	}
	page, size, err := pageParams(r)
	if err != nil {
		return err
	}
	owners, err := readOnly(r.Context(), c.db, func(q querier) (Page[*Owner], error) { return findOwnersPage(r.Context(), q, lastName, page, size) })
	if err != nil {
		return err
	}
	ok(w, owners)
	return nil
}

// pageParams reads page (default 0, @Min(0)) and size (default 20, @Min(1) @Max(100)).
func pageParams(r *http.Request) (page, size int, err error) {
	if page, err = queryInt(r, "page", 0); err != nil {
		return 0, 0, err
	}
	if size, err = queryInt(r, "size", 20); err != nil {
		return 0, 0, err
	}
	if page < 0 || size < 1 || size > 100 {
		return 0, 0, errConstraint
	}
	return page, size, nil
}

// ---------------------------------------------------------------------------------------------------------------
// Pets

func (c *clinic) listPets(w http.ResponseWriter, r *http.Request) error {
	pets, err := readOnly(r.Context(), c.db, func(q querier) ([]*Pet, error) { return findAllPets(r.Context(), q) })
	if err != nil {
		return err
	}
	if len(pets) == 0 {
		notFound(w)
		return nil
	}
	ok(w, pets)
	return nil
}

func (c *clinic) listPetsPage(w http.ResponseWriter, r *http.Request) error {
	page, size, err := pageParams(r)
	if err != nil {
		return err
	}
	pets, err := readOnly(r.Context(), c.db, func(q querier) (Page[*Pet], error) { return findPetsPage(r.Context(), q, page, size) })
	if err != nil {
		return err
	}
	ok(w, pets)
	return nil
}

func (c *clinic) getPet(w http.ResponseWriter, r *http.Request) error {
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	if err := minZero(petID); err != nil {
		return err
	}
	pet, err := readOnly(r.Context(), c.db, func(q querier) (*Pet, error) { return findPet(r.Context(), q, petID) })
	if err != nil || pet == nil {
		return notFoundUnless(w, err)
	}
	ok(w, pet)
	return nil
}

func (c *clinic) updatePet(w http.ResponseWriter, r *http.Request) error {
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	var body *petBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(petID); err != nil {
		return err
	}
	pet, err := readOnly(r.Context(), c.db, func(q querier) (*Pet, error) { return findPet(r.Context(), q, petID) })
	if err != nil || pet == nil {
		return notFoundUnless(w, err)
	}
	pet.BirthDate, pet.Name, pet.Type = body.BirthDate.value, body.Name.value, PetType{ID: body.Type.ID.value}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return savePet(r.Context(), tx, pet) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deletePet(w http.ResponseWriter, r *http.Request) error {
	petID, err := pathInt(r, "petId")
	if err != nil {
		return err
	}
	if err := minZero(petID); err != nil {
		return err
	}
	pet, err := readOnly(r.Context(), c.db, func(q querier) (*Pet, error) { return findPet(r.Context(), q, petID) })
	if err != nil || pet == nil {
		return notFoundUnless(w, err)
	}
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error { return deletePet(r.Context(), tx, pet) })
	return finishDelete(w, true, err)
}

// ---------------------------------------------------------------------------------------------------------------
// Visits

func (c *clinic) listVisits(w http.ResponseWriter, r *http.Request) error {
	visits, err := readOnly(r.Context(), c.db, func(q querier) ([]Visit, error) { return findAllVisits(r.Context(), q) })
	if err != nil {
		return err
	}
	if len(visits) == 0 {
		notFound(w)
		return nil
	}
	ok(w, visits)
	return nil
}

func (c *clinic) getVisit(w http.ResponseWriter, r *http.Request) error {
	visitID, err := pathInt(r, "visitId")
	if err != nil {
		return err
	}
	if err := minZero(visitID); err != nil {
		return err
	}
	visit, err := readOnly(r.Context(), c.db, func(q querier) (*Visit, error) { return findVisit(r.Context(), q, visitID) })
	if err != nil || visit == nil {
		return notFoundUnless(w, err)
	}
	ok(w, visit)
	return nil
}

// addVisit saves the VisitDto as given: with an id, the reference updates that visit instead of inserting.
func (c *clinic) addVisit(w http.ResponseWriter, r *http.Request) error {
	var body *visitBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	visit := &Visit{Date: body.Date.value, Description: body.Description.value, ID: body.ID.value, PetID: body.PetID.value}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveVisit(r.Context(), tx, visit) }); err != nil {
		return err
	}
	created(w, location("visits", visit.ID), visit)
	return nil
}

func (c *clinic) updateVisit(w http.ResponseWriter, r *http.Request) error {
	visitID, err := pathInt(r, "visitId")
	if err != nil {
		return err
	}
	var body *visitFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(visitID); err != nil {
		return err
	}
	visit, err := readOnly(r.Context(), c.db, func(q querier) (*Visit, error) { return findVisit(r.Context(), q, visitID) })
	if err != nil || visit == nil {
		return notFoundUnless(w, err)
	}
	visit.Date, visit.Description = body.Date.value, body.Description.value
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveVisit(r.Context(), tx, visit) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deleteVisit(w http.ResponseWriter, r *http.Request) error {
	visitID, err := pathInt(r, "visitId")
	if err != nil {
		return err
	}
	if err := minZero(visitID); err != nil {
		return err
	}
	found := false
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error {
		visit, err := findVisit(r.Context(), tx, visitID)
		if err != nil || visit == nil {
			return err
		}
		found = true
		return deleteVisit(r.Context(), tx, visit)
	})
	return finishDelete(w, found, err)
}

// ---------------------------------------------------------------------------------------------------------------
// Pet types

func (c *clinic) listPetTypes(w http.ResponseWriter, r *http.Request) error {
	types, err := readOnly(r.Context(), c.db, func(q querier) ([]PetType, error) { return findAllPetTypes(r.Context(), q) })
	if err != nil {
		return err
	}
	if len(types) == 0 {
		notFound(w)
		return nil
	}
	ok(w, types)
	return nil
}

func (c *clinic) getPetType(w http.ResponseWriter, r *http.Request) error {
	typeID, err := pathInt(r, "petTypeId")
	if err != nil {
		return err
	}
	if err := minZero(typeID); err != nil {
		return err
	}
	t, err := readOnly(r.Context(), c.db, func(q querier) (*PetType, error) { return findPetType(r.Context(), q, typeID) })
	if err != nil || t == nil {
		return notFoundUnless(w, err)
	}
	ok(w, t)
	return nil
}

func (c *clinic) addPetType(w http.ResponseWriter, r *http.Request) error {
	var body *petTypeFields
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	t := &PetType{Name: body.Name.value}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return savePetType(r.Context(), tx, t) }); err != nil {
		return err
	}
	created(w, location("pettypes", t.ID), t)
	return nil
}

func (c *clinic) updatePetType(w http.ResponseWriter, r *http.Request) error {
	typeID, err := pathInt(r, "petTypeId")
	if err != nil {
		return err
	}
	var body *petTypeBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(typeID); err != nil {
		return err
	}
	t, err := readOnly(r.Context(), c.db, func(q querier) (*PetType, error) { return findPetType(r.Context(), q, typeID) })
	if err != nil || t == nil {
		return notFoundUnless(w, err)
	}
	t.Name = body.Name.value
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return savePetType(r.Context(), tx, t) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deletePetType(w http.ResponseWriter, r *http.Request) error {
	typeID, err := pathInt(r, "petTypeId")
	if err != nil {
		return err
	}
	if err := minZero(typeID); err != nil {
		return err
	}
	found := false
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error {
		t, err := findPetType(r.Context(), tx, typeID)
		if err != nil || t == nil {
			return err
		}
		found = true
		return deletePetType(r.Context(), tx, t)
	})
	return finishDelete(w, found, err)
}

// ---------------------------------------------------------------------------------------------------------------
// Specialties

func (c *clinic) listSpecialties(w http.ResponseWriter, r *http.Request) error {
	specialties, err := readOnly(r.Context(), c.db, func(q querier) ([]Specialty, error) { return findAllSpecialties(r.Context(), q) })
	if err != nil {
		return err
	}
	if len(specialties) == 0 {
		notFound(w)
		return nil
	}
	ok(w, specialties)
	return nil
}

func (c *clinic) getSpecialty(w http.ResponseWriter, r *http.Request) error {
	specialtyID, err := pathInt(r, "specialtyId")
	if err != nil {
		return err
	}
	if err := minZero(specialtyID); err != nil {
		return err
	}
	s, err := readOnly(r.Context(), c.db, func(q querier) (*Specialty, error) { return findSpecialty(r.Context(), q, specialtyID) })
	if err != nil || s == nil {
		return notFoundUnless(w, err)
	}
	ok(w, s)
	return nil
}

// addSpecialty saves the SpecialtyDto as given: with an id, the reference updates that specialty.
func (c *clinic) addSpecialty(w http.ResponseWriter, r *http.Request) error {
	var body *specialtyBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	s := &Specialty{ID: body.ID.value, Name: body.Name.value}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveSpecialty(r.Context(), tx, s) }); err != nil {
		return err
	}
	created(w, location("specialties", s.ID), s)
	return nil
}

func (c *clinic) updateSpecialty(w http.ResponseWriter, r *http.Request) error {
	specialtyID, err := pathInt(r, "specialtyId")
	if err != nil {
		return err
	}
	var body *specialtyBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(specialtyID); err != nil {
		return err
	}
	s, err := readOnly(r.Context(), c.db, func(q querier) (*Specialty, error) { return findSpecialty(r.Context(), q, specialtyID) })
	if err != nil || s == nil {
		return notFoundUnless(w, err)
	}
	s.Name = body.Name.value
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveSpecialty(r.Context(), tx, s) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deleteSpecialty(w http.ResponseWriter, r *http.Request) error {
	specialtyID, err := pathInt(r, "specialtyId")
	if err != nil {
		return err
	}
	if err := minZero(specialtyID); err != nil {
		return err
	}
	found := false
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error {
		s, err := findSpecialty(r.Context(), tx, specialtyID)
		if err != nil || s == nil {
			return err
		}
		found = true
		return deleteSpecialty(r.Context(), tx, s)
	})
	return finishDelete(w, found, err)
}

// ---------------------------------------------------------------------------------------------------------------
// Vets

func (c *clinic) listVets(w http.ResponseWriter, r *http.Request) error {
	vets, err := readOnly(r.Context(), c.db, func(q querier) ([]*Vet, error) { return findAllVets(r.Context(), q) })
	if err != nil {
		return err
	}
	if len(vets) == 0 {
		notFound(w)
		return nil
	}
	ok(w, vets)
	return nil
}

func (c *clinic) getVet(w http.ResponseWriter, r *http.Request) error {
	vetID, err := pathInt(r, "vetId")
	if err != nil {
		return err
	}
	if err := minZero(vetID); err != nil {
		return err
	}
	vet, err := readOnly(r.Context(), c.db, func(q querier) (*Vet, error) { return findVet(r.Context(), q, vetID) })
	if err != nil || vet == nil {
		return notFoundUnless(w, err)
	}
	ok(w, vet)
	return nil
}

// vetSpecialties resolves the body's specialties by name, as the vet controller does: a vet gets the stored
// specialties whose names the body lists, whatever ids it gives.
func (c *clinic) vetSpecialties(r *http.Request, body *vetBody) ([]Specialty, error) {
	listed := *body.Specialties
	if len(listed) == 0 {
		return []Specialty{}, nil
	}
	var names []string
	seen := map[string]bool{}
	for _, s := range listed {
		if s == nil {
			return nil, errNullPointer
		}
		if !seen[s.Name.value] {
			seen[s.Name.value] = true
			names = append(names, s.Name.value)
		}
	}
	specialties, err := readOnly(r.Context(), c.db, func(q querier) ([]Specialty, error) { return findSpecialtiesByNameIn(r.Context(), q, names) })
	if specialties == nil {
		specialties = []Specialty{}
	}
	return specialties, err
}

// addVet saves the VetDto as given: with an id, the reference updates that vet.
func (c *clinic) addVet(w http.ResponseWriter, r *http.Request) error {
	var body *vetBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	vet := &Vet{FirstName: body.FirstName.value, LastName: body.LastName.value, ID: body.ID.value}
	var err error
	if vet.Specialties, err = c.vetSpecialties(r, body); err != nil {
		return err
	}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveVet(r.Context(), tx, vet) }); err != nil {
		return err
	}
	sortSpecialties(vet.Specialties)
	created(w, location("vets", vet.ID), vet)
	return nil
}

func (c *clinic) updateVet(w http.ResponseWriter, r *http.Request) error {
	vetID, err := pathInt(r, "vetId")
	if err != nil {
		return err
	}
	var body *vetBody
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if err := minZero(vetID); err != nil {
		return err
	}
	vet, err := readOnly(r.Context(), c.db, func(q querier) (*Vet, error) { return findVet(r.Context(), q, vetID) })
	if err != nil || vet == nil {
		return notFoundUnless(w, err)
	}
	vet.FirstName, vet.LastName = body.FirstName.value, body.LastName.value
	if vet.Specialties, err = c.vetSpecialties(r, body); err != nil {
		return err
	}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveVet(r.Context(), tx, vet) }); err != nil {
		return err
	}
	noContent(w, true)
	return nil
}

func (c *clinic) deleteVet(w http.ResponseWriter, r *http.Request) error {
	vetID, err := pathInt(r, "vetId")
	if err != nil {
		return err
	}
	if err := minZero(vetID); err != nil {
		return err
	}
	found := false
	err = inTx(r.Context(), c.db, func(tx *sql.Tx) error {
		vet, err := findVet(r.Context(), tx, vetID)
		if err != nil || vet == nil {
			return err
		}
		found = true
		return deleteVet(r.Context(), tx, vet)
	})
	return finishDelete(w, found, err)
}

// ---------------------------------------------------------------------------------------------------------------
// Users

func (c *clinic) addUser(w http.ResponseWriter, r *http.Request) error {
	body := &userBody{Roles: &[]*roleBody{}} // the generated DTO starts with an empty role list
	if err := readBody(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	if body.Roles == nil || len(*body.Roles) == 0 {
		return errIllegalArgument // UserServiceImpl: "User must have at least a role set!"
	}
	user := &User{Username: body.Username.value, Enabled: body.Enabled.ptr(), Roles: []Role{}}
	if body.Password.set {
		user.Password = &body.Password.value
	}
	for _, role := range *body.Roles {
		if role == nil {
			return errNullPointer
		}
		name := role.Name.value
		if len(name) < 5 || name[:5] != "ROLE_" {
			name = "ROLE_" + name
		}
		user.Roles = append(user.Roles, Role{Name: name})
	}
	if err := inTx(r.Context(), c.db, func(tx *sql.Tx) error { return saveUser(r.Context(), tx, user) }); err != nil {
		return err
	}
	created(w, "", user)
	return nil
}

// ---------------------------------------------------------------------------------------------------------------
// Actuator (management.endpoints defaults: health only, details never shown)

const actuatorType = "application/vnd.spring-boot.actuator.v3+json"

type link struct {
	Href      string `json:"href"`
	Templated bool   `json:"templated"`
}

type actuatorIndex struct {
	Links struct {
		Self       link `json:"self"`
		Health     link `json:"health"`
		HealthPath link `json:"health-path"`
	} `json:"_links"`
}

type healthStatus struct {
	Groups []string `json:"groups,omitempty"`
	Status string   `json:"status"`
}

// actuatorMediaType negotiates the actuator's v3 media type against plain JSON: v3 unless the client asks for
// application/json and not for v3.
func actuatorMediaType(r *http.Request) string {
	wantsJSON := false
	for _, item := range splitAccept(r.Header.Get("Accept")) {
		switch item {
		case actuatorType:
			return actuatorType
		case "application/json":
			wantsJSON = true
		}
	}
	if wantsJSON {
		return "application/json"
	}
	return actuatorType
}

func (c *clinic) actuatorLinks(w http.ResponseWriter, r *http.Request) error {
	base := "http://" + r.Host + contextPath + "/actuator"
	var index actuatorIndex
	index.Links.Self = link{Href: base}
	index.Links.Health = link{Href: base + "/health"}
	index.Links.HealthPath = link{Href: base + "/health/{*path}", Templated: true}
	writeJSON(w, http.StatusOK, actuatorMediaType(r), index)
	return nil
}

// health aggregates the database check (DataSourceHealthIndicator validates a connection) with the probes.
func (c *clinic) health(w http.ResponseWriter, r *http.Request) error {
	status, code := "UP", http.StatusOK
	// DataSourceHealthIndicator without a validation query: Connection.isValid, which pgjdbc sends as an empty
	// query (ADR-032). Borrowing the connection may send Hikari's validation first (openDatabase).
	if _, err := c.db.ExecContext(r.Context(), ""); err != nil {
		status, code = "DOWN", http.StatusServiceUnavailable
	}
	writeJSON(w, code, actuatorMediaType(r), healthStatus{Groups: []string{"liveness", "readiness"}, Status: status})
	return nil
}

// healthGroup answers the liveness and readiness groups, which hold only the application's availability state.
func (c *clinic) healthGroup(w http.ResponseWriter, r *http.Request) error {
	switch r.PathValue("path") {
	case "liveness", "readiness":
		writeJSON(w, http.StatusOK, actuatorMediaType(r), healthStatus{Status: "UP"})
	default:
		notFound(w)
	}
	return nil
}
