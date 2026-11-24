/++
Floor reference for petclinic-rest's GET /petclinic/api/owners/{id} (docs/spring/phase1/petclinic-cpu-astra.md,
the floor-reference diagnostic). Diagnostic only, never evidence.

Arm "minimal": a fiber route on the same engine-web stack and reactor options as the Boot app, the same pinned
libpq through an engine-sql pool of ten, the same transaction and statements (BEGIN READ ONLY, petclinic's three
SELECTs, COMMIT), and the response bytes petclinic sends: status line, header fields in its order, chunked body,
and JSON with its field order, sorting and Jackson's escaping. Rows are written straight into the response; nothing
models Owner, Pet or PetType.

Arm "mapped" (FLOOR_ARM=mapped): the same handler, with petclinic-rest's object work restored after the same
statements: its Owner, Pet, PetType and Visit entities built from the rows, the OwnerDto of its OwnerMapperImpl
(constructed with its PetMapperImpl and VisitMapperImpl, as Boot wires them), and the JsonMapper Boot's Jackson
auto-configuration builds over the Flint AOT descriptors of petclinic's DTOs. The Boot context starts only for this
arm; it has no web server, servlet, MVC or security of its own. The model and mapper packages are petclinic-rest's
own files, linked; the DTO and validation packages are copies, because Flint AOT describes only a project's own
files and follows no links.

Environment: SERVER_PORT, POSTGRES_URL (jdbc:postgresql://host:port/database), POSTGRES_USER, POSTGRES_PASS, and
FLOOR_SQL_DIR (petclinic's db/postgres scripts, run at startup as petclinic's flint.sql.init.mode=always does).
Without FLOOR_SQL_DIR it reads resources/db/postgres when started from petclinic-rest's directory, as the benchmark
launcher starts a Flint port (tools/spring_diag.py --flint-binary), and petclinic-rest's copy when started from this
project's directory. SIGTERM stops it.
+/
module org.springframework.floor.app;

import flint.arena : Buffer, Error, RequestArena, Status;
import flint.boot : FlintApplication;
import flint.conc : Context, Deadline;
import flint.engine.sql : Connection, Driver, Pool, PoolOptions, Row, SqlValue, ValueKind, enablePostgres;
import flint.jackson.databind : JsonMapper;
import flint.java.time : LocalDate;
import org.springframework.samples.petclinic.mapper : OwnerMapper, OwnerMapperImpl, PetMapperImpl, VisitMapperImpl;
import org.springframework.samples.petclinic.model : Owner, Pet, PetType, Visit;
import flint.engine.web : FiberResponse, FiberRoute, Method, Request, RequestContext, Server,
    ServerOptions, StreamField, unknownLength;

@safe:

/// The statements petclinic-rest sends for one owner, as PostgreSQL receives them.
private enum ownerSql = "SELECT id, first_name, last_name, address, city, telephone FROM owners WHERE id= $1";
private enum petsColumns = "SELECT pets.id as pets_id, name, birth_date, type_id, owner_id, visits.id as visit_id, ";
private enum petsVisits = "visit_date, description, visits.pet_id as visits_pet_id FROM pets LEFT OUTER JOIN visits ";
private enum petsSql = petsColumns ~ petsVisits ~ "ON pets.id = visits.pet_id WHERE owner_id=$1 ORDER BY pets.id";
private enum typesSql = "SELECT id, name FROM types ORDER BY name";

/// The response fields petclinic-rest sends for a JSON 200, in its order; engine-web adds framing and Date.
private static immutable StreamField[] jsonFields = [
    StreamField("X-Content-Type-Options", "nosniff"), StreamField("X-XSS-Protection", "0"),
    StreamField("Cache-Control", "no-cache, no-store, max-age=0, must-revalidate"),
    StreamField("Pragma", "no-cache"), StreamField("Expires", "0"),
    StreamField("X-Frame-Options", "SAMEORIGIN"), StreamField("Vary", "Origin"),
    StreamField("Vary", "Access-Control-Request-Method"),
    StreamField("Vary", "Access-Control-Request-Headers"),
    StreamField("Content-Type", "application/json"),
];

private enum pathPrefix = "/petclinic/api/owners/";

/// A text value copied into the request's `Scratch`: its place there, or null.
private struct Text
{
    uint offset;
    uint length;
    bool isNull;
}

/// Text copied out of the request arena for the response: one stack block per request.
private struct Scratch
{
    char[16_384] storage;
    size_t used;
    bool overflowed;

    /// Empty, without touching `storage`.
    void reset() pure nothrow @nogc
    {
        used = 0;
        overflowed = false;
    }

    /// Copy `buffer`'s bytes and return where they are, or an empty text once the block is full.
    Text copy(ref scope RequestArena arena, Buffer buffer) nothrow @nogc
    {
        if (used + buffer.length > storage.length)
        {
            overflowed = true;
            return Text.init;
        }
        const start = used;
        const status = arena.read(buffer, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            storage[start .. start + bytes.length] = cast(const(char)[]) bytes;
        });
        if (status != Status.ok)
        {
            overflowed = true;
            return Text.init;
        }
        used += buffer.length;
        return Text(cast(uint) start, cast(uint) buffer.length);
    }

    /// The characters of `text`.
    const(char)[] opIndex(Text text) const return nothrow @nogc
    {
        return storage[text.offset .. text.offset + text.length];
    }
}

