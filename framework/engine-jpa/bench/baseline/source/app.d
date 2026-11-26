/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module app;

import core.stdc.stdio : fputc, stdout;
import flint.engine.jdbc : FlintDataSource, enablePostgres;

@safe:

private final class Owner
{
    long id;
    string name;
}

int main(string[] args)
{
    if (args.length != 4)
        return 2;
    enablePostgres();
    auto dataSource = new FlintDataSource(args[1]);
    dataSource.setUsername(args[2]);
    dataSource.setPassword(args[3]);
    scope (exit)
        dataSource.close();
    auto connection = dataSource.getConnection();
    scope (exit)
        connection.close();
    auto statement = connection.prepareStatement("select 'One'::text as name, 1::bigint as id");
    scope (exit)
        statement.close();
    auto rows = statement.executeQuery();
    scope (exit)
        rows.close();
    if (!rows.next())
        return 1;
    auto owner = new Owner;
    owner.name = rows.getString(1);
    if (rows.wasNull())
        return 1;
    owner.id = rows.getLong(2);
    if (rows.wasNull() || owner.id != 1 || owner.name != "One")
        return 1;
    foreach (character; owner.name)
        fputc(character, stdout);
    fputc('\n', stdout);
    return 0;
}
