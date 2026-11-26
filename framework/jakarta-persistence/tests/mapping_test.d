/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.mapping_test;

import flint.jakarta.persistence : Basic, CheckConstraint, Column, Entity, FetchType,
    GeneratedValue, GenerationType, Id, Index, SequenceGenerator, Table, UniqueConstraint;

@safe:

// API checks derived from Jakarta Persistence 3.2, sections 11.1 (mapping annotations) and 11.2 (schema defaults).
@("mapping defaults distinguish provider choices from explicit constraints")
unittest
{
    const entity = Entity();
    assert(entity.name == "");
    const column = Column();
    assert(column.nullable && column.insertable && column.updatable && !column.unique);
    assert(column.length == 255 && column.secondPrecision == -1 && column.check.length == 0);
    const table = Table();
    assert(table.name == "" && table.uniqueConstraints.length == 0 && table.indexes.length == 0);
    const basic = Basic();
    assert(basic.fetch == FetchType.EAGER && basic.optional);
    assert(GeneratedValue().strategy == GenerationType.AUTO);
    const sequence = SequenceGenerator();
    assert(sequence.initialValue == 1 && sequence.allocationSize == 50);
}

@("entity and identifier UDAs retain an explicit schema and generator")
unittest
{
    @Entity("Owner")
    @Table("owners", "clinic", "pets", [UniqueConstraint("owner_name", ["first_name",
            "last_name"])], [Index("owner_last_name", "last_name")], [
        CheckConstraint("valid_owner", "id > 0")
    ])
    static class Owner
    {
        @Id
        @GeneratedValue(GenerationType.SEQUENCE, "owner_ids")
        int id;
    }

    enum attributes = __traits(getAttributes, Owner);
    enum generator = __traits(getAttributes, Owner.id)[1];
    assert(attributes[0].name == "Owner");
    assert(attributes[1].schema == "pets");
    assert(attributes[1].uniqueConstraints[0].columnNames == ["first_name", "last_name"]);
    assert(attributes[1].indexes[0].columnList == "last_name");
    assert(attributes[1].check[0].constraint == "id > 0");
    static assert(is(__traits(getAttributes, Owner.id)[0] == Id));
    assert(generator.strategy == GenerationType.SEQUENCE && generator.generator == "owner_ids");
}

@("implicit foreign keys defer to the provider and explicit keys override that choice")
unittest
{
    import flint.jakarta.persistence : AssociationOverride, ConstraintMode, ForeignKey, JoinColumn,
        JoinTable, MapKeyJoinColumn, PrimaryKeyJoinColumn;

    assert(ForeignKey().value == ConstraintMode.CONSTRAINT);
    assert(JoinColumn().foreignKey.value == ConstraintMode.PROVIDER_DEFAULT);
    assert(MapKeyJoinColumn().foreignKey.value == ConstraintMode.PROVIDER_DEFAULT);
    assert(PrimaryKeyJoinColumn().foreignKey.value == ConstraintMode.PROVIDER_DEFAULT);
    assert(JoinTable().inverseForeignKey.value == ConstraintMode.PROVIDER_DEFAULT);
    assert(AssociationOverride("pet").joinTable.foreignKey.value == ConstraintMode.PROVIDER_DEFAULT);

    auto join = JoinColumn("owner_id");
    join.foreignKey = ForeignKey(ConstraintMode.NO_CONSTRAINT, "owner_ref");
    assert(join.name == "owner_id" && join.foreignKey.name == "owner_ref");
    assert(join.foreignKey.value == ConstraintMode.NO_CONSTRAINT);
}