private enum maxPets = 64;
private enum maxVisits = 256;
private enum maxTypes = 64;

private struct VisitRow
{
    long id;
    long petId;
    Text date;
    Text description;
}

private struct PetRow
{
    long id;
    long typeId;
    long ownerId;
    Text name;
    Text birthDate;
    size_t firstVisit;
    size_t visitCount;
}

private struct TypeRow
{
    long id;
    Text name;
}

/// An integer column's value, or NULL.
private struct NullableLong
{
    long value;
    bool isNull;
}

/// One owner's rows, as the three queries return them.
private struct OwnerRows
{
    bool found;
    long id;
    Text[5] text; // first name, last name, address, city, telephone
    PetRow[maxPets] pets;
    size_t petCount;
    VisitRow[maxVisits] visits;
    size_t visitCount;
    TypeRow[maxTypes] types;
    size_t typeCount;
    bool tooMany;

    /// No rows, without touching the row arrays.
    void reset() pure nothrow @nogc
    {
        found = false;
        id = 0;
        text[] = Text.init;
        petCount = visitCount = typeCount = 0;
        tooMany = false;
    }
}

/// The JSON body, built in a stack block.
private struct Body
{
    char[16_384] storage;
    size_t used;
    bool overflowed;

    /// Empty, without touching `storage`.
    void reset() pure nothrow @nogc
    {
        used = 0;
        overflowed = false;
    }

    void put(scope const(char)[] text) nothrow @nogc
    {
        if (used + text.length > storage.length)
        {
            overflowed = true;
            return;
        }
        storage[used .. used + text.length] = text;
        used += text.length;
    }

    void put(char c) nothrow @nogc
    {
        const char[1] one = [c];
        put(one[]);
    }

    void number(long value) nothrow @nogc
    {
        char[24] digits;
        size_t start = digits.length;
        const negative = value < 0;
        ulong magnitude = negative ? -cast(ulong) value : cast(ulong) value;
        do
        {
            digits[--start] = cast(char)('0' + magnitude % 10);
            magnitude /= 10;
        }
        while (magnitude != 0);
        if (negative)
            digits[--start] = '-';
        put(digits[start .. $]);
    }

