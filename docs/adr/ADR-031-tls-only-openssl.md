# ADR-031: TLS-only OpenSSL

Status: **accepted** on 2026-11-23. This is the last Phase 0 size lever of [ADR-030](ADR-030-flint-is-a-spring-port.md) section 5, which required its own ADR.

## Context

Every executable that links `flint:engine-web`, `engine-http`, `engine-security`, `engine-sql`, `engine-mail`, `engine-mq`, `engine-rpc` or `engine-storage` links the pinned OpenSSL 3.5.9 statically. That includes the REST benchmark.

OpenSSL's providers register every algorithm they implement in dispatch tables, so `--gc-sections` keeps them all. Flint uses a small part of it:
- **Its TLS server profile:** `native/ffi/flint_web_tls.c`. TLS 1.2 is the minimum, TLS 1.2 is restricted to `ECDHE+AESGCM:ECDHE+CHACHA20`, and the TLS 1.3 suites, groups and signature algorithms are OpenSSL's defaults.
- **Its TLS clients:** curl in `engine-http` and `engine-mail`, libpq, librdkafka and the mq socket. They use OpenSSL's defaults at TLS 1.2 or later.
- **The shims' direct calls:** SHA-1 for WebSocket accept keys, SHA-256, HMAC, RSA, ECDSA and Ed25519 verification for JWTs, and random bytes.

AGENTS.md forbids using a different TLS profile to win a measurement. So the reduced build is acceptable only if every handshake negotiates exactly what it did before.

## Decision

### 1. The build

`tools/native_build.py` configures OpenSSL with `OPENSSL_TLS_ONLY`, on every target and in the sanitizer lane. The pinned version, commit and source archive in `policy/native-lock.json` are unchanged. `native/conan-index` is regenerated, because its recipes pin the build steps' hash. The install receipt records the switches as `configure_disabled`.

| Removed | Switches |
| --- | --- |
| Legacy provider and legacy ciphers | `no-legacy no-des no-rc2 no-rc4 no-bf no-cast no-idea no-seed no-camellia no-aria` |
| National and legacy algorithms | `no-sm2 no-sm3 no-sm4 no-gost no-whirlpool no-mdc2 no-rmd160 no-md4 no-dsa no-ec2m` |
| Protocols below TLS 1.2, and DTLS | `no-ssl3 no-tls1 no-tls1_1 no-dtls no-sctp no-srtp` |
| Key exchanges and extensions Flint never configures | `no-psk no-srp no-nextprotoneg no-comp` |
| Subsystems no consumer calls | `no-cms no-ts no-cmp no-ct no-engine no-dynamic-engine no-quic no-ssl-trace` |
| Unused KDFs, MACs, modes and signatures | `no-argon2 no-scrypt no-siv no-ocb no-siphash no-slh-dsa` |

