/* TLS handshake matrix for ADR-031: what a given OpenSSL build negotiates, probe by probe.
 *
 * tools/tls_profile_matrix.py builds this file twice, once against each OpenSSL install it compares, and
 * drives these modes:
 *
 *   ciphers                       list every TLS 1.2-and-below cipher this OpenSSL knows
 *   gencert DIR                   write RSA-2048, ECDSA P-256 and Ed25519 self-signed certificates
 *   serve-flint PORT CERT KEY     Flint's TLS server profile: native/ffi/flint_web_tls.c, unmodified
 *   serve-all PORT DIR            a server that accepts every version, cipher, group and signature
 *   probe PORT FILE               one handshake per probe line, one JSON result per line on stdout
 *
 * A probe line is "<kind> <value>": default, version, cipher12, suite13, group12, group13, sigalg12,
 * sigalg13 or alpn. Each restricts only that one client setting and leaves OpenSSL's defaults otherwise.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/objects.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "flint_web.h"

static int listen_on(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons((unsigned short)port) };
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 16) != 0) {
        perror("listen");
        exit(2);
    }
    printf("ready\n");
    fflush(stdout);
    return fd;
}

static void timeouts(int fd) {
    struct timeval limit = { .tv_sec = 5 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, sizeof(limit));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, sizeof(limit));
}

static int flush_session(flint_tls_session *session, int fd) {
    uint8_t buffer[4096];
    while (flint_tls_pending(session) > 0) {
        size_t count = flint_tls_send(session, buffer, sizeof(buffer));
        if (count == 0 || send(fd, buffer, count, MSG_NOSIGNAL) != (ssize_t)count)
            return -1;
    }
    return 0;
}

/* Flint's profile drives a memory-BIO session; this pump moves its records to and from the socket. */
static void serve_flint(int port, const char *certificate, const char *key) {
    flint_tls_context *context = flint_tls_open(certificate, key, 1);
    if (context == NULL) {
        fprintf(stderr, "flint_tls_open failed\n");
        exit(2);
    }
    int listener = listen_on(port);
    for (;;) {
        int fd = accept(listener, NULL, NULL);
        if (fd < 0)
            continue;
        timeouts(fd);
        flint_tls_session *session = flint_tls_accept(context);
        int state = FLINT_TLS_WAIT;
        uint8_t buffer[4096];
        while (state == FLINT_TLS_WAIT) {
            state = flint_tls_handshake(session);
            if (flush_session(session, fd) != 0)
                state = FLINT_TLS_ERROR;
            if (state != FLINT_TLS_WAIT)
                break;
            ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
            if (count <= 0 || flint_tls_receive(session, buffer, (size_t)count) != 0)
                state = FLINT_TLS_ERROR;
        }
        if (state == FLINT_TLS_READY) {
            size_t consumed = 0;
            const char *reply = flint_tls_protocol(session) == 2 ? "ok h2\n" : "ok http/1.1\n";
            flint_tls_write(session, (const uint8_t *)reply, strlen(reply), &consumed);
            flint_tls_shutdown(session);
            flush_session(session, fd);
        }
        flint_tls_free(session);
        close(fd);
    }
}

static const char *ALL_GROUPS =
    "?X25519MLKEM768:?SecP256r1MLKEM768:?SecP384r1MLKEM1024:?X25519:?X448:?secp256r1:?secp384r1:?secp521r1:"
    "?brainpoolP256r1tls13:?brainpoolP384r1tls13:?brainpoolP512r1tls13:?ffdhe2048:?ffdhe3072:?ffdhe4096:"
    "?ffdhe6144:?ffdhe8192:?MLKEM512:?MLKEM768:?MLKEM1024:?brainpoolP256r1:?brainpoolP384r1:?brainpoolP512r1";

static int select_first(SSL *ssl, const unsigned char **out, unsigned char *outlen, const unsigned char *in,
                        unsigned int inlen, void *arg) {
    (void)ssl;
    (void)arg;
    if (inlen == 0 || in[0] + 1u > inlen)
        return SSL_TLSEXT_ERR_NOACK;
    *out = in + 1;
    *outlen = in[0];
    return SSL_TLSEXT_ERR_OK;
}

static void load(SSL_CTX *context, const char *directory, const char *name) {
    char certificate[4096], key[4096];
    snprintf(certificate, sizeof(certificate), "%s/%s.pem", directory, name);
    snprintf(key, sizeof(key), "%s/%s.key", directory, name);
    if (SSL_CTX_use_certificate_file(context, certificate, SSL_FILETYPE_PEM) != 1 ||
        SSL_CTX_use_PrivateKey_file(context, key, SSL_FILETYPE_PEM) != 1)
        fprintf(stderr, "serve-all: this OpenSSL cannot load %s\n", name);
}

