/// `BaseEntity`, `Person` and `Owner`: properties inherited through getters and setters.
module org.springframework.samples.petclinic.model.baseentity;

import flint.jakarta.validation.constraints : Digits, NotEmpty;

@safe:

/// `BaseEntity`: the id.
class BaseEntity
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

/// `Person`: names.
class Person : BaseEntity
{
    private string firstName_;

    /// First name.
    @NotEmpty string getFirstName()
    {
        return firstName_;
    }

    /// ditto
    void setFirstName(string firstName)
    {
        firstName_ = firstName;
    }
}

/// `Owner`: contact details.
class Owner : Person
{
    private string telephone_;

    /// Telephone, digits only.
    @NotEmpty @Digits(fraction: 0, integer: 10) string getTelephone()
    {
        return telephone_;
    }

    /// ditto
    void setTelephone(string telephone)
    {
        telephone_ = telephone;
    }
}
