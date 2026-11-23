/// The API's owner documents, as openapi-generator writes them: fields behind annotated getters.
module org.springframework.samples.petclinic.rest.dto.ownerdto;

import flint.jakarta.validation.constraints : NotNull;

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

/// `OwnerDto`: the fields plus the id.
class OwnerDto : OwnerFieldsDto
{
    private int id_;

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
