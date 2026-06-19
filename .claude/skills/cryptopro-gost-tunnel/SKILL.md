---
name: cryptopro-gost-tunnel
description: >-
  Build, operate, and debug this project's CryptoPro CSP GOST TLS tunnel
  (stunnel + socat) and GOST detached signing. Use when editing the Docker
  image or .docker/scripts, configuring stunnel/socat, importing CryptoPro
  certificates and key containers, wiring an HTTP proxy, or troubleshooting
  GOST-TLS handshake / key-container / signing failures.
metadata:
  author: aif-skill-generator
  version: "1.0"
  category: infrastructure
---

# CryptoPro GOST TLS Tunnel

This project (`rfm-tunel`) is a Docker container that exposes a plain local
port and proxies traffic over a **GOST TLS** session to an upstream host,
using **CryptoPro CSP** for the Russian GOST cryptography. It also performs
**detached GOST signing** of documents. Use this skill when working on the
build (`.docker/Dockerfile`), runtime scripts (`.docker/scripts/`), or the
stunnel/socat configuration.

## Architecture at a glance

```
client ──HTTP──▶ stunnel (:8080, GOST-TLS client)
                   │  connect = unix:/var/run/socat.sock
                   ▼
                 socat (UNIX-LISTEN ─▶ TCP:${STUNNEL_HOST})
                   │  optional: PROXY:${STUNNEL_HTTP_PROXY}
                   ▼
                 upstream GOST endpoint
```

- **stunnel** terminates the GOST-TLS client side; it presents the exported
  client certificate (`/etc/stunnel/client.crt`) and connects to a local Unix
  socket, not directly to the network.
- **socat** bridges that Unix socket to the real upstream (`STUNNEL_HOST`),
  optionally traversing an HTTP proxy. It runs in a restart loop so a dropped
  connection re-establishes automatically.
- **CryptoPro CSP** holds the GOST private key inside its own container store
  (`HDIMAGE`, under `/var/opt/cprocsp/keys/root/`). The private key never
  leaves the store — only the public client certificate is exported.

## Key invariants (do not break these)

1. **GOST private keys stay in the CryptoPro store.** Only export the public
   client certificate for stunnel. Never copy `*.key` container files out of
   the image or log them.
2. **Secrets are injected, never committed.** `resource/root.cer`,
   `resource/root.zip`, `CERTIFICATE_PIN`, and `CRYPTO_PRO_LICENSE` come in as
   build args / mounted resources. Keep them out of version control.
3. **stunnel connects to the Unix socket, not the network.**
   `connect=/var/run/socat.sock`; the network hop belongs to socat. Keep that
   split — it is what allows optional proxy traversal without touching stunnel.
4. **GOST hash algorithm OID is `1.2.643.7.1.1.2.2`** (GOST R 34.11-2012,
   256-bit) for `cryptcp -sign`. Don't substitute a non-GOST algorithm.
5. **Architecture is selected via `TARGETARCH`** (`linux-${TARGETARCH}_deb`).
   Preserve multi-arch (amd64 / arm64) support when editing the Dockerfile.
6. **CryptoPro output is cp1251.** Pipe names that may contain Cyrillic through
   `iconv -fcp1251 -tutf-8` before displaying (see `setup_my_certificate`).
7. **Fail fast.** Init scripts must `exit 1` when a key container, certificate,
   or required key file is missing — a half-configured tunnel is worse than a
   clear failure.

## Startup sequence (`entrypoint.sh`)

1. Install the CA into the `mCA` store; copy the root key container into
   `/var/opt/cprocsp/keys/root/` and `chmod 600` its files.
2. Discover the private-key container:
   `csptest -keys -enum -verifyc -fqcn -un | grep HDIMAGE` → take the container
   name. Abort if none is found.
3. Install the certificate with its private key into that container
   (`certmgr -inst -cont "$containerName"`).
4. Export the client certificate for stunnel
   (`certmgr -export -dest /etc/stunnel/client.crt`); abort if the file is
   missing.
5. Start `socat` in the background (`stunnel-socat.sh`), patch
   `STUNNEL_DEBUG_LEVEL` into `stunnel.conf`, then `exec` stunnel in the
   foreground.

## Environment variables

| Variable | Stage | Purpose |
|----------|-------|---------|
| `STUNNEL_HOST` | runtime | Upstream `host:port` socat connects to |
| `STUNNEL_HTTP_PROXY` | runtime | Optional HTTP proxy host |
| `STUNNEL_HTTP_PROXY_PORT` | runtime | Proxy port (`proxyport=`) |
| `STUNNEL_HTTP_PROXY_CREDENTIALS` | runtime | `login:pass` for `proxyauth=` |
| `STUNNEL_DEBUG_LEVEL` | runtime | stunnel verbosity, patched into config |
| `CERTIFICATE_PIN` | build | PIN to link cert ↔ private-key container |
| `CRYPTO_PRO_LICENSE` | build | CryptoPro license key (`cpconfig -license`) |
| `TARGETARCH` | build | Selects `linux-${TARGETARCH}_deb` packages |

## Common tasks

- **Add/refresh the upstream:** set `STUNNEL_HOST`; no rebuild needed (socat
  reads it at start). Verify the listener loop in `stunnel-socat.sh`.
- **Route through a corporate proxy:** set `STUNNEL_HTTP_PROXY[_PORT]` and, if
  required, `STUNNEL_HTTP_PROXY_CREDENTIALS`. socat switches from `TCP:` to
  `PROXY:` automatically.
- **Sign a document (detached GOST):** pipe content to `scripts/sign <PIN>`; it
  uses `cryptcp -sign -thumbprint "$containerHash" -nochain -hashAlg
  1.2.643.7.1.1.2.2 -detached`. The `containerHash` must be baked into the
  image at build time — empty hash → script exits 1.
- **Rotate certificates/keys:** replace `resource/root.zip` (key container +
  cert bundle) and `resource/root.cer`; rebuild with the matching
  `CERTIFICATE_PIN`.

## Troubleshooting

For detailed command reference, failure signatures, and fixes (handshake
errors, "Keys container not found", PrivateKey-Link issues, proxy/socat
failures, signing errors), read **[references/OPERATIONS.md](references/OPERATIONS.md)**.

## Conventions

Follow the project conventions in `.ai-factory/rules/base.md`: snake_case
setup scripts, `camelCase` bash locals, `UPPER_SNAKE` env vars, `|| exit 1`
fail-fast error handling, colored `info`/`ok`/`warning`/`error` logging from
`scripts/lib/functions.sh`, and Russian comments in shell scripts.