    /// A JSON string as Jackson's UTF8JsonGenerator writes it: `"` and `\` escaped, the short escapes for
    /// \b \t \n \f \r, \u00XX (upper-case hex) for other control characters, and everything else as it is.
    void quoted(scope const(char)[] text) nothrow @nogc
    {
        static immutable char[16] hex = "0123456789ABCDEF";
        put('"');
        size_t run;
        foreach (i, c; text)
        {
            char escape;
            switch (c)
            {
            case '"':
                escape = '"';
                break;
            case '\\':
                escape = '\\';
                break;
            case '\b':
                escape = 'b';
                break;
            case '\t':
                escape = 't';
                break;
            case '\n':
                escape = 'n';
                break;
            case '\f':
                escape = 'f';
                break;
            case '\r':
                escape = 'r';
                break;
            default:
                if (c >= 0x20)
                    continue;
                escape = 'u';
                break;
            }
            put(text[run .. i]);
            put('\\');
            put(escape);
            if (escape == 'u')
            {
                const char[4] code = ['0', '0', hex[(c >> 4) & 0xF], hex[c & 0xF]];
                put(code[]);
            }
            run = i + 1;
        }
        put(text[run .. $]);
        put('"');
    }

    void field(scope const(char)[] name) nothrow @nogc
    {
        put('"');
        put(name);
        put("\":");
    }

    void text(scope const(char)[] name, ref const Scratch scratch, Text value) nothrow @nogc
    {
        field(name);
        if (value.isNull)
            put("null");
        else
            quoted(scratch[value]);
    }
}

/// Whether `a` sorts before `b` ignoring ASCII case (Java's String.CASE_INSENSITIVE_ORDER on these names).
private bool lessIgnoringCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    const length = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. length)
    {
        const x = a[i] >= 'A' && a[i] <= 'Z' ? a[i] + 32 : a[i];
        const y = b[i] >= 'A' && b[i] <= 'Z' ? b[i] + 32 : b[i];
        if (x != y)
            return x < y;
    }
    return a.length < b.length;
}

/// The owner's JSON, as petclinic-rest's OwnerDto, PetDto, PetTypeDto and VisitDto serialize: pets by name
/// ignoring case, each pet's visits latest first, both stable.
private void writeOwner(ref OwnerRows rows, ref const Scratch scratch, ref Body output) nothrow @nogc
{
    // Stable insertion sorts over a few entries, as petclinic's model sorts.
    size_t[maxPets] petOrder;
    foreach (i; 0 .. rows.petCount)
    {
        size_t j = i;
        for (; j > 0 && lessIgnoringCase(scratch[rows.pets[i].name], scratch[rows.pets[petOrder[j - 1]].name]);
                --j)
            petOrder[j] = petOrder[j - 1];
        petOrder[j] = i;
    }
    output.put('{');
    static immutable string[5] names = ["firstName", "lastName", "address", "city", "telephone"];
    foreach (i, name; names)
    {
        output.text(name, scratch, rows.text[i]);
        output.put(',');
    }
    output.field("pets");
    output.put('[');
    foreach (n, index; petOrder[0 .. rows.petCount])
    {
        const pet = &rows.pets[index];
        if (n != 0)
            output.put(',');
        output.put('{');
        output.text("name", scratch, pet.name);
        output.put(',');
        output.text("birthDate", scratch, pet.birthDate);
        output.put(',');
        output.field("type");
        output.put('{');
        foreach (ref type; rows.types[0 .. rows.typeCount])
        {
            if (type.id != pet.typeId)
                continue;
            output.text("name", scratch, type.name);
            output.put(",\"id\":");
            output.number(type.id);
            break;
        }
        output.put("},\"id\":");
        output.number(pet.id);
        output.put(',');
        output.field("visits");
        output.put('[');
        size_t[maxVisits] visitOrder;
        auto visits = rows.visits[pet.firstVisit .. pet.firstVisit + pet.visitCount];
        foreach (i; 0 .. visits.length)
        {
            size_t j = i;
            for (; j > 0 && scratch[visits[i].date] > scratch[visits[visitOrder[j - 1]].date]; --j)
                visitOrder[j] = visitOrder[j - 1];
            visitOrder[j] = i;
        }
        foreach (v, at; visitOrder[0 .. visits.length])
        {
            const visit = &visits[at];
            if (v != 0)
                output.put(',');
            output.put('{');
            output.text("date", scratch, visit.date);
            output.put(',');
            output.text("description", scratch, visit.description);
            output.put(",\"id\":");
            output.number(visit.id);
            output.put(",\"petId\":");
            output.number(visit.petId);
            output.put('}');
        }
        output.put("],\"ownerId\":");
        output.number(pet.ownerId);
        output.put('}');
    }
    output.put("],\"id\":");
    output.number(rows.id);
    output.put('}');
}