static void serve_all(int port, const char *directory) {
    SSL_CTX *context = SSL_CTX_new(TLS_server_method());
    SSL_CTX_set_security_level(context, 0);
    SSL_CTX_set_min_proto_version(context, TLS1_VERSION);
    SSL_CTX_set_cipher_list(context, "ALL:COMPLEMENTOFALL:@SECLEVEL=0");
    SSL_CTX_set_ciphersuites(context, "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:"
                                      "TLS_AES_128_CCM_SHA256:TLS_AES_128_CCM_8_SHA256");
    SSL_CTX_set1_groups_list(context, ALL_GROUPS);
    SSL_CTX_set_num_tickets(context, 0);
    SSL_CTX_set_alpn_select_cb(context, select_first, NULL);
    load(context, directory, "rsa");
    load(context, directory, "ec");
    load(context, directory, "ed");
    int listener = listen_on(port);
    for (;;) {
        int fd = accept(listener, NULL, NULL);
        if (fd < 0)
            continue;
        timeouts(fd);
        SSL *ssl = SSL_new(context);
        SSL_set_fd(ssl, fd);
        if (SSL_accept(ssl) == 1) {
            SSL_write(ssl, "ok\n", 3);
            SSL_shutdown(ssl);
        }
        ERR_clear_error();
        SSL_free(ssl);
        close(fd);
    }
}

static int version_of(const char *name) {
    if (strcmp(name, "TLSv1") == 0)
        return TLS1_VERSION;
    if (strcmp(name, "TLSv1.1") == 0)
        return TLS1_1_VERSION;
    if (strcmp(name, "TLSv1.2") == 0)
        return TLS1_2_VERSION;
    if (strcmp(name, "TLSv1.3") == 0)
        return TLS1_3_VERSION;
    return -1;
}

/* Restrict one client setting; returns 0 when this OpenSSL does not accept the setting at all. */
static int configure(SSL_CTX *context, const char *kind, const char *value) {
    if (strcmp(kind, "default") == 0)
        return 1;
    if (strcmp(kind, "version") == 0) {
        int version = version_of(value);
        SSL_CTX_set_security_level(context, 0);
        return version > 0 && SSL_CTX_set_min_proto_version(context, version) == 1 &&
               SSL_CTX_set_max_proto_version(context, version) == 1 &&
               SSL_CTX_set_cipher_list(context, "ALL:@SECLEVEL=0") == 1;
    }
    if (strcmp(kind, "cipher12") == 0) {
        char list[512];
        snprintf(list, sizeof(list), "%s:@SECLEVEL=0", value);
        SSL_CTX_set_min_proto_version(context, TLS1_VERSION);
        return SSL_CTX_set_max_proto_version(context, TLS1_2_VERSION) == 1 &&
               SSL_CTX_set_cipher_list(context, list) == 1;
    }
    if (strcmp(kind, "suite13") == 0)
        return SSL_CTX_set_min_proto_version(context, TLS1_3_VERSION) == 1 &&
               SSL_CTX_set_ciphersuites(context, value) == 1;
    if (strcmp(kind, "group12") == 0 || strcmp(kind, "group13") == 0) {
        int tls13 = kind[5] == '1' && kind[6] == '3';
        if (tls13)
            SSL_CTX_set_min_proto_version(context, TLS1_3_VERSION);
        else
            SSL_CTX_set_max_proto_version(context, TLS1_2_VERSION);
        return SSL_CTX_set1_groups_list(context, value) == 1;
    }
    if (strcmp(kind, "sigalg12") == 0 || strcmp(kind, "sigalg13") == 0) {
        int tls13 = kind[6] == '1' && kind[7] == '3';
        if (tls13)
            SSL_CTX_set_min_proto_version(context, TLS1_3_VERSION);
        else
            SSL_CTX_set_max_proto_version(context, TLS1_2_VERSION);
        return SSL_CTX_set1_sigalgs_list(context, value) == 1;
    }
    if (strcmp(kind, "alpn") == 0) {
        unsigned char wire[256];
        size_t length = 0;
        char copy[256];
        snprintf(copy, sizeof(copy), "%s", value);
        for (char *token = strtok(copy, ","); token != NULL; token = strtok(NULL, ",")) {
            size_t n = strlen(token);
            if (length + n + 1 > sizeof(wire))
                return 0;
            wire[length++] = (unsigned char)n;
            memcpy(wire + length, token, n);
            length += n;
        }
        return SSL_CTX_set_alpn_protos(context, wire, (unsigned)length) == 0;
    }
    return 0;
}

static void json_string(const char *key, const char *value, int comma) {
    printf("\"%s\":", key);
    if (value == NULL)
        printf("null");
    else
        printf("\"%s\"", value);
    if (comma)
        printf(",");
}

