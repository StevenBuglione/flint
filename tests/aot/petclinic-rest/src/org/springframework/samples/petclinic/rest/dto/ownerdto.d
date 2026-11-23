/// The API's owner documents, as openapi-generator writes them: fields behind annotated getters.
module org.springframework.samples.petclinic.rest.dto.ownerdto;

import flint.jakarta.validation.constraints : NotNull;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

/// `OwnerFieldsDto`.
class OwnerFieldsDto
{
    private string firstName_;

    /// First name.
    @NotNull string getFirstName()
    {
        return firstName_;
    }

    /// ditto
    void setFirstName(string firstName)
    {
        firstName_ = firstName;
    }
}

/// `PetDto`: a boxed `Integer` owner id, null when absent.
class PetDto
{
    private Nullable!int ownerId_;

    /// The owner's id, or null.
    Nullable!int getOwnerId()
    {
        return ownerId_;
    }

    /// ditto
    void setOwnerId(Nullable!int ownerId)
    {
        ownerId_ = ownerId;
    }
}

/// `OwnerDto`: the fields plus the id and the pets.
class OwnerDto : OwnerFieldsDto
{
    private int id_;
    private List!PetDto pets_;

    /// The pets: a container property, whose descriptor the generated module registers.
    List!PetDto getPets()
    {
        return pets_;
    }

    /// ditto
    void setPets(List!PetDto pets)
    {
        pets_ = pets;
    }

    /// The id.
    int getId()
    {
        return id_;
    }

    /// ditto
    void setId(int id)
    {
        id_ = id;
    }
}