/// The process's pool: opened before the server starts, then only read.
private final class Floor
{
    Pool pool;
    /// Arm "mapped": petclinic-rest's DTO mapper and Boot's JsonMapper; null for arm "minimal".
    OwnerMapper ownerMapper;
    JsonMapper jsonMapper;

    void serve(ref scope Request request, ref scope RequestContext context, FiberResponse response) @safe
    {
        const id = request.method == Method.get ? ownerId(request, context) : -1;
        if (id < 0)
        {
            respond(response, context, 404, null);
            return;
        }
        // The blocks are 48 KB together: left uninitialized (their bytes are written before they are read), only
        // their counters are set, as a handler would keep such buffers. Initializing them cost 49k instructions.
        Scratch scratch = void;
        scratch.reset();
        OwnerRows rows = void;
        rows.reset();
        const read = load(id, context.arena, context.cancellation, scratch, rows);
        if (read.code != Status.ok || scratch.overflowed || rows.tooMany)
        {
            respond(response, context, 500, null);
            return;
        }
        if (!rows.found)
        {
            respond(response, context, 404, null);
            return;
        }
        if (jsonMapper !is null)
        {
            ubyte[] json;
            try
                json = jsonMapper.writeValueAsBytes(ownerMapper.toOwnerDto(entities(rows, scratch)));
            catch (Exception failure)
            {
                import std.stdio : writeln;

                writeln("floor: mapped arm failed: ", failure.msg);
                respond(response, context, 500, null);
                return;
            }
            respond(response, context, 200, cast(const(char)[]) json);
            return;
        }
        Body output = void;
        output.reset();
        writeOwner(rows, scratch, output);
        if (output.overflowed)
        {
            respond(response, context, 500, null);
            return;
        }
        respond(response, context, 200, output.storage[0 .. output.used]);
    }

    /// The owner and its pets, types and visits as petclinic-rest's entities, as its repository builds them.
    private static Owner entities(ref OwnerRows rows, ref const Scratch scratch)
    {
        string str(Text text)
        {
            return text.isNull ? null : scratch[text].idup;
        }

        auto owner = new Owner;
        owner.setId(cast(int) rows.id);
        owner.setFirstName(str(rows.text[0]));
        owner.setLastName(str(rows.text[1]));
        owner.setAddress(str(rows.text[2]));
        owner.setCity(str(rows.text[3]));
        owner.setTelephone(str(rows.text[4]));
        PetType[] types;
        foreach (ref row; rows.types[0 .. rows.typeCount])
        {
            auto type = new PetType;
            type.setId(cast(int) row.id);
            type.setName(str(row.name));
            types ~= type;
        }
        foreach (ref row; rows.pets[0 .. rows.petCount])
        {
            auto pet = new Pet;
            pet.setId(cast(int) row.id);
            pet.setName(str(row.name));
            pet.setBirthDate(LocalDate.parse(scratch[row.birthDate]));
            foreach (type; types)
                if (type.getId() == row.typeId)
                    pet.setType(type);
            foreach (ref visitRow; rows.visits[row.firstVisit .. row.firstVisit + row.visitCount])
            {
                auto visit = new Visit;
                visit.setId(cast(int) visitRow.id);
                visit.setDate(LocalDate.parse(scratch[visitRow.date]));
                visit.setDescription(str(visitRow.description));
                pet.addVisit(visit);
            }
            owner.addPet(pet);
        }
        return owner;
    }

