/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.dto`, the models
openapi-generator 7.26.0 (SpringCodegen) writes from src/main/resources/openapi.yml at build time, translated to D.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- One module for the generated package (R1). Fields carry a trailing underscore, since D cannot name a field and
  the generator's fluent setter alike.
- Types: `Integer` is `int` (an absent id reads as 0, as BaseEntity's "new"), `Boolean` `bool`, `Long` `long`;
  `URI` and `OffsetDateTime` are their ISO text.
- `@Schema` (springdoc) is dropped; the generated `equals`, `hashCode` and `toString` are omitted, since nothing in
  the application calls them.
- `@PetAgeValidation`, which openapi.yml puts on the `birthDate` field, is on its getter, so the property path
  stays `birthDate` with the field's trailing underscore.
- `ValidationMessageDto`'s additional properties are strings, the only values the application puts there.
+/
module org.springframework.samples.petclinic.rest.dto;

import flint.jackson.annotation : JsonAnyGetter, JsonAnySetter, JsonProperty;
import flint.jakarta.validation : Valid;
import flint.jakarta.validation.constraints : Max, Min, NotNull, Pattern, Size;
import flint.java.time : LocalDate;
import flint.java.util : ArrayList, LinkedHashMap, List, Map;
import org.springframework.samples.petclinic.rest.validation : PetAgeValidation;

@safe:

/// `PetTypeFieldsDto`: Editable fields of a pet type.
class PetTypeFieldsDto
{
    private string name_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(string name)
    {
        this.name_ = name;
    }

    ///
    PetTypeFieldsDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}][\\p{L}\\s\\-']{0,79}$") @Size(min : 1, max:
            80) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }
}

/// `PetTypeDto`: A pet type.
class PetTypeDto
{
    private string name_;
    private int id_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(string name, int id)
    {
        this.name_ = name;
        this.id_ = id;
    }

    ///
    PetTypeDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}][\\p{L}\\s\\-']{0,79}$") @Size(min : 1, max:
            80) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }

    ///
    PetTypeDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }
}

/// `VisitFieldsDto`: Editable fields of a vet visit.
class VisitFieldsDto
{
    private LocalDate date_;
    private string description_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(LocalDate date, string description)
    {
        this.date_ = date;
        this.description_ = description;
    }

    ///
    VisitFieldsDto date(LocalDate date)
    {
        this.date_ = date;
        return this;
    }

    ///
    @NotNull @JsonProperty("date") LocalDate getDate()
    {
        return date_;
    }

    ///
    @JsonProperty("date") void setDate(LocalDate date)
    {
        this.date_ = date;
    }

    ///
    VisitFieldsDto description(string description)
    {
        this.description_ = description;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            255) @JsonProperty("description") string getDescription()
    {
        return description_;
    }

    ///
    @JsonProperty("description") void setDescription(string description)
    {
        this.description_ = description;
    }
}

/// `VisitDto`: A booking for a vet visit.
class VisitDto
{
    private LocalDate date_;
    private string description_;
    private int id_;
    private int petId_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(LocalDate date, string description, int id, int petId)
    {
        this.date_ = date;
        this.description_ = description;
        this.id_ = id;
        this.petId_ = petId;
    }

    ///
    VisitDto date(LocalDate date)
    {
        this.date_ = date;
        return this;
    }

    ///
    @NotNull @JsonProperty("date") LocalDate getDate()
    {
        return date_;
    }

    ///
    @JsonProperty("date") void setDate(LocalDate date)
    {
        this.date_ = date;
    }

    ///
    VisitDto description(string description)
    {
        this.description_ = description;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            255) @JsonProperty("description") string getDescription()
    {
        return description_;
    }

    ///
    @JsonProperty("description") void setDescription(string description)
    {
        this.description_ = description;
    }

    ///
    VisitDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }

    ///
    VisitDto petId(int petId)
    {
        this.petId_ = petId;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("petId") int getPetId()
    {
        return petId_;
    }

    ///
    @JsonProperty("petId") void setPetId(int petId)
    {
        this.petId_ = petId;
    }
}

/// `PetFieldsDto`: Editable fields of a pet.
class PetFieldsDto
{
    private string name_;
    private LocalDate birthDate_;
    private PetTypeDto type_;

    ///
    this()
    {
        type_ = null;
    }

    /// Constructor with only required parameters.
    this(string name, LocalDate birthDate, PetTypeDto type)
    {
        this.name_ = name;
        this.birthDate_ = birthDate;
        this.type_ = type;
    }

    ///
    PetFieldsDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            30) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }

    ///
    PetFieldsDto birthDate(LocalDate birthDate)
    {
        this.birthDate_ = birthDate;
        return this;
    }

    ///
    @NotNull @PetAgeValidation @JsonProperty("birthDate") LocalDate getBirthDate()
    {
        return birthDate_;
    }

    ///
    @JsonProperty("birthDate") void setBirthDate(LocalDate birthDate)
    {
        this.birthDate_ = birthDate;
    }

    ///
    PetFieldsDto type(PetTypeDto type)
    {
        this.type_ = type;
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("type") PetTypeDto getType()
    {
        return type_;
    }

    ///
    @JsonProperty("type") void setType(PetTypeDto type)
    {
        this.type_ = type;
    }
}

/// `PetDto`: A pet.
class PetDto
{
    private string name_;
    private LocalDate birthDate_;
    private PetTypeDto type_;
    private int id_;
    private int ownerId_;
    private List!VisitDto visits_;

    ///
    this()
    {
        type_ = null;
        visits_ = new ArrayList!VisitDto();
    }

    /// Constructor with only required parameters.
    this(string name, LocalDate birthDate, PetTypeDto type, int id, List!VisitDto visits)
    {
        this.name_ = name;
        this.birthDate_ = birthDate;
        this.type_ = type;
        this.id_ = id;
        this.visits_ = visits;
    }

    ///
    PetDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            30) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }

    ///
    PetDto birthDate(LocalDate birthDate)
    {
        this.birthDate_ = birthDate;
        return this;
    }

    ///
    @NotNull @PetAgeValidation @JsonProperty("birthDate") LocalDate getBirthDate()
    {
        return birthDate_;
    }

    ///
    @JsonProperty("birthDate") void setBirthDate(LocalDate birthDate)
    {
        this.birthDate_ = birthDate;
    }

    ///
    PetDto type(PetTypeDto type)
    {
        this.type_ = type;
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("type") PetTypeDto getType()
    {
        return type_;
    }

    ///
    @JsonProperty("type") void setType(PetTypeDto type)
    {
        this.type_ = type;
    }

    ///
    PetDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }

    ///
    PetDto ownerId(int ownerId)
    {
        this.ownerId_ = ownerId;
        return this;
    }

    ///
    @Min(0) @JsonProperty("ownerId") int getOwnerId()
    {
        return ownerId_;
    }

    ///
    @JsonProperty("ownerId") void setOwnerId(int ownerId)
    {
        this.ownerId_ = ownerId;
    }

    ///
    PetDto visits(List!VisitDto visits)
    {
        this.visits_ = visits;
        return this;
    }

    ///
    PetDto addVisitsItem(VisitDto visitsItem)
    {
        if (this.visits_ is null)
            this.visits_ = new ArrayList!VisitDto();
        this.visits_.add(visitsItem);
        return this;
    }

    ///
    @Valid @JsonProperty("visits") List!VisitDto getVisits()
    {
        return visits_;
    }

    ///
    @JsonProperty("visits") void setVisits(List!VisitDto visits)
    {
        this.visits_ = visits;
    }
}

/// `OwnerFieldsDto`: Editable fields of a pet owner.
class OwnerFieldsDto
{
    private string firstName_;
    private string lastName_;
    private string address_;
    private string city_;
    private string telephone_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(string firstName, string lastName, string address, string city, string telephone)
    {
        this.firstName_ = firstName;
        this.lastName_ = lastName;
        this.address_ = address;
        this.city_ = city;
        this.telephone_ = telephone;
    }

    ///
    OwnerFieldsDto firstName(string firstName)
    {
        this.firstName_ = firstName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}$") @Size(min : 1, max:
            30) @JsonProperty("firstName") string getFirstName()
    {
        return firstName_;
    }

    ///
    @JsonProperty("firstName") void setFirstName(string firstName)
    {
        this.firstName_ = firstName;
    }

    ///
    OwnerFieldsDto lastName(string lastName)
    {
        this.lastName_ = lastName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}\\.?$") @Size(min : 1, max:
            30) @JsonProperty("lastName") string getLastName()
    {
        return lastName_;
    }

    ///
    @JsonProperty("lastName") void setLastName(string lastName)
    {
        this.lastName_ = lastName;
    }

    ///
    OwnerFieldsDto address(string address)
    {
        this.address_ = address;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            255) @JsonProperty("address") string getAddress()
    {
        return address_;
    }

    ///
    @JsonProperty("address") void setAddress(string address)
    {
        this.address_ = address;
    }

    ///
    OwnerFieldsDto city(string city)
    {
        this.city_ = city;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            80) @JsonProperty("city") string getCity()
    {
        return city_;
    }

    ///
    @JsonProperty("city") void setCity(string city)
    {
        this.city_ = city;
    }

    ///
    OwnerFieldsDto telephone(string telephone)
    {
        this.telephone_ = telephone;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[0-9]{10}$") @Size(min : 10, max:
            10) @JsonProperty("telephone") string getTelephone()
    {
        return telephone_;
    }

    ///
    @JsonProperty("telephone") void setTelephone(string telephone)
    {
        this.telephone_ = telephone;
    }
}

/// `OwnerDto`: A pet owner.
class OwnerDto
{
    private string firstName_;
    private string lastName_;
    private string address_;
    private string city_;
    private string telephone_;
    private int id_;
    private List!PetDto pets_;

    ///
    this()
    {
        pets_ = new ArrayList!PetDto();
    }

    /// Constructor with only required parameters.
    this(string firstName, string lastName, string address, string city, string telephone, List!PetDto pets)
    {
        this.firstName_ = firstName;
        this.lastName_ = lastName;
        this.address_ = address;
        this.city_ = city;
        this.telephone_ = telephone;
        this.pets_ = pets;
    }

    ///
    OwnerDto firstName(string firstName)
    {
        this.firstName_ = firstName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}$") @Size(min : 1, max:
            30) @JsonProperty("firstName") string getFirstName()
    {
        return firstName_;
    }

    ///
    @JsonProperty("firstName") void setFirstName(string firstName)
    {
        this.firstName_ = firstName;
    }

    ///
    OwnerDto lastName(string lastName)
    {
        this.lastName_ = lastName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}\\.?$") @Size(min : 1, max:
            30) @JsonProperty("lastName") string getLastName()
    {
        return lastName_;
    }

    ///
    @JsonProperty("lastName") void setLastName(string lastName)
    {
        this.lastName_ = lastName;
    }

    ///
    OwnerDto address(string address)
    {
        this.address_ = address;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            255) @JsonProperty("address") string getAddress()
    {
        return address_;
    }

    ///
    @JsonProperty("address") void setAddress(string address)
    {
        this.address_ = address;
    }

    ///
    OwnerDto city(string city)
    {
        this.city_ = city;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "[\\s\\S]*\\S[\\s\\S]*") @Size(min : 1, max:
            80) @JsonProperty("city") string getCity()
    {
        return city_;
    }

    ///
    @JsonProperty("city") void setCity(string city)
    {
        this.city_ = city;
    }

    ///
    OwnerDto telephone(string telephone)
    {
        this.telephone_ = telephone;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[0-9]{10}$") @Size(min : 10, max:
            10) @JsonProperty("telephone") string getTelephone()
    {
        return telephone_;
    }

    ///
    @JsonProperty("telephone") void setTelephone(string telephone)
    {
        this.telephone_ = telephone;
    }

    ///
    OwnerDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }

    ///
    OwnerDto pets(List!PetDto pets)
    {
        this.pets_ = pets;
        return this;
    }

    ///
    OwnerDto addPetsItem(PetDto petsItem)
    {
        if (this.pets_ is null)
            this.pets_ = new ArrayList!PetDto();
        this.pets_.add(petsItem);
        return this;
    }

    ///
    @Valid @JsonProperty("pets") List!PetDto getPets()
    {
        return pets_;
    }

    ///
    @JsonProperty("pets") void setPets(List!PetDto pets)
    {
        this.pets_ = pets;
    }
}

/// `OwnerPageDto`: A page of pet owners.
class OwnerPageDto
{
    private List!OwnerDto content_;
    private int page_;
    private int size_;
    private long totalElements_;
    private int totalPages_;

    ///
    this()
    {
        content_ = new ArrayList!OwnerDto();
    }

    /// Constructor with only required parameters.
    this(List!OwnerDto content, int page, int size, long totalElements, int totalPages)
    {
        this.content_ = content;
        this.page_ = page;
        this.size_ = size;
        this.totalElements_ = totalElements;
        this.totalPages_ = totalPages;
    }

    ///
    OwnerPageDto content(List!OwnerDto content)
    {
        this.content_ = content;
        return this;
    }

    ///
    OwnerPageDto addContentItem(OwnerDto contentItem)
    {
        if (this.content_ is null)
            this.content_ = new ArrayList!OwnerDto();
        this.content_.add(contentItem);
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("content") List!OwnerDto getContent()
    {
        return content_;
    }

    ///
    @JsonProperty("content") void setContent(List!OwnerDto content)
    {
        this.content_ = content;
    }

    ///
    OwnerPageDto page(int page)
    {
        this.page_ = page;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("page") int getPage()
    {
        return page_;
    }

    ///
    @JsonProperty("page") void setPage(int page)
    {
        this.page_ = page;
    }

    ///
    OwnerPageDto size(int size)
    {
        this.size_ = size;
        return this;
    }

    ///
    @NotNull @Min(1) @JsonProperty("size") int getSize()
    {
        return size_;
    }

    ///
    @JsonProperty("size") void setSize(int size)
    {
        this.size_ = size;
    }

    ///
    OwnerPageDto totalElements(long totalElements)
    {
        this.totalElements_ = totalElements;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("totalElements") long getTotalElements()
    {
        return totalElements_;
    }

    ///
    @JsonProperty("totalElements") void setTotalElements(long totalElements)
    {
        this.totalElements_ = totalElements;
    }

    ///
    OwnerPageDto totalPages(int totalPages)
    {
        this.totalPages_ = totalPages;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("totalPages") int getTotalPages()
    {
        return totalPages_;
    }

    ///
    @JsonProperty("totalPages") void setTotalPages(int totalPages)
    {
        this.totalPages_ = totalPages;
    }
}

/// `PetPageDto`: A page of pets.
class PetPageDto
{
    private List!PetDto content_;
    private int page_;
    private int size_;
    private long totalElements_;
    private int totalPages_;

    ///
    this()
    {
        content_ = new ArrayList!PetDto();
    }

    /// Constructor with only required parameters.
    this(List!PetDto content, int page, int size, long totalElements, int totalPages)
    {
        this.content_ = content;
        this.page_ = page;
        this.size_ = size;
        this.totalElements_ = totalElements;
        this.totalPages_ = totalPages;
    }

    ///
    PetPageDto content(List!PetDto content)
    {
        this.content_ = content;
        return this;
    }

    ///
    PetPageDto addContentItem(PetDto contentItem)
    {
        if (this.content_ is null)
            this.content_ = new ArrayList!PetDto();
        this.content_.add(contentItem);
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("content") List!PetDto getContent()
    {
        return content_;
    }

    ///
    @JsonProperty("content") void setContent(List!PetDto content)
    {
        this.content_ = content;
    }

    ///
    PetPageDto page(int page)
    {
        this.page_ = page;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("page") int getPage()
    {
        return page_;
    }

    ///
    @JsonProperty("page") void setPage(int page)
    {
        this.page_ = page;
    }

    ///
    PetPageDto size(int size)
    {
        this.size_ = size;
        return this;
    }

    ///
    @NotNull @Min(1) @JsonProperty("size") int getSize()
    {
        return size_;
    }

    ///
    @JsonProperty("size") void setSize(int size)
    {
        this.size_ = size;
    }

    ///
    PetPageDto totalElements(long totalElements)
    {
        this.totalElements_ = totalElements;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("totalElements") long getTotalElements()
    {
        return totalElements_;
    }

    ///
    @JsonProperty("totalElements") void setTotalElements(long totalElements)
    {
        this.totalElements_ = totalElements;
    }

    ///
    PetPageDto totalPages(int totalPages)
    {
        this.totalPages_ = totalPages;
        return this;
    }

    ///
    @NotNull @Min(0) @JsonProperty("totalPages") int getTotalPages()
    {
        return totalPages_;
    }

    ///
    @JsonProperty("totalPages") void setTotalPages(int totalPages)
    {
        this.totalPages_ = totalPages;
    }
}

/// `SpecialtyDto`: Fields of specialty of vets.
class SpecialtyDto
{
    private int id_;
    private string name_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(int id, string name)
    {
        this.id_ = id;
        this.name_ = name;
    }

    ///
    SpecialtyDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }

    ///
    SpecialtyDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}][\\p{L}\\s\\-&/]{0,79}$") @Size(min : 1, max:
            80) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }
}

/// `VetFieldsDto`: Editable fields of a veterinarian.
class VetFieldsDto
{
    private string firstName_;
    private string lastName_;
    private List!SpecialtyDto specialties_;

    ///
    this()
    {
        specialties_ = new ArrayList!SpecialtyDto();
    }

    /// Constructor with only required parameters.
    this(string firstName, string lastName, List!SpecialtyDto specialties)
    {
        this.firstName_ = firstName;
        this.lastName_ = lastName;
        this.specialties_ = specialties;
    }

    ///
    VetFieldsDto firstName(string firstName)
    {
        this.firstName_ = firstName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}$") @Size(min : 1, max:
            30) @JsonProperty("firstName") string getFirstName()
    {
        return firstName_;
    }

    ///
    @JsonProperty("firstName") void setFirstName(string firstName)
    {
        this.firstName_ = firstName;
    }

    ///
    VetFieldsDto lastName(string lastName)
    {
        this.lastName_ = lastName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}\\.?$") @Size(min : 1, max:
            30) @JsonProperty("lastName") string getLastName()
    {
        return lastName_;
    }

    ///
    @JsonProperty("lastName") void setLastName(string lastName)
    {
        this.lastName_ = lastName;
    }

    ///
    VetFieldsDto specialties(List!SpecialtyDto specialties)
    {
        this.specialties_ = specialties;
        return this;
    }

    ///
    VetFieldsDto addSpecialtiesItem(SpecialtyDto specialtiesItem)
    {
        if (this.specialties_ is null)
            this.specialties_ = new ArrayList!SpecialtyDto();
        this.specialties_.add(specialtiesItem);
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("specialties") List!SpecialtyDto getSpecialties()
    {
        return specialties_;
    }

    ///
    @JsonProperty("specialties") void setSpecialties(List!SpecialtyDto specialties)
    {
        this.specialties_ = specialties;
    }
}

/// `VetDto`: A veterinarian.
class VetDto
{
    private string firstName_;
    private string lastName_;
    private List!SpecialtyDto specialties_;
    private int id_;

    ///
    this()
    {
        specialties_ = new ArrayList!SpecialtyDto();
    }

    /// Constructor with only required parameters.
    this(string firstName, string lastName, List!SpecialtyDto specialties, int id)
    {
        this.firstName_ = firstName;
        this.lastName_ = lastName;
        this.specialties_ = specialties;
        this.id_ = id;
    }

    ///
    VetDto firstName(string firstName)
    {
        this.firstName_ = firstName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}$") @Size(min : 1, max:
            30) @JsonProperty("firstName") string getFirstName()
    {
        return firstName_;
    }

    ///
    @JsonProperty("firstName") void setFirstName(string firstName)
    {
        this.firstName_ = firstName;
    }

    ///
    VetDto lastName(string lastName)
    {
        this.lastName_ = lastName;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^[\\p{L}]+([ '-][\\p{L}]+){0,2}\\.?$") @Size(min : 1, max:
            30) @JsonProperty("lastName") string getLastName()
    {
        return lastName_;
    }

    ///
    @JsonProperty("lastName") void setLastName(string lastName)
    {
        this.lastName_ = lastName;
    }

    ///
    VetDto specialties(List!SpecialtyDto specialties)
    {
        this.specialties_ = specialties;
        return this;
    }

    ///
    VetDto addSpecialtiesItem(SpecialtyDto specialtiesItem)
    {
        if (this.specialties_ is null)
            this.specialties_ = new ArrayList!SpecialtyDto();
        this.specialties_.add(specialtiesItem);
        return this;
    }

    ///
    @NotNull @Valid @JsonProperty("specialties") List!SpecialtyDto getSpecialties()
    {
        return specialties_;
    }

    ///
    @JsonProperty("specialties") void setSpecialties(List!SpecialtyDto specialties)
    {
        this.specialties_ = specialties;
    }

    ///
    VetDto id(int id)
    {
        this.id_ = id;
        return this;
    }

    ///
    @Min(0) @JsonProperty("id") int getId()
    {
        return id_;
    }

    ///
    @JsonProperty("id") void setId(int id)
    {
        this.id_ = id;
    }
}

/// `RoleDto`: A role.
class RoleDto
{
    private string name_;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(string name)
    {
        this.name_ = name;
    }

    ///
    RoleDto name(string name)
    {
        this.name_ = name;
        return this;
    }

    ///
    @NotNull @Pattern(regexp : "^ROLE_[A-Z][A-Z0-9_]{1,74}$") @Size(min : 1, max:
            80) @JsonProperty("name") string getName()
    {
        return name_;
    }

    ///
    @JsonProperty("name") void setName(string name)
    {
        this.name_ = name;
    }
}

/// `UserDto`: An user.
class UserDto
{
    private string username_;
    private string password_;
    private bool enabled_;
    private List!RoleDto roles_;

    ///
    this()
    {
        roles_ = new ArrayList!RoleDto();
    }

    /// Constructor with only required parameters.
    this(string username)
    {
        this.username_ = username;
        roles_ = new ArrayList!RoleDto();
    }

    ///
    UserDto username(string username)
    {
        this.username_ = username;
        return this;
    }

    ///
    @NotNull @Size(min : 1, max:
            80) @JsonProperty("username") string getUsername()
    {
        return username_;
    }

    ///
    @JsonProperty("username") void setUsername(string username)
    {
        this.username_ = username;
    }

    ///
    UserDto password(string password)
    {
        this.password_ = password;
        return this;
    }

    ///
    @Size(min : 1, max:
            80) @JsonProperty("password") string getPassword()
    {
        return password_;
    }

    ///
    @JsonProperty("password") void setPassword(string password)
    {
        this.password_ = password;
    }

    ///
    UserDto enabled(bool enabled)
    {
        this.enabled_ = enabled;
        return this;
    }

    ///
    @JsonProperty("enabled") bool getEnabled()
    {
        return enabled_;
    }

    ///
    @JsonProperty("enabled") void setEnabled(bool enabled)
    {
        this.enabled_ = enabled;
    }

    ///
    UserDto roles(List!RoleDto roles)
    {
        this.roles_ = roles;
        return this;
    }

    ///
    UserDto addRolesItem(RoleDto rolesItem)
    {
        if (this.roles_ is null)
            this.roles_ = new ArrayList!RoleDto();
        this.roles_.add(rolesItem);
        return this;
    }

    ///
    @Valid @JsonProperty("roles") List!RoleDto getRoles()
    {
        return roles_;
    }

    ///
    @JsonProperty("roles") void setRoles(List!RoleDto roles)
    {
        this.roles_ = roles;
    }
}

/// `ProblemDetailDto`: The schema for all error responses.
class ProblemDetailDto
{
    private string type_;
    private string title_;
    private int status_;
    private string detail_;
    private string timestamp_;
    private List!ValidationMessageDto schemaValidationErrors_;

    ///
    this()
    {
        schemaValidationErrors_ = new ArrayList!ValidationMessageDto();
    }

    /// Constructor with only required parameters.
    this(string type, string title, int status, string detail, string timestamp,
            List!ValidationMessageDto schemaValidationErrors)
    {
        this.type_ = type;
        this.title_ = title;
        this.status_ = status;
        this.detail_ = detail;
        this.timestamp_ = timestamp;
        this.schemaValidationErrors_ = schemaValidationErrors;
    }

    ///
    ProblemDetailDto type(string type)
    {
        this.type_ = type;
        return this;
    }

    ///
    @JsonProperty("type") string getType()
    {
        return type_;
    }

    ///
    @JsonProperty("type") void setType(string type)
    {
        this.type_ = type;
    }

    ///
    ProblemDetailDto title(string title)
    {
        this.title_ = title;
        return this;
    }

    ///
    @JsonProperty("title") string getTitle()
    {
        return title_;
    }

    ///
    @JsonProperty("title") void setTitle(string title)
    {
        this.title_ = title;
    }

    ///
    ProblemDetailDto status(int status)
    {
        this.status_ = status;
        return this;
    }

    ///
    @Min(400) @Max(600) @JsonProperty("status") int getStatus()
    {
        return status_;
    }

    ///
    @JsonProperty("status") void setStatus(int status)
    {
        this.status_ = status;
    }

    ///
    ProblemDetailDto detail(string detail)
    {
        this.detail_ = detail;
        return this;
    }

    ///
    @JsonProperty("detail") string getDetail()
    {
        return detail_;
    }

    ///
    @JsonProperty("detail") void setDetail(string detail)
    {
        this.detail_ = detail;
    }

    ///
    ProblemDetailDto timestamp(string timestamp)
    {
        this.timestamp_ = timestamp;
        return this;
    }

    ///
    @JsonProperty("timestamp") string getTimestamp()
    {
        return timestamp_;
    }

    ///
    @JsonProperty("timestamp") void setTimestamp(string timestamp)
    {
        this.timestamp_ = timestamp;
    }

    ///
    ProblemDetailDto schemaValidationErrors(List!ValidationMessageDto schemaValidationErrors)
    {
        this.schemaValidationErrors_ = schemaValidationErrors;
        return this;
    }

    ///
    ProblemDetailDto addSchemaValidationErrorsItem(ValidationMessageDto schemaValidationErrorsItem)
    {
        if (this.schemaValidationErrors_ is null)
            this.schemaValidationErrors_ = new ArrayList!ValidationMessageDto();
        this.schemaValidationErrors_.add(schemaValidationErrorsItem);
        return this;
    }

    ///
    @NotNull @JsonProperty("schemaValidationErrors") List!ValidationMessageDto getSchemaValidationErrors()
    {
        return schemaValidationErrors_;
    }

    ///
    @JsonProperty("schemaValidationErrors") void setSchemaValidationErrors(
            List!ValidationMessageDto schemaValidationErrors)
    {
        this.schemaValidationErrors_ = schemaValidationErrors;
    }
}

/// `ValidationMessageDto`: Messages describing a validation error.
class ValidationMessageDto
{
    private string message_;
    private Map!(string, string) additionalProperties;

    ///
    this()
    {
    }

    /// Constructor with only required parameters.
    this(string message)
    {
        this.message_ = message;
    }

    ///
    ValidationMessageDto message(string message)
    {
        this.message_ = message;
        return this;
    }

    ///
    @JsonProperty("message") string getMessage()
    {
        return message_;
    }

    ///
    @JsonProperty("message") void setMessage(string message)
    {
        this.message_ = message;
    }

    /// Set the additional (undeclared) property with the specified name and value. If the property does not
    /// already exist, create it otherwise replace it.
    @JsonAnySetter ValidationMessageDto putAdditionalProperty(string key, string value)
    {
        if (this.additionalProperties is null)
            this.additionalProperties = new LinkedHashMap!(string, string)();
        this.additionalProperties.put(key, value);
        return this;
    }

    /// The additional (undeclared) properties.
    @JsonAnyGetter Map!(string, string) getAdditionalProperties()
    {
        return additionalProperties;
    }

    /// The additional (undeclared) property with the specified name, or null.
    string getAdditionalProperty(string key)
    {
        return this.additionalProperties is null ? null : this.additionalProperties.get(key);
    }
}
