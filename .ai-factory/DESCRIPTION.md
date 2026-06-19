# rfm-tunel

## Overview

`rfm-tunel` is a containerized GOST TLS tunnel that lets standard HTTP clients
talk to a remote service secured with Russian GOST cryptography (CryptoPro CSP).
A client connects to a plain local port; the container terminates/initiates the
GOST-TLS session using a CryptoPro key container and client certificate, and
forwards traffic to the upstream host (optionally through an HTTP proxy).

The repository also ships a small, independent **MarkItDown** helper image used to
convert API documentation (e.g. `api-rfm.docx`) into Markdown.

## Core Features

- GOST TLS client tunnel via **stunnel** listening on local port `8080`.
- Upstream connection (and optional HTTP/HTTPS proxy traversal) via **socat**
  over a Unix domain socket (`/var/run/socat.sock`).
- **CryptoPro CSP** integration: license install, root/CA certificate import,
  private-key container setup, and client-certificate export at container start.
- Detached GOST signing of documents (`scripts/sign`, `cryptcp` with hash
  algorithm `1.2.643.7.1.1.2.2`) and the **phpcades** (CAdES) library for PHP.
- Multi-architecture build support via `TARGETARCH` (amd64 / arm64 CryptoPro
  packages).
- Separate MarkItDown converter image for documentation processing.

## Tech Stack

- **Programming language:** Bash (init/runtime scripts), Expect (interactive
  certmgr automation); PHP 8.3 runtime present for the phpcades/CAdES library.
- **Framework:** None (infrastructure / shell tooling).
- **Database:** None.
- **ORM:** None.
- **Crypto / runtime:** CryptoPro CSP, `cprocsp-pki-phpcades` (CAdES), stunnel,
  socat, OpenSSL-compatible GOST stack.
- **Packaging:** Docker (Debian `bookworm-slim` base for the tunnel;
  `python:3.11-slim` for the MarkItDown helper).
- **Integrations:** Remote GOST-TLS upstream (configured via `STUNNEL_HOST`),
  optional HTTP proxy (`STUNNEL_HTTP_PROXY*`).

## Architecture Notes

- **Entrypoint flow** (`.docker/scripts/entrypoint.sh`): configure CSP → import
  CA and root certificates → locate the `HDIMAGE` key container → install and
  export the client certificate for stunnel → start `socat` (background) → start
  `stunnel` (foreground, `exec "$@"`).
- **Traffic path:** client → `stunnel` (`:8080`, GOST-TLS client) →
  `unix:/var/run/socat.sock` → `socat` → `TCP:${STUNNEL_HOST}` (direct or via
  `PROXY:` with optional `proxyauth`).
- **Configuration is environment-driven:** `STUNNEL_HOST`, `STUNNEL_HTTP_PROXY`,
  `STUNNEL_HTTP_PROXY_PORT`, `STUNNEL_HTTP_PROXY_CREDENTIALS`,
  `STUNNEL_DEBUG_LEVEL`, plus build-time `CERTIFICATE_PIN` and
  `CRYPTO_PRO_LICENSE`.
- **Secret material** (`resource/`: `root.cer`, `root.zip`) and the license/PIN
  are supplied at build/run time and are kept out of version control.
- The MarkItDown image is fully decoupled from the tunnel — it only consumes a
  `.docx` on stdin and emits Markdown on stdout (`app.sh`).

## Non-Functional Requirements

- **Logging:** stunnel verbosity is configurable via `STUNNEL_DEBUG_LEVEL`
  (rewritten into `stunnel.conf` at startup); scripts log status with colored
  `info`/`ok`/`warning`/`error` helpers.
- **Error handling:** init scripts fail fast (`exit 1`) when key containers,
  certificates, or required key files are missing.
- **Resilience:** the `socat` listener runs in a restart loop so a dropped
  upstream connection is automatically re-established.
- **Security:** GOST private keys never leave the CryptoPro container store; only
  the public client certificate is exported for stunnel. License, PIN, and key
  bundles are injected as build args / mounted resources, not committed.
- **Portability:** CryptoPro package selection is driven by `TARGETARCH` to
  support both amd64 and arm64 hosts.
