# Jakarta Persistence mapping probe

The fixture reads a declared entity name, table and identifier column at compile time. It prints "Owner owners id" with no arguments and "owners" with an argument. The baseline emits the same output directly, with the same compiler options and no Jakarta dependency.
