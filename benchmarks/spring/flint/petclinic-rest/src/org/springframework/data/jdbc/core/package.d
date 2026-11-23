/++
`org.springframework.data.jdbc.core.OneToManyResultSetExtractor` from Spring Data JDBC Extensions 1.2.1, the
library spring-petclinic-rest's `JdbcPetVisitExtractor` extends.

That library is not in Flint's licence matrix (`policy/upstream-licences.json`), so this is a clean-room
implementation from its documented behaviour, not a port of its source: rows ordered by the root's primary key
become one root per key, each with the children whose foreign key is set; the number of roots is checked against
`ExpectedResults`. It lives in the application, as the third-party dependency it is.
+/
module org.springframework.data.jdbc.core;

import flint.dao : IncorrectResultSizeDataAccessException;
import flint.java.sql : ResultSet;
import flint.java.util : ArrayList, List;
import flint.jdbc.core : ResultSetExtractor, RowMapper;
import std.typecons : Nullable;

@safe:

/// How many root objects a `OneToManyResultSetExtractor` expects.
enum ExpectedResults
{
    ANY, ///
    ONE_AND_ONLY_ONE, ///
    ONE_OR_NONE, ///
    AT_LEAST_ONE ///
}

/++
A `ResultSetExtractor` that maps a one-to-many join into root objects `R`, each with its child objects `C`. The rows
must be ordered by the root's primary key `K`. Subclasses say how to read the primary and foreign keys and how to
attach a child.
+/
abstract class OneToManyResultSetExtractor(R, C, K) : ResultSetExtractor!(List!R)
{
    /// Maps the root object of a row.
    protected RowMapper!R rootMapper;
    /// Maps the child object of a row.
    protected RowMapper!C childMapper;
    /// The expected number of roots.
    protected ExpectedResults expectedResults;

    /// Extract roots with their children, any number of roots.
    this(RowMapper!R rootMapper, RowMapper!C childMapper)
    {
        this(rootMapper, childMapper, ExpectedResults.ANY);
    }

    /// Extract roots with their children, checking the number of roots.
    this(RowMapper!R rootMapper, RowMapper!C childMapper, ExpectedResults expectedResults)
    {
        this.rootMapper = rootMapper;
        this.childMapper = childMapper;
        this.expectedResults = expectedResults;
    }

    override List!R extractData(ResultSet rs)
    {
        auto results = new ArrayList!R;
        int row;
        bool more = rs.next();
        if (more)
            ++row;
        while (more)
        {
            auto root = rootMapper.mapRow(rs, row);
            const primaryKey = mapPrimaryKey(rs);
            do
            {
                const foreignKey = mapForeignKey(rs);
                if (!foreignKey.isNull && foreignKey.get == primaryKey)
                    addChild(root, childMapper.mapRow(rs, row));
                more = rs.next();
                if (more)
                    ++row;
            }
            while (more && mapPrimaryKey(rs) == primaryKey);
            results.add(root);
        }
        checkResultSize(results.size());
        return results;
    }

    private void checkResultSize(int size)
    {
        const ok = expectedResults == ExpectedResults.ANY
            || (expectedResults == ExpectedResults.ONE_AND_ONLY_ONE && size == 1)
            || (expectedResults == ExpectedResults.ONE_OR_NONE && size <= 1)
            || (expectedResults == ExpectedResults.AT_LEAST_ONE && size >= 1);
        if (!ok)
            throw new IncorrectResultSizeDataAccessException(1, size);
    }

    /// The root's primary key in the current row.
    protected abstract K mapPrimaryKey(ResultSet rs);

    /// The child's foreign key in the current row, or null when the row has no child.
    protected abstract Nullable!K mapForeignKey(ResultSet rs);

    /// Attach `child` to `root`.
    protected abstract void addChild(R root, C child);
}