static void probe(int port, const char *file) {
    FILE *input = fopen(file, "r");
    if (input == NULL) {
        perror(file);
        exit(2);
    }
    char line[1024];
    while (fgets(line, sizeof(line), input) != NULL) {
        char kind[64], value[900];
        if (sscanf(line, "%63s %899s", kind, value) != 2)
            continue;
        SSL_CTX *context = SSL_CTX_new(TLS_client_method());
        SSL_CTX_set_verify(context, SSL_VERIFY_NONE, NULL);
        const char *outcome = "ok";
        const char *version = NULL, *cipher = NULL, *group = NULL;
        char signature[128] = "", alpn[64] = "";
        if (!configure(context, kind, value)) {
            outcome = "client-rejects-setting";
        } else {
            int fd = socket(AF_INET, SOCK_STREAM, 0);
            timeouts(fd);
            struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons((unsigned short)port) };
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            SSL *ssl = SSL_new(context);
            SSL_set_tlsext_host_name(ssl, "localhost");
            char reply[64] = "";
            if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
                outcome = "connect-failed";
            } else {
                SSL_set_fd(ssl, fd);
                if (SSL_connect(ssl) != 1) {
                    outcome = "handshake-failed";
                } else {
                    int n = SSL_read(ssl, reply, sizeof(reply) - 1);
                    if (n <= 0)
                        outcome = "no-reply";
                    version = SSL_get_version(ssl);
                    cipher = SSL_get_cipher_name(ssl);
                    group = SSL_get0_group_name(ssl);
                    int type = NID_undef, digest = NID_undef;
                    SSL_get_peer_signature_type_nid(ssl, &type);
                    SSL_get_peer_signature_nid(ssl, &digest);
                    snprintf(signature, sizeof(signature), "%s+%s", OBJ_nid2sn(type), OBJ_nid2sn(digest));
                    const unsigned char *selected = NULL;
                    unsigned int length = 0;
                    SSL_get0_alpn_selected(ssl, &selected, &length);
                    if (length > 0 && length < sizeof(alpn)) {
                        memcpy(alpn, selected, length);
                        alpn[length] = 0;
                    }
                }
            }
            SSL_free(ssl);
            close(fd);
        }
        ERR_clear_error();
        printf("{");
        json_string("kind", kind, 1);
        json_string("value", value, 1);
        json_string("outcome", outcome, 1);
        json_string("version", version, 1);
        json_string("cipher", cipher, 1);
        json_string("group", group, 1);
        json_string("signature", signature[0] ? signature : NULL, 1);
        json_string("alpn", alpn[0] ? alpn : NULL, 0);
        printf("}\n");
        fflush(stdout);
        SSL_CTX_free(context);
    }
    fclose(input);
}

static void certificate(const char *directory, const char *name, EVP_PKEY *key, const EVP_MD *digest) {
    X509 *x = X509_new();
    X509_set_version(x, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(x), 1);
    X509_gmtime_adj(X509_getm_notBefore(x), -3600);
    X509_gmtime_adj(X509_getm_notAfter(x), 86400L * 3650);
    X509_set_pubkey(x, key);
    X509_NAME *subject = X509_get_subject_name(x);
    X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, (const unsigned char *)"localhost", -1, -1, 0);
    X509_set_issuer_name(x, subject);
    if (X509_sign(x, key, digest) == 0) {
        fprintf(stderr, "signing %s failed\n", name);
        exit(2);
    }
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s.pem", directory, name);
    FILE *out = fopen(path, "w");
    PEM_write_X509(out, x);
    fclose(out);
    snprintf(path, sizeof(path), "%s/%s.key", directory, name);
    out = fopen(path, "w");
    PEM_write_PrivateKey(out, key, NULL, NULL, 0, NULL, NULL);
    fclose(out);
    X509_free(x);
    EVP_PKEY_free(key);
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    if (argc == 3 && strcmp(argv[1], "gencert") == 0) {
        certificate(argv[2], "rsa", EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)2048), EVP_sha256());
        certificate(argv[2], "ec", EVP_PKEY_Q_keygen(NULL, NULL, "EC", "P-256"), EVP_sha256());
        certificate(argv[2], "ed", EVP_PKEY_Q_keygen(NULL, NULL, "ED25519"), NULL);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "ciphers") == 0) {
        /* Every TLS 1.2-and-below cipher this OpenSSL knows, for the probe list. */
        SSL_CTX *context = SSL_CTX_new(TLS_method());
        SSL_CTX_set_security_level(context, 0);
        SSL_CTX_set_cipher_list(context, "ALL:COMPLEMENTOFALL:@SECLEVEL=0");
        STACK_OF(SSL_CIPHER) *ciphers = SSL_CTX_get_ciphers(context);
        for (int i = 0; i < sk_SSL_CIPHER_num(ciphers); i++) {
            const SSL_CIPHER *cipher = sk_SSL_CIPHER_value(ciphers, i);
            if (strcmp(SSL_CIPHER_get_version(cipher), "TLSv1.3") != 0)
                printf("%s\n", SSL_CIPHER_get_name(cipher));
        }
        SSL_CTX_free(context);
        return 0;
    }
    if (argc == 5 && strcmp(argv[1], "serve-flint") == 0)
        serve_flint(atoi(argv[2]), argv[3], argv[4]);
    if (argc == 4 && strcmp(argv[1], "serve-all") == 0)
        serve_all(atoi(argv[2]), argv[3]);
    if (argc == 4 && strcmp(argv[1], "probe") == 0) {
        probe(atoi(argv[2]), argv[3]);
        return 0;
    }
    fprintf(stderr, "usage: tls_matrix gencert DIR | serve-flint PORT CERT KEY | serve-all PORT DIR | probe PORT FILE\n");
    return 2;
}