    /// The owner id in the request's path, or -1.
    private static long ownerId(ref scope Request request, ref scope RequestContext context) nothrow @nogc
    {
        auto path = request.path();
        if (!path.ok)
            return -1;
        bool good;
        long value;
        const status = context.arena.read(path.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            const text = cast(const(char)[]) bytes;
            if (text.length <= pathPrefix.length || text[0 .. pathPrefix.length] != pathPrefix)
                return;
            foreach (c; text[pathPrefix.length .. $])
            {
                if (c < '0' || c > '9' || value > int.max / 10)
                    return;
                value = value * 10 + (c - '0');
            }
            good = true;
        });
        return status == Status.ok && good ? value : -1;
    }

    /// The three statements in one read-only transaction on one lease, as petclinic's @Transactional(readOnly)
    /// findOwnerById does.
    private Error load(long id, ref scope RequestArena arena, ref Context context, ref Scratch scratch,
            ref OwnerRows rows) nothrow @nogc
    {
        auto acquired = pool.acquire(context);
        if (!acquired.ok())
            return acquired.error;
        auto lease = acquired.value;
        scope (exit)
            cast(void) pool.release(lease);
        // The request's own region, as the servlet path's statements use theirs. BEGIN goes with the first
        // SELECT, as engine-jdbc sends it (Connection.sendBefore, one round trip).
        lease.sendBefore("BEGIN READ ONLY");
        const SqlValue[1] key = [SqlValue(ValueKind.int64, id)];
        auto status = loadOwner(lease, key[], arena, context, scratch, rows);
        if (status.code == Status.ok && rows.found)
            status = loadPets(lease, key[], arena, context, scratch, rows);
        if (status.code == Status.ok && rows.found)
            status = loadTypes(lease, arena, context, scratch, rows);
        auto committed = lease.execute("COMMIT", [], arena, context);
        if (status.code != Status.ok)
            return status;
        return committed.ok() ? Error.init : committed.error;
    }

    private static Error loadOwner(ref Connection lease, scope const(SqlValue)[] key,
            ref scope RequestArena arena, ref Context context, ref Scratch scratch, ref OwnerRows rows) nothrow @nogc
    {
        return lease.query(ownerSql, key, arena, context, (ref Row row) @safe nothrow @nogc {
            rows.found = true;
            rows.id = integer(row, 0, arena);
            foreach (column; 1 .. 6)
                rows.text[column - 1] = text(row, column, arena, scratch);
            return Error.init;
        });
    }

    /// The owner's pets, each followed by its visits when the join found any.
    private static Error loadPets(ref Connection lease, scope const(SqlValue)[] key,
            ref scope RequestArena arena, ref Context context, ref Scratch scratch, ref OwnerRows rows) nothrow @nogc
    {
        return lease.query(petsSql, key, arena, context, (ref Row row) @safe nothrow @nogc {
            const petId = integer(row, 0, arena);
            if (rows.petCount == 0 || rows.pets[rows.petCount - 1].id != petId)
                addPet(row, petId, arena, scratch, rows);
            const visitId = nullableInteger(row, 5, arena);
            if (!visitId.isNull)
                addVisit(row, visitId.value, arena, scratch, rows);
            return Error.init;
        });
    }

    private static void addPet(ref Row row, long petId, ref scope RequestArena arena,
            ref Scratch scratch, ref OwnerRows rows) nothrow @nogc
    {
        if (rows.petCount == maxPets)
        {
            rows.tooMany = true;
            return;
        }
        rows.pets[rows.petCount++] = PetRow(petId, integer(row, 3, arena), integer(row, 4, arena),
                text(row, 1, arena, scratch), text(row, 2, arena, scratch), rows.visitCount, 0);
    }

    private static void addVisit(ref Row row, long visitId, ref scope RequestArena arena,
            ref Scratch scratch, ref OwnerRows rows) nothrow @nogc
    {
        if (rows.visitCount == maxVisits || rows.petCount == 0)
        {
            rows.tooMany = true;
            return;
        }
        VisitRow visit;
        visit.id = visitId;
        visit.date = text(row, 6, arena, scratch);
        visit.description = text(row, 7, arena, scratch);
        visit.petId = integer(row, 8, arena);
        rows.visits[rows.visitCount++] = visit;
        ++rows.pets[rows.petCount - 1].visitCount;
    }

    private static Error loadTypes(ref Connection lease, ref scope RequestArena arena,
            ref Context context, ref Scratch scratch, ref OwnerRows rows) nothrow @nogc
    {
        return lease.query(typesSql, [], arena, context, (ref Row row) @safe nothrow @nogc {
            if (rows.typeCount == maxTypes)
            {
                rows.tooMany = true;
                return Error.init;
            }
            rows.types[rows.typeCount++] = TypeRow(integer(row, 0, arena), text(row, 1, arena, scratch));
            return Error.init;
        });
    }

    private static long integer(ref Row row, uint column, ref scope RequestArena arena) nothrow @nogc
    {
        auto value = row.value(column, arena);
        return value.ok() && value.value.kind != ValueKind.null_ ? value.value.integer : 0;
    }

    /// An integer column that may be NULL.
    private static NullableLong nullableInteger(ref Row row, uint column, ref scope RequestArena arena) nothrow @nogc
    {
        auto value = row.value(column, arena);
        if (!value.ok() || value.value.kind == ValueKind.null_)
            return NullableLong(0, true);
        return NullableLong(value.value.integer, false);
    }

    private static Text text(ref Row row, uint column, ref scope RequestArena arena, ref Scratch scratch) nothrow @nogc
    {
        auto value = row.value(column, arena);
        if (!value.ok() || value.value.kind == ValueKind.null_)
            return Text(0, 0, true);
        return scratch.copy(arena, value.value.bytes);
    }

    private static void respond(FiberResponse response, ref scope RequestContext context, ushort status,
            scope const(char)[] json) nothrow @nogc
    {
        if (status != 200)
        {
            cast(void) response.begin(status, [], 0, context.cancellation);
            cast(void) response.finish(context.cancellation);
            return;
        }
        if (response.begin(200, jsonFields, unknownLength, context.cancellation).code != Status.ok)
            return;
        if (response.send(cast(const(ubyte)[]) json, context.cancellation).code != Status.ok)
            return;
        cast(void) response.finish(context.cancellation);
    }
}

