/* Checks the pinned crypt-blowfish provider (policy/native-lock.json) through the two entry points Flint uses.
 *
 *   cc -I<prefix>/include crypt_blowfish_vectors.c <prefix>/lib/libcrypt_blowfish.a -o vectors && ./vectors
 *
 * Positive: upstream's OpenBSD-compatible vectors for each prefix ($2a$, $2b$, $2y$ and the legacy $2x$), the
 * 72-byte key limit, petclinic-rest's seeded admin hash, and a salt from _crypt_gensalt_blowfish_rn that hashes and
 * verifies. Negative: a wrong key, an unsupported prefix, a cost outside 4..31, a truncated setting, a short output
 * buffer and a short salt input are each refused or mismatch. Exit status 0 means every case held. */
#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "crypt_blowfish.h"

static int failures;

static void expect(int condition, const char *what)
{
    if (!condition)
    {
        failures++;
        printf("FAIL %s\n", what);
    }
}

/* The hash of `key` under the setting (prefix, cost and salt) of `hash`, compared with `hash`. */
static int verifies(const char *key, const char *hash)
{
    char output[61];
    const char *result = _crypt_blowfish_rn(key, hash, output, (int)sizeof output);
    return result != NULL && strcmp(result, hash) == 0;
}

static const char *const vectors[][2] = {
    {"$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", "U*U"},
    {"$2a$05$CCCCCCCCCCCCCCCCCCCCC.VGOzA784oUp/Z0DY336zx7pLYAy0lwK", "U*U*"},
    {"$2a$05$XXXXXXXXXXXXXXXXXXXXXOAcXxm9kjPGEMsLznoKqmqw7tc8WCx4a", "U*U*U"},
    {"$2a$05$abcdefghijklmnopqrstuu5s2v8.iXieOjg/.AySBTTZIIVFJeBui",
     "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789chars after 72 are ignored"},
    {"$2x$05$/OK.fbVrR/bpIqNJ5ianF.CE5elHaaO4EbggVDjb8P19RukzXSM3e", "\xff\xff\xa3"},
    {"$2y$05$/OK.fbVrR/bpIqNJ5ianF.CE5elHaaO4EbggVDjb8P19RukzXSM3e", "\xff\xff\xa3"},
    {"$2a$05$/OK.fbVrR/bpIqNJ5ianF.nqd1wy.pTMdcvrRWxyiGL2eMz.2a85.", "\xff\xff\xa3"},
    {"$2b$05$/OK.fbVrR/bpIqNJ5ianF.CE5elHaaO4EbggVDjb8P19RukzXSM3e", "\xff\xff\xa3"},
    {"$2y$05$/OK.fbVrR/bpIqNJ5ianF.Sa7shbm4.OzKpvFnX1pQLmQW96oUlCq", "\xa3"},
    {"$2a$05$/OK.fbVrR/bpIqNJ5ianF.Sa7shbm4.OzKpvFnX1pQLmQW96oUlCq", "\xa3"},
    {"$2b$05$/OK.fbVrR/bpIqNJ5ianF.Sa7shbm4.OzKpvFnX1pQLmQW96oUlCq", "\xa3"},
    {"$2a$05$/OK.fbVrR/bpIqNJ5ianF.6IflQkJytoRVc1yuaNtHfiuq.FRlSIS", "\xa3" "ab"},
    {"$2a$05$/OK.fbVrR/bpIqNJ5ianF.R9xrDjiycxMbQE2bp.vgqlYpW5wx2yy",
     "\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55"
     "\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55"
     "\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55\xaa\x55"},
    {"$2a$05$CCCCCCCCCCCCCCCCCCCCC.7uG0VCzI2bS7j6ymqJi9CdcdxiRTWNy", ""},
    /* petclinic-rest's data.sql seeds user admin with password admin. */
    {"$2a$10$ymaklWBnpBKlgdMgkjWVF.GMGyvH8aDuTK.glFOaKw712LHtRRymS", "admin"},
};

static void positive(void)
{
    for (size_t i = 0; i < sizeof vectors / sizeof vectors[0]; i++)
    {
        char what[96];
        snprintf(what, sizeof what, "vector %zu (%.7s)", i, vectors[i][0]);
        expect(verifies(vectors[i][1], vectors[i][0]), what);
    }
    /* A fresh salt: 16 input bytes at cost 4 encode to "$2b$04$" plus 22 salt characters, then hash and verify. */
    const char random[16] = "0123456789abcdef";
    char setting[30];
    const char *salt = _crypt_gensalt_blowfish_rn("$2b$", 4, random, (int)sizeof random, setting, (int)sizeof setting);
    expect(salt != NULL && strlen(salt) == 29 && strncmp(salt, "$2b$04$", 7) == 0, "gensalt $2b$04$");
    char hash[61];
    const char *made = salt ? _crypt_blowfish_rn("koala", salt, hash, (int)sizeof hash) : NULL;
    expect(made != NULL && strlen(made) == 60 && strncmp(made, salt, 29) == 0, "hash of a generated salt");
    expect(made != NULL && verifies("koala", made), "generated hash verifies");
    expect(made != NULL && !verifies("koalb", made), "generated hash rejects another key");
}

/* The setting is refused: NULL with errno set. */
static void refused(const char *setting, int size, int error, const char *what)
{
    char output[61];
    errno = 0;
    const char *result = _crypt_blowfish_rn("key", setting, output, size);
    expect(result == NULL && errno == error, what);
}

static void negative(void)
{
    expect(!verifies("U*V", vectors[0][0]), "a wrong key mismatches");
    expect(!verifies("admin ", vectors[sizeof vectors / sizeof vectors[0] - 1][0]), "a trailing space mismatches");
    refused("$2c$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", 61, EINVAL, "unsupported prefix $2c$");
    refused("$2a$03$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", 61, EINVAL, "cost 3 is below 4");
    refused("$2a$32$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", 61, EINVAL, "cost 32 is above 31");
    refused("$2a$05$CCCC", 61, EINVAL, "a truncated salt");
    refused("$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", 60, ERANGE, "60-byte output buffer");
    char setting[30];
    errno = 0;
    expect(_crypt_gensalt_blowfish_rn("$2b$", 10, "short", 5, setting, (int)sizeof setting) == NULL && errno == EINVAL,
           "gensalt refuses fewer than 16 input bytes");
    errno = 0;
    expect(_crypt_gensalt_blowfish_rn("$2b$", 10, "0123456789abcdef", 16, setting, 29) == NULL && errno == ERANGE,
           "gensalt refuses a 29-byte output buffer");
}

int main(void)
{
    positive();
    negative();
    printf("%s: %d failure(s)\n", failures ? "FAILED" : "ok", failures);
    return failures != 0;
}