**Kept, because the profile negotiates or advertises them:**
- **`dh`:** the server accepts the TLS 1.3 FFDHE groups `ffdhe2048` and `ffdhe3072` by default.
- **`ecx`:** X25519 and X448. OpenSSL 3.5 has no switch that removes Curve448 alone, and X25519 is what clients negotiate.
- **ML-KEM:** `X25519MLKEM768` is the default first group, and both OpenSSL 3.5 and Go negotiate it.
- **ML-DSA:** in OpenSSL's default signature algorithm list.
- **Also kept:** OCSP (curl's certificate status option) and the HTTP client OCSP depends on, plus everything TLS 1.2 and 1.3 use: AES, ChaCha20-Poly1305, SHA-1/2/3, HMAC, HKDF, RSA, ECDSA, EdDSA and DRBG.

The removals take away three client features no Flint code uses:
- curl's NTLM authentication, which needs DES and MD4;
- PSK and SRP key exchange;
- negotiating TLS 1.0 or 1.1, which Flint's clients already refuse: `engine-http` sets `CURL_SSLVERSION_TLSv1_2` and the mq socket sets a TLS 1.2 minimum.

### 2. The TLS profile is unchanged: the handshake matrix

`tools/tls_profile_matrix.py` compiles `tools/tls_matrix/tls_matrix.c` against each OpenSSL build and runs 265 probes. Each probe restricts one client setting and records the outcome and the negotiated version, cipher, group, peer signature and ALPN. The settings probed are:
- each protocol version;
- every TLS 1.2-and-below cipher the full build knows (ALL:COMPLEMENTOFALL at security level 0);
- each TLS 1.3 suite;
- 22 groups and 26 signature algorithms, under TLS 1.2 and under TLS 1.3;
- four ALPN offers.

It runs two matrices:
- **Server.** Flint's server profile is `flint_web_tls.c`, unmodified, linked with each build, with an RSA-2048 and an ECDSA P-256 certificate. The client is the full build.
- **Client.** Each build acts as a client with OpenSSL's defaults, as curl, libpq and librdkafka use it. The server is a full-build server that accepts every version, cipher, group and signature.

| Matrix | Probes | Negotiated, full build | Negotiated, TLS-only | Differences |
| --- | ---: | ---: | ---: | ---: |
| Server, RSA certificate | 265 | 35 | 35 | 0 |
| Server, ECDSA certificate | 265 | 26 | 26 | 0 |
| Client, OpenSSL defaults | 265 | 121 | 105 | 108 |

**Server: the TLS profile itself.** No probe differs. Before and after, Flint's server negotiates:
- TLS 1.2 with `ECDHE-ECDSA-AES128-GCM-SHA256`, `ECDHE-ECDSA-AES256-GCM-SHA384`, `ECDHE-ECDSA-CHACHA20-POLY1305`, `ECDHE-RSA-AES128-GCM-SHA256`, `ECDHE-RSA-AES256-GCM-SHA384`, `ECDHE-RSA-CHACHA20-POLY1305`;
- TLS 1.3 with `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`;
- the groups `X25519MLKEM768`, `ffdhe2048`, `ffdhe3072`, `secp256r1`, `secp384r1`, `secp521r1`, `x25519`, `x448`;
- the peer signatures `RSASSA-PSS+SHA256`, `RSASSA-PSS+SHA384`, `RSASSA-PSS+SHA512`, `id-ecPublicKey+SHA224`, `id-ecPublicKey+SHA256`, `id-ecPublicKey+SHA384`, `id-ecPublicKey+SHA512`, `rsaEncryption+SHA224`, `rsaEncryption+SHA256`, `rsaEncryption+SHA384`, `rsaEncryption+SHA512`.

Its default handshake is TLSv1.3 `TLS_AES_256_GCM_SHA384` over `X25519MLKEM768`, in both builds. TLS 1.0 and 1.1, every other cipher and every other group are refused in both builds.

**Client.** The default handshake is identical, and so are the suite, group, ALPN and signature probes. The 108 differing probes each name, explicitly, a feature this ADR removes:

- PSK, SRP, ARIA, Camellia, SEED, IDEA, DES and RC4 ciphers named explicitly (failed before as well): 88
- ARIA and Camellia ciphers named explicitly at security level 0: 14
- DSA signature algorithms (failed before as well: no DSA certificate): 4
- TLS 1.0 and 1.1, offered at security level 0: 2

The only client probes that negotiated before and fail now are TLS 1.0 and 1.1 and the 14 ARIA and Camellia ciphers (`ARIA128-GCM-SHA256`, `ARIA256-GCM-SHA384`, `CAMELLIA128-SHA`, `CAMELLIA128-SHA256`, `CAMELLIA256-SHA`, `CAMELLIA256-SHA256`, `ECDHE-ARIA128-GCM-SHA256`, `ECDHE-ARIA256-GCM-SHA384`, `ECDHE-ECDSA-ARIA128-GCM-SHA256`, `ECDHE-ECDSA-ARIA256-GCM-SHA384`, `ECDHE-ECDSA-CAMELLIA128-SHA256`, `ECDHE-ECDSA-CAMELLIA256-SHA384`, `ECDHE-RSA-CAMELLIA128-SHA256`, `ECDHE-RSA-CAMELLIA256-SHA384`). Each needs the client to name the cipher or version at security level 0, and Flint's clients never configure either. With its defaults, every Flint client still negotiates what it did.

### 3. Size

| bench-rest | Before | TLS-only OpenSSL | Saved |
| --- | ---: | ---: | ---: |
| O3 | 5,904,304 | 5,005,088 | 899,216 (15.2%) |
| Oz | 5,855,152 | 4,955,936 | 899,216 (15.4%) |

Measured with `tools/measure_builds.py --app-sizes --app bench-rest`: stripped, release (O3) and size (Oz) profiles, LDC 1.43 with ThinLTO. The before build is `241096fadb`; the after build is the same tree plus this change, `12c131e1f3` before rebasing. `libcrypto.a` shrinks from 14,418,128 to 10,874,068 bytes, and `libssl.a` from 2,409,626 to 1,423,552.

## Verification

On venus (Linux x86-64, glibc 2.39), the native providers were rebuilt with `tools/native_build.py --profile ci`, with the private toolchain verified by `flint toolchain verify` (fork patch `64703b0b…`).

- **Native C tests.** The shims' native tests pass against the TLS-only build, including `mq_socket_test` for the TLS socket. They are run by the provider build's `ctest`.
- **Engine suites with real peers.** `flint test engine-web engine-http engine-security engine-sql engine-mail engine-mq engine-rpc engine-storage --compiler both --verify` passes 16 of 16 runs: every OpenSSL consumer, on DMD and LDC.
  - The peers are the Go HTTP/1.1, HTTP/2 and TLS peer (`http`), the Go HTTPS JWKS peer (`jwks`), PostgreSQL 18.7 built from source, the SMTP peer, and MinIO and S3.
  - engine-web covers the TLS server.
- **Policy and tooling.** `tools/conan_index.py --check`, `tests/test_conan_index.py`, `tests/test_flint_native*.py`, `tools/test_guards.py` and `tools/gates.py --gate structural` pass.
- **Handshake matrix.** It ran as in section 2, with the full build saved before the change as the reference.

Commands, for reproducing:

```bash
python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build --emit-dub
python3 tools/tls_profile_matrix.py --reference <full-install> --openssl full=<full-install> \
    --openssl tls-only=.native/install/linux-x86_64-glibc --output tls-matrix.json
python3 tools/measure_builds.py --app-sizes --app bench-rest --output sizes.json
```

Start-up and throughput timings are queued with the proof-harness session's quiet-window measurement queue. venus was too busy for timing evidence.

## Consequences

- Smaller executables for every TLS consumer, with the same TLS profile.
- A future need for a removed algorithm needs an amendment here and a new matrix run. Examples are NTLM through curl, a DTLS or QUIC transport, CMS or a national cipher.
- A change to `flint_web_tls.c`, or to the switches, reruns `tools/tls_profile_matrix.py` against the full build. Any difference in the server matrix is a TLS profile change and needs its own review.
- macOS and Windows build the same switches. They are verified on Linux x86-64 glibc; the platform lanes verify their own builds.