/// The libpq connection string for petclinic's POSTGRES_URL, POSTGRES_USER and POSTGRES_PASS.
private string connectionString(string url, string user, string password)
{
    import std.algorithm.searching : findSplit;

    enum scheme = "jdbc:postgresql://";
    if (url.length <= scheme.length || url[0 .. scheme.length] != scheme)
        throw new Exception("POSTGRES_URL must be jdbc:postgresql://host:port/database");
    auto hostAndRest = url[scheme.length .. $].findSplit("/");
    auto hostPort = hostAndRest[0].findSplit(":");
    const database = hostAndRest[2].findSplit("?")[0];
    string text = "host=" ~ hostPort[0] ~ " dbname=" ~ database;
    if (hostPort[1].length)
        text ~= " port=" ~ hostPort[2];
    if (user.length)
        text ~= " user=" ~ user;
    if (password.length)
        text ~= " password=" ~ password;
    return text;
}

/// The pool petclinic-rest would open: PostgreSQL from its environment, ten connections.
private Pool openPool()
{
    import std.process : environment;

    PoolOptions options;
    options.driver = Driver.postgres;
    options.connectionString = connectionString(environment.get("POSTGRES_URL", ""),
            environment.get("POSTGRES_USER", ""), environment.get("POSTGRES_PASS", ""));
    options.maxConnections = 10; // HikariCP's default, as petclinic-rest's pool
    Pool pool;
    const opened = pool.open(options);
    if (opened.code != Status.ok)
        throw new Exception("could not open the pool: " ~ opened.message);
    return pool;
}

/// petclinic-rest's scripts: its own resources when started from its directory, else from this project's.
private string defaultScripts()
{
    import std.file : exists;

    enum fromPetclinic = "resources/db/postgres";
    return exists(fromPetclinic ~ "/schema.sql") ? fromPetclinic : "../../flint/petclinic-rest/" ~ fromPetclinic;
}

