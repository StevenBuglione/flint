/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.repository.jdbc`, the
JDBC repositories, ported to Flint. Copyright 2002-2013 the original author or authors. Licensed under the Apache
License, Version 2.0.
Modified by the Flint authors:
- Java → D syntax (R1).
- `Map<String, Object>` parameters are `HashMap!(string, Any)` (R10).
- `Class<T>` arguments are template parameters (R4): `BeanPropertyRowMapper!Owner.newInstance()`.
- `rs.getObject(i, LocalDate.class)` is `getObject!LocalDate(i)`, and `rs.getDate(...)` with `java.sql.Date` is the
  same `getObject!LocalDate`.
+/
module org.springframework.samples.petclinic.repository.jdbc;

import flint.boot.sql.init.dependency : DependsOnDatabaseInitialization;
import flint.context.annotation : Profile;
import flint.dao : EmptyResultDataAccessException;
import flint.data.domain : Page, PageImpl, Pageable;
import flint.engine.aot.any : Any;
import flint.java.sql : ResultSet;
import flint.java.time : LocalDate;
import flint.java.util : ArrayList, Collection, HashMap, List, Set;
import flint.javax.sql : DataSource;
import flint.jdbc.core : BeanPropertyRowMapper, JdbcTemplate, RowMapper;
import flint.jdbc.core.namedparam : BeanPropertySqlParameterSource, MapSqlParameterSource, NamedParameterJdbcTemplate;
import flint.jdbc.core.simple : SimpleJdbcInsert;
import flint.orm : ObjectRetrievalFailureException;
import flint.stereotype : Repository;
import flint.transaction.annotation : Transactional;
import org.springframework.data.jdbc.core : OneToManyResultSetExtractor;
import org.springframework.samples.petclinic.model;
import org.springframework.samples.petclinic.repository;
import org.springframework.samples.petclinic.util : EntityUtils;
import std.typecons : Nullable;

@safe:

/// A `HashMap<String, Object>` of named parameters.
private HashMap!(string, Any) params()
{
    return new HashMap!(string, Any);
}

private enum ownerColumns = "SELECT id, first_name, last_name, address, city, telephone FROM owners";

// ---------------------------------------------------------------------------------------------------------------
// Owners

/// A simple JDBC-based implementation of the `OwnerRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcOwnerRepositoryImpl : OwnerRepository
{
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertOwner;

    ///
    this(DataSource dataSource)
    {
        insertOwner = new SimpleJdbcInsert(dataSource).withTableName("owners").usingGeneratedKeyColumns("id");
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
    }

    /// Loads `Owner`s from the data store by last name, returning all owners whose last name starts with the given
    /// name; also loads the `Pet`s and `Visit`s for the corresponding owners, if not already loaded.
    override Collection!Owner findByLastName(string lastName)
    {
        auto query = params();
        query.put("lastName", Any.of(lastName ~ "%"));
        auto owners = namedParameterJdbcTemplate.query(ownerColumns ~ " WHERE last_name like :lastName",
                query, BeanPropertyRowMapper!Owner.newInstance());
        loadOwnersPetsAndVisits(owners);
        return owners;
    }

    override Page!Owner findByLastName(string lastName, Pageable pageable)
    {
        auto query = params();
        query.put("lastName", Any.of(lastName ~ "%"));
        query.put("size", Any.of(pageable.getPageSize()));
        query.put("offset", Any.of(pageable.getOffset()));
        auto owners = namedParameterJdbcTemplate.query(
                ownerColumns ~ " WHERE last_name like :lastName ORDER BY id LIMIT :size OFFSET :offset",
                query, BeanPropertyRowMapper!Owner.newInstance());
        loadOwnersPetsAndVisits(owners);
        const total = namedParameterJdbcTemplate.queryForObject!long(
                "SELECT COUNT(*) FROM owners WHERE last_name like :lastName", query);
        return new PageImpl!Owner(owners, pageable, total);
    }

    /// Loads the `Owner` with the supplied `id`; also loads the `Pet`s and `Visit`s for the corresponding owner,
    /// if not already loaded.
    override Owner findById(int id)
    {
        Owner owner;
        try
        {
            auto query = params();
            query.put("id", Any.of(id));
            owner = namedParameterJdbcTemplate.queryForObject(ownerColumns ~ " WHERE id= :id",
                    query, BeanPropertyRowMapper!Owner.newInstance());
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(Owner), Any.of(id));
        loadPetsAndVisits(owner);
        return owner;
    }

    /// Loads the `Pet`s and their `Visit`s of `owner`.
    void loadPetsAndVisits(Owner owner)
    {
        auto query = params();
        query.put("id", Any.of(owner.getId()));
        auto pets = namedParameterJdbcTemplate.query("SELECT pets.id as pets_id, name, birth_date, type_id, "
                ~ "owner_id, visits.id as visit_id, visit_date, description, visits.pet_id as visits_pet_id FROM pets "
                ~ "LEFT OUTER JOIN visits ON pets.id = visits.pet_id WHERE owner_id=:id ORDER BY pets.id",
                query, new JdbcPetVisitExtractor);
        auto petTypes = getPetTypes();
        foreach (pet; pets.toArray())
        {
            pet.setType(EntityUtils.getById!PetType(petTypes, pet.getTypeId()));
            owner.addPet(pet);
        }
    }

    override void save(Owner owner)
    {
        auto parameterSource = new BeanPropertySqlParameterSource(owner);
        if (owner.isNew())
        {
            const newKey = insertOwner.executeAndReturnKey(parameterSource);
            owner.setId(cast(int) newKey.get!long);
        }
        else
            namedParameterJdbcTemplate.update("UPDATE owners SET first_name=:firstName, last_name=:lastName, "
                    ~ "address=:address, city=:city, telephone=:telephone WHERE id=:id", parameterSource);
    }

    /// All pet types, by name.
    Collection!PetType getPetTypes()
    {
        return namedParameterJdbcTemplate.query("SELECT id, name FROM types ORDER BY name",
                params(), BeanPropertyRowMapper!PetType.newInstance());
    }

    /// Loads the `Pet` and `Visit` data for the supplied `List` of `Owner`s.
    private void loadOwnersPetsAndVisits(List!Owner owners)
    {
        foreach (owner; owners.toArray())
            loadPetsAndVisits(owner);
    }

    override Collection!Owner findAll()
    {
        auto owners = namedParameterJdbcTemplate.query(ownerColumns, params(),
                BeanPropertyRowMapper!Owner.newInstance());
        foreach (owner; owners.toArray())
            loadPetsAndVisits(owner);
        return owners;
    }

    override Page!Owner findAll(Pageable pageable)
    {
        auto query = params();
        query.put("size", Any.of(pageable.getPageSize()));
        query.put("offset", Any.of(pageable.getOffset()));
        auto owners = namedParameterJdbcTemplate.query(ownerColumns ~ " ORDER BY id LIMIT :size OFFSET :offset",
                query, BeanPropertyRowMapper!Owner.newInstance());
        loadOwnersPetsAndVisits(owners);
        const total = namedParameterJdbcTemplate.queryForObject!long("SELECT COUNT(*) FROM owners", query);
        return new PageImpl!Owner(owners, pageable, total);
    }

    @Transactional override void delete_(Owner owner)
    {
        auto ownerParams = params();
        ownerParams.put("id", Any.of(owner.getId()));
        foreach (pet; owner.getPets().toArray())
        {
            auto petParams = params();
            petParams.put("id", Any.of(pet.getId()));
            foreach (visit; pet.getVisits().toArray())
            {
                auto visitParams = params();
                visitParams.put("id", Any.of(visit.getId()));
                namedParameterJdbcTemplate.update("DELETE FROM visits WHERE id=:id", visitParams);
            }

            namedParameterJdbcTemplate.update("DELETE FROM pets WHERE id=:id", petParams);
        }
        namedParameterJdbcTemplate.update("DELETE FROM owners WHERE id=:id", ownerParams);
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Pets

/// Subclass of `Pet` that carries temporary id properties which are only relevant for a JDBC implementation of the
/// `PetRepository`.
class JdbcPet : Pet
{
    private int typeId;
    private int ownerId;

    ///
    int getTypeId()
    {
        return typeId;
    }

    ///
    void setTypeId(int typeId)
    {
        this.typeId = typeId;
    }

    ///
    int getOwnerId()
    {
        return ownerId;
    }

    ///
    void setOwnerId(int ownerId)
    {
        this.ownerId = ownerId;
    }
}

/// `RowMapper` implementation mapping data from a `ResultSet` to the corresponding properties of the `JdbcPet`
/// class.
class JdbcPetRowMapper : RowMapper!JdbcPet
{
    override JdbcPet mapRow(ResultSet rs, int)
    {
        auto pet = new JdbcPet;
        pet.setId(rs.getInt("pets_id"));
        pet.setName(rs.getString("name"));
        pet.setBirthDate(rs.getObject!LocalDate("birth_date"));
        pet.setTypeId(rs.getInt("type_id"));
        pet.setOwnerId(rs.getInt("owner_id"));
        return pet;
    }
}

/// `RowMapper` implementation mapping data from a `ResultSet` to the corresponding properties of the `Visit`
/// class.
class JdbcVisitRowMapper : RowMapper!Visit
{
    override Visit mapRow(ResultSet rs, int)
    {
        auto visit = new Visit;
        visit.setId(rs.getInt("visit_id"));
        visit.setDate(rs.getObject!LocalDate("visit_date"));
        visit.setDescription(rs.getString("description"));
        return visit;
    }
}

/// `OneToManyResultSetExtractor` of the pets of an owner with their visits.
class JdbcPetVisitExtractor : OneToManyResultSetExtractor!(JdbcPet, Visit, int)
{
    ///
    this()
    {
        super(new JdbcPetRowMapper, new JdbcVisitRowMapper);
    }

    protected override int mapPrimaryKey(ResultSet rs)
    {
        return rs.getInt("pets_id");
    }

    protected override Nullable!int mapForeignKey(ResultSet rs)
    {
        if (rs.getObject("visits_pet_id").isNull)
            return Nullable!int.init;
        return Nullable!int(rs.getInt("visits_pet_id"));
    }

    protected override void addChild(JdbcPet root, Visit child)
    {
        root.addVisit(child);
    }
}

private enum petColumns = "SELECT pets.id as pets_id, name, birth_date, type_id, owner_id FROM pets";

/// A simple JDBC-based implementation of the `PetRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcPetRepositoryImpl : PetRepository
{
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertPet;
    private OwnerRepository ownerRepository;

    ///
    this(DataSource dataSource, OwnerRepository ownerRepository)
    {
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        insertPet = new SimpleJdbcInsert(dataSource).withTableName("pets").usingGeneratedKeyColumns("id");
        this.ownerRepository = ownerRepository;
    }

    override List!PetType findPetTypes()
    {
        return namedParameterJdbcTemplate.query("SELECT id, name FROM types ORDER BY name",
                params(), BeanPropertyRowMapper!PetType.newInstance());
    }

    override Pet findById(int id)
    {
        int ownerId;
        try
        {
            auto query = params();
            query.put("id", Any.of(id));
            ownerId = namedParameterJdbcTemplate.queryForObject!int("SELECT owner_id FROM pets WHERE id=:id", query);
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(Pet), Any.of(id));
        auto owner = ownerRepository.findById(ownerId);
        return EntityUtils.getById!Pet(owner.getPets(), id);
    }

    override void save(Pet pet)
    {
        if (pet.isNew())
        {
            const newKey = insertPet.executeAndReturnKey(createPetParameterSource(pet));
            pet.setId(cast(int) newKey.get!long);
        }
        else
            namedParameterJdbcTemplate.update("UPDATE pets SET name=:name, birth_date=:birth_date, "
                    ~ "type_id=:type_id, owner_id=:owner_id WHERE id=:id", createPetParameterSource(pet));
    }

    /// Creates a `MapSqlParameterSource` based on data values from the supplied `Pet` instance. Java's
    /// `pet.getType().getId()` throws `NullPointerException` for an unknown pet type (the API answers 500); a D null
    /// dereference does not throw, so the dereferences say so with `Objects.requireNonNull`.
    private MapSqlParameterSource createPetParameterSource(Pet pet)
    {
        import flint.java.util : Objects;

        return new MapSqlParameterSource().addValue("id", pet.getId()).addValue("name",
                pet.getName()).addValue("birth_date", pet.getBirthDate()).addValue("type_id",
                Objects.requireNonNull(pet.getType()).getId()).addValue("owner_id",
                Objects.requireNonNull(pet.getOwner()).getId());
    }

    override Collection!Pet findAll()
    {
        auto pets = new ArrayList!Pet;
        foreach (jdbcPet; loadPets(namedParameterJdbcTemplate.query(petColumns, params(), new JdbcPetRowMapper))
                .toArray())
            pets.add(jdbcPet);
        return pets;
    }

    override Page!Pet findAll(Pageable pageable)
    {
        auto query = params();
        query.put("size", Any.of(pageable.getPageSize()));
        query.put("offset", Any.of(pageable.getOffset()));
        auto jdbcPets = loadPets(namedParameterJdbcTemplate.query(
                petColumns ~ " ORDER BY id LIMIT :size OFFSET :offset", query, new JdbcPetRowMapper));
        const total = namedParameterJdbcTemplate.queryForObject!long("SELECT count(*) FROM pets", query);
        auto pets = new ArrayList!Pet;
        foreach (jdbcPet; jdbcPets.toArray())
            pets.add(jdbcPet);
        return new PageImpl!Pet(pets, pageable, total);
    }

    /// Sets each pet's type and owner from the pet types and the owners.
    private List!JdbcPet loadPets(List!JdbcPet jdbcPets)
    {
        auto petTypes = namedParameterJdbcTemplate.query("SELECT id, name FROM types ORDER BY name",
                params(), BeanPropertyRowMapper!PetType.newInstance());
        auto owners = namedParameterJdbcTemplate.query(ownerColumns ~ " ORDER BY last_name",
                params(), BeanPropertyRowMapper!Owner.newInstance());
        foreach (jdbcPet; jdbcPets.toArray())
        {
            jdbcPet.setType(EntityUtils.getById!PetType(petTypes, jdbcPet.getTypeId()));
            jdbcPet.setOwner(EntityUtils.getById!Owner(owners, jdbcPet.getOwnerId()));
        }
        return jdbcPets;
    }

    override void delete_(Pet pet)
    {
        auto petParams = params();
        petParams.put("id", Any.of(pet.getId()));
        foreach (visit; pet.getVisits().toArray())
        {
            auto visitParams = params();
            visitParams.put("id", Any.of(visit.getId()));
            namedParameterJdbcTemplate.update("DELETE FROM visits WHERE id=:id", visitParams);
        }

        namedParameterJdbcTemplate.update("DELETE FROM pets WHERE id=:id", petParams);
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Pet types and specialties

/// A simple JDBC-based implementation of the `PetTypeRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcPetTypeRepositoryImpl : PetTypeRepository
{
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertPetType;

    ///
    this(DataSource dataSource)
    {
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        insertPetType = new SimpleJdbcInsert(dataSource).withTableName("types").usingGeneratedKeyColumns("id");
    }

    override PetType findById(int id)
    {
        try
        {
            auto query = params();
            query.put("id", Any.of(id));
            return namedParameterJdbcTemplate.queryForObject("SELECT id, name FROM types WHERE id= :id",
                    query, BeanPropertyRowMapper!PetType.newInstance());
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(PetType), Any.of(id));
    }

    override PetType findByName(string name)
    {
        try
        {
            auto query = params();
            query.put("name", Any.of(name));
            return namedParameterJdbcTemplate.queryForObject("SELECT id, name FROM types WHERE name= :name",
                    query, BeanPropertyRowMapper!PetType.newInstance());
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(PetType), Any.of(name));
    }

    override Collection!PetType findAll()
    {
        return namedParameterJdbcTemplate.query("SELECT id, name FROM types", params(),
                BeanPropertyRowMapper!PetType.newInstance());
    }

    override void save(PetType petType)
    {
        auto parameterSource = new BeanPropertySqlParameterSource(petType);
        if (petType.isNew())
            petType.setId(cast(int) insertPetType.executeAndReturnKey(parameterSource).get!long);
        else
            namedParameterJdbcTemplate.update("UPDATE types SET name=:name WHERE id=:id", parameterSource);
    }

    override void delete_(PetType petType)
    {
        auto petTypeParams = params();
        petTypeParams.put("id", Any.of(petType.getId()));
        auto pets = namedParameterJdbcTemplate.query(
                "SELECT pets.id, name, birth_date, type_id, owner_id FROM pets " ~ "WHERE type_id=:id",
                petTypeParams, BeanPropertyRowMapper!Pet.newInstance());
        foreach (pet; pets.toArray())
        {
            auto petParams = params();
            petParams.put("id", Any.of(pet.getId()));
            auto visits = namedParameterJdbcTemplate.query(
                    "SELECT id, pet_id, visit_date, description FROM visits " ~ "WHERE pet_id = :id",
                    petParams, BeanPropertyRowMapper!Visit.newInstance());
            foreach (visit; visits.toArray())
            {
                auto visitParams = params();
                visitParams.put("id", Any.of(visit.getId()));
                namedParameterJdbcTemplate.update("DELETE FROM visits WHERE id=:id", visitParams);
            }

            namedParameterJdbcTemplate.update("DELETE FROM pets WHERE id=:id", petParams);
        }
        namedParameterJdbcTemplate.update("DELETE FROM types WHERE id=:id", petTypeParams);
    }
}

/// A simple JDBC-based implementation of the `SpecialtyRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcSpecialtyRepositoryImpl : SpecialtyRepository
{
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertSpecialty;

    ///
    this(DataSource dataSource)
    {
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        insertSpecialty = new SimpleJdbcInsert(dataSource).withTableName("specialties").usingGeneratedKeyColumns("id");
    }

    override Specialty findById(int id)
    {
        try
        {
            auto query = params();
            query.put("id", Any.of(id));
            return namedParameterJdbcTemplate.queryForObject("SELECT id, name FROM specialties WHERE id= :id",
                    query, BeanPropertyRowMapper!Specialty.newInstance());
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(Specialty), Any.of(id));
    }

    override List!Specialty findSpecialtiesByNameIn(Set!string names)
    {
        Any[] values;
        foreach (name; names.toArray())
            values ~= Any.of(name);
        auto query = params();
        query.put("names", Any.of(values));
        return namedParameterJdbcTemplate.query("SELECT id, name FROM specialties WHERE specialties.name IN (:names)",
                query, new BeanPropertyRowMapper!Specialty);
    }

    override Collection!Specialty findAll()
    {
        return namedParameterJdbcTemplate.query("SELECT id, name FROM specialties", params(),
                BeanPropertyRowMapper!Specialty.newInstance());
    }

    override void save(Specialty specialty)
    {
        auto parameterSource = new BeanPropertySqlParameterSource(specialty);
        if (specialty.isNew())
            specialty.setId(cast(int) insertSpecialty.executeAndReturnKey(parameterSource).get!long);
        else
            namedParameterJdbcTemplate.update("UPDATE specialties SET name=:name WHERE id=:id", parameterSource);
    }

    override void delete_(Specialty specialty)
    {
        auto query = params();
        query.put("id", Any.of(specialty.getId()));
        namedParameterJdbcTemplate.update("DELETE FROM vet_specialties WHERE specialty_id=:id", query);
        namedParameterJdbcTemplate.update("DELETE FROM specialties WHERE id=:id", query);
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Users, vets and visits

/// A simple JDBC-based implementation of the `UserRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcUserRepositoryImpl : UserRepository
{
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertUser;

    ///
    this(DataSource dataSource)
    {
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        insertUser = new SimpleJdbcInsert(dataSource).withTableName("users");
    }

    override void save(User user)
    {
        auto parameterSource = new BeanPropertySqlParameterSource(user);
        scope (exit)
            updateUserRoles(user);
        try
        {
            getByUsername(user.getUsername());
            namedParameterJdbcTemplate.update(
                    "UPDATE users SET password=:password, enabled=:enabled " ~ "WHERE username=:username",
                    parameterSource);
        }
        catch (EmptyResultDataAccessException e)
            insertUser.execute(parameterSource);
    }

    private User getByUsername(string username)
    {
        auto query = params();
        query.put("username", Any.of(username));
        return namedParameterJdbcTemplate.queryForObject("SELECT * FROM users WHERE username=:username",
                query, BeanPropertyRowMapper!User.newInstance());
    }

    private void updateUserRoles(User user)
    {
        auto query = params();
        query.put("username", Any.of(user.getUsername()));
        namedParameterJdbcTemplate.update("DELETE FROM roles WHERE username=:username", query);
        foreach (role; user.getRoles().toArray())
        {
            query.put("role", Any.of(role.getName()));
            if (role.getName() !is null)
                namedParameterJdbcTemplate.update("INSERT INTO roles(username, role) VALUES (:username, :role)", query);
        }
    }
}

/// A simple JDBC-based implementation of the `VetRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcVetRepositoryImpl : VetRepository
{
    private JdbcTemplate jdbcTemplate;
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private SimpleJdbcInsert insertVet;

    ///
    this(DataSource dataSource, JdbcTemplate jdbcTemplate)
    {
        this.jdbcTemplate = jdbcTemplate;
        insertVet = new SimpleJdbcInsert(dataSource).withTableName("vets").usingGeneratedKeyColumns("id");
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
    }

    /// Refresh the cache of Vets that the ClinicService is holding.
    override Collection!Vet findAll()
    {
        auto vets = jdbcTemplate.query("SELECT id, first_name, last_name FROM vets ORDER BY last_name,first_name",
                BeanPropertyRowMapper!Vet.newInstance());
        auto specialties = jdbcTemplate.query("SELECT id, name FROM specialties",
                BeanPropertyRowMapper!Specialty.newInstance());
        foreach (vet; vets.toArray())
        {
            auto vetSpecialtiesIds = jdbcTemplate.query("SELECT specialty_id FROM vet_specialties WHERE vet_id=?",
                    (ResultSet rs, int) => rs.getInt(1), vet.getId());
            foreach (specialtyId; vetSpecialtiesIds.toArray())
                vet.addSpecialty(EntityUtils.getById!Specialty(specialties, specialtyId));
        }
        return vets;
    }

    override Vet findById(int id)
    {
        Vet vet;
        try
        {
            auto vetParams = params();
            vetParams.put("id", Any.of(id));
            vet = namedParameterJdbcTemplate.queryForObject("SELECT id, first_name, last_name FROM vets WHERE id= :id",
                    vetParams, BeanPropertyRowMapper!Vet.newInstance());
            auto specialties = namedParameterJdbcTemplate.query("SELECT id, name FROM specialties",
                    vetParams, BeanPropertyRowMapper!Specialty.newInstance());
            auto vetSpecialtiesIds = namedParameterJdbcTemplate.query(
                    "SELECT specialty_id FROM vet_specialties WHERE vet_id=:id",
                    vetParams, (ResultSet rs, int) => rs.getInt(1));
            foreach (specialtyId; vetSpecialtiesIds.toArray())
                vet.addSpecialty(EntityUtils.getById!Specialty(specialties, specialtyId));
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(Vet), Any.of(id));
        return vet;
    }

    override void save(Vet vet)
    {
        auto parameterSource = new BeanPropertySqlParameterSource(vet);
        if (vet.isNew())
            vet.setId(cast(int) insertVet.executeAndReturnKey(parameterSource).get!long);
        else
            namedParameterJdbcTemplate.update(
                    "UPDATE vets SET first_name=:firstName, last_name=:lastName " ~ "WHERE id=:id", parameterSource);
        updateVetSpecialties(vet);
    }

    override void delete_(Vet vet)
    {
        auto query = params();
        query.put("id", Any.of(vet.getId()));
        namedParameterJdbcTemplate.update("DELETE FROM vet_specialties WHERE vet_id=:id", query);
        namedParameterJdbcTemplate.update("DELETE FROM vets WHERE id=:id", query);
    }

    private void updateVetSpecialties(Vet vet)
    {
        auto query = params();
        query.put("id", Any.of(vet.getId()));
        namedParameterJdbcTemplate.update("DELETE FROM vet_specialties WHERE vet_id=:id", query);
        foreach (spec; vet.getSpecialties().toArray())
        {
            query.put("spec_id", Any.of(spec.getId()));
            if (spec.getId() != 0)
                namedParameterJdbcTemplate.update("INSERT INTO vet_specialties VALUES (:id, :spec_id)", query);
        }
    }
}

/// A simple JDBC-based implementation of the `VisitRepository` interface.
@DependsOnDatabaseInitialization @Repository @Profile(["jdbc"])
class JdbcVisitRepositoryImpl : VisitRepository
{
    protected SimpleJdbcInsert insertVisit;
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    ///
    this(DataSource dataSource)
    {
        namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        insertVisit = new SimpleJdbcInsert(dataSource).withTableName("visits").usingGeneratedKeyColumns("id");
    }

    /// Creates a `MapSqlParameterSource` based on data values from the supplied `Visit` instance.
    protected MapSqlParameterSource createVisitParameterSource(Visit visit)
    {
        return new MapSqlParameterSource().addValue("id", visit.getId()).addValue("visit_date",
                visit.getDate()).addValue("description", visit.getDescription()).addValue("pet_id",
                visit.getPet().getId());
    }

    override List!Visit findByPetId(int petId)
    {
        auto query = params();
        query.put("id", Any.of(petId));
        auto pet = namedParameterJdbcTemplate.queryForObject(
                "SELECT id as pets_id, name, birth_date, type_id, " ~ "owner_id FROM pets WHERE id=:id",
                query, new JdbcPetRowMapper);
        auto visits = namedParameterJdbcTemplate.query(
                "SELECT id as visit_id, visit_date, description FROM visits " ~ "WHERE pet_id=:id",
                query, new JdbcVisitRowMapper);
        foreach (visit; visits.toArray())
            visit.setPet(pet);
        return visits;
    }

    override Visit findById(int id)
    {
        try
        {
            auto query = params();
            query.put("id", Any.of(id));
            return namedParameterJdbcTemplate.queryForObject("SELECT id as visit_id, visits.pet_id as pets_id, "
                    ~ "visit_date, description FROM visits WHERE id= :id", query, new JdbcVisitRowMapperExt);
        }
        catch (EmptyResultDataAccessException ex)
            throw new ObjectRetrievalFailureException(typeid(Visit), Any.of(id));
    }

    override Collection!Visit findAll()
    {
        return namedParameterJdbcTemplate.query("SELECT visits.id as visit_id, pets.id as pets_id, visit_date, "
                ~ "description FROM visits LEFT JOIN pets ON visits.pet_id = pets.id", params(),
                new JdbcVisitRowMapperExt);
    }

    override void save(Visit visit)
    {
        if (visit.isNew())
            visit.setId(cast(int) insertVisit.executeAndReturnKey(createVisitParameterSource(visit)).get!long);
        else
        {
            enum sql = "UPDATE visits SET visit_date=:visit_date, description=:description, "
                ~ "pet_id=:pet_id WHERE id=:id ";
            namedParameterJdbcTemplate.update(sql, createVisitParameterSource(visit));
        }
    }

    override void delete_(Visit visit)
    {
        auto query = params();
        query.put("id", Any.of(visit.getId()));
        namedParameterJdbcTemplate.update("DELETE FROM visits WHERE id=:id", query);
    }

    /// Maps a visit with its pet, the pet's type and its owner.
    protected class JdbcVisitRowMapperExt : RowMapper!Visit
    {
        override Visit mapRow(ResultSet rs, int)
        {
            auto visit = new Visit;
            visit.setId(rs.getInt("visit_id"));
            visit.setDate(rs.getObject!LocalDate("visit_date"));
            visit.setDescription(rs.getString("description"));
            auto query = params();
            query.put("id", Any.of(rs.getInt("pets_id")));
            auto pet = this.outer.namedParameterJdbcTemplate.queryForObject(petColumns ~ " WHERE pets.id=:id",
                    query, new JdbcPetRowMapper);
            query.put("type_id", Any.of(pet.getTypeId()));
            pet.setType(this.outer.namedParameterJdbcTemplate.queryForObject(
                    "SELECT id, name FROM types WHERE id= :type_id", query,
                    BeanPropertyRowMapper!PetType.newInstance()));
            query.put("owner_id", Any.of(pet.getOwnerId()));
            pet.setOwner(this.outer.namedParameterJdbcTemplate.queryForObject(ownerColumns ~ " WHERE id= :owner_id",
                    query, BeanPropertyRowMapper!Owner.newInstance()));
            visit.setPet(pet);
            return visit;
        }
    }
}
