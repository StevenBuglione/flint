// Misuse: an entity column of an unsupported type.
// expect: Item\.name: unsupported SQL field type
module data_entity;
import flint.data : Column, CrudRepository, SqlRepository, Table;
@Table("items") struct Item { @Column("name") string name; }
alias Items = SqlRepository!(Item, ulong);
void use() { Items* items; }