/// petclinic-rest's flint.sql.init.mode=always: its schema and data scripts on every start.
private void initializeDatabase(ref Pool pool)
{
    import std.file : readText;
    import std.path : buildPath;
    import std.process : environment;

    const scripts = environment.get("FLOOR_SQL_DIR", defaultScripts());
    Context context;
    auto lease = pool.acquire(context);
    if (!lease.ok())
        throw new Exception("could not reach PostgreSQL: " ~ lease.error.message);
    auto connection = lease.value;
    scope (exit)
        cast(void) pool.release(connection);
    foreach (script; ["schema.sql", "data.sql"])
    {
        const ran = connection.executeScript(readText(buildPath(scripts, script)), context);
        if (ran.code != Status.ok)
            throw new Exception(script ~ " failed: " ~ ran.message);
    }
}

/// The servlet engine's server for a Boot app (flint.engine.servlet's defaults), serving `floor`.
private void startServer(ref Server server, Floor floor)
{
    import std.conv : to;
    import std.parallelism : totalCPUs;
    import std.process : environment;

    ServerOptions options;
    options.address = "0.0.0.0";
    options.port = environment.get("SERVER_PORT", "8080").to!ushort;
    // Every allowed CPU, up to engine-web's 16 workers.
    const cpus = totalCPUs;
    options.cores = cpus == 0 ? 1 : cpus > 16 ? 16 : cast(uint) cpus;
    options.http2 = false;
    options.idleTimeoutNanos = 60_000_000_000L;
    options.maxBodyBytes = 1_048_576;
    options.maxConnectionsPerCore = 4096;
    options.maxHandlers = 200;
    const started = server.start(options);
    if (started.code != Status.ok)
        throw new Exception("could not start the server: " ~ started.message);
    const routed = server.routeFiber(FiberRoute(&floor.serve));
    if (routed.code != Status.ok)
        throw new Exception("could not route: " ~ routed.message);
}

/// Run the arm `FLOOR_ARM` selects ("minimal" by default, or "mapped"); `App` is the Boot application of arm
/// "mapped".
int runFloor(App)(string[] args)
{
    import core.atomic : atomicLoad, atomicStore;
    import core.thread.osthread : Thread;
    import core.time : msecs;
    import flint.os : onShutdownSignal;
    import std.stdio : writeln;

    if (enablePostgres() != Status.ok)
    {
        writeln("floor: the PostgreSQL driver is not linked");
        return 1;
    }
    auto floor = new Floor;
    Server server;
    try
    {
        import std.process : environment;

        if (environment.get("FLOOR_ARM", "minimal") == "mapped")
        {
            // Boot's JsonMapper, over the Flint AOT descriptors of the DTOs this project compiles, and petclinic-rest's
            // mappers as Boot wires them (this project links their sources, which Flint AOT does not scan).
            auto context = FlintApplication.run!App(args);
            floor.jsonMapper = context.getBean!JsonMapper();
            floor.ownerMapper = new OwnerMapperImpl(new PetMapperImpl(new VisitMapperImpl));
        }
        floor.pool = openPool();
        initializeDatabase(floor.pool);
        startServer(server, floor);
    }
    catch (Exception failure)
    {
        writeln("floor: ", failure.msg);
        return 1;
    }
    shared bool stopping;
    const subscription = onShutdownSignal((signal) @safe { atomicStore(stopping, true); });
    if (!subscription.ok)
    {
        writeln("floor: could not watch for SIGTERM");
        return 1;
    }
    writeln("floor: serving on port ", server.listenPort());
    Context context;
    while (!atomicLoad(stopping))
    {
        const polled = server.poll(context);
        if (polled.code != Status.ok)
            break;
        Thread.sleep(50.msecs);
    }
    server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);
    Context closing;
    cast(void) floor.pool.close(closing);
    return 0;
}
