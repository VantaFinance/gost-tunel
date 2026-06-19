# Architecture

> Generated during `/aif` setup. The `aif-architecture` skill is not installed in
> this project, so this document was authored directly from codebase analysis.
> Update it when the runtime topology, build pipeline, or script boundaries change.

## Architecture Pattern

This is **infrastructure / containerized tooling**, not a layered application.
The "architecture" is the **runtime topology** of cooperating processes inside a
single Docker container, plus the **build pipeline** that provisions CryptoPro CSP
and certificates. Design it as a small set of single-responsibility shell modules
orchestrated by one entrypoint.

Two independent deliverables live in this repo:

1. **GOST TLS tunnel** (`.docker/`) — the primary system.
2. **MarkItDown converter** (root `Dockerfile` + `app.sh`) — an unrelated helper
   image for converting documentation. Keep these build contexts separate.

## Runtime Topology (tunnel)

```
                     ┌─────────────────────────────────────────────┐
   HTTP client ─────▶│ stunnel  (:8080, GOST-TLS client)            │
                     │   cert = /etc/stunnel/client.crt             │
                     │   connect = unix:/var/run/socat.sock         │
                     └───────────────┬─────────────────────────────┘
                                     ▼
                     ┌─────────────────────────────────────────────┐
                     │ socat  (UNIX-LISTEN, fork, restart loop)     │
                     │   TCP:${STUNNEL_HOST}                        │
                     │   or PROXY:${STUNNEL_HTTP_PROXY}:...          │
                     └───────────────┬─────────────────────────────┘
                                     ▼
                          upstream GOST endpoint
```

- **stunnel** owns GOST-TLS termination and certificate presentation. It is the
  container's foreground process (`exec`), so its lifecycle is the container's.
- **socat** owns the network hop (direct or proxied) and self-heals via a restart
  loop. It runs in the background and communicates over a Unix domain socket.
- **CryptoPro CSP** owns all key material. Private keys live only in its store
  (`HDIMAGE` under `/var/opt/cprocsp/keys/root/`).

## Build Pipeline (`.docker/Dockerfile`)

1. Select arch-specific CryptoPro packages via `linux-${TARGETARCH}_deb`.
2. Install CSP, CAdES (`cprocsp-pki-phpcades`), and dev libs; symlink CLI tools
   (`certmgr`, `csptest`, `cryptcp`, `cpconfig`, …) into `/bin`.
3. Apply license (`setup_license`), import root cert (`setup_root`), install the
   user certificate + key container (`setup_my_certificate`).
4. Copy runtime scripts; set entrypoint to `entrypoint.sh`, default CMD launches
   stunnel.

## Module Boundaries (`.docker/scripts/`)

| Module | Responsibility | May depend on |
|--------|----------------|---------------|
| `entrypoint.sh` | Orchestration: CSP config → cert export → start socat → exec stunnel | all scripts, lib |
| `stunnel-socat.sh` | Network bridge (socat) with optional proxy + restart loop | env vars only |
| `setup_root` | Import root CA (Expect-driven `certmgr`) | — |
| `setup_my_certificate` | Install + link user cert and key container | `lib/` |
| `setup_license` | Install / view CryptoPro license | — |
| `sign` | Detached GOST signing (`cryptcp`) | baked-in `containerHash` |
| `lib/colors.sh`, `lib/functions.sh` | Shared color vars + `info`/`ok`/`warning`/`error`/`assert` | — |

## Dependency Rules

1. **One direction of dependency:** `entrypoint.sh` and `setup_*` may source
   `lib/`; `lib/` must depend on nothing in this project.
2. **Configuration flows through environment variables**, never hardcoded:
   `STUNNEL_HOST`, `STUNNEL_HTTP_PROXY*`, `STUNNEL_DEBUG_LEVEL` (runtime);
   `CERTIFICATE_PIN`, `CRYPTO_PRO_LICENSE`, `TARGETARCH` (build).
3. **Secrets stay out of the image layers and VCS:** key bundles
   (`resource/root.zip`, `resource/root.cer`), PIN, and license are injected at
   build/run time.
4. **stunnel never talks to the network directly** — it always hands off to socat
   via the Unix socket. This keeps proxy logic isolated in one module.
5. **GOST private keys never leave the CSP store** — export only the public client
   certificate.
6. **The MarkItDown image is fully decoupled** from the tunnel; no shared scripts
   or layers.

## Conventions & Error Handling

- Fail fast: abort (`exit 1`) when a key container, certificate, or required key
  file is missing.
- Validate inputs before acting (e.g. `testprivk` checks all six `*.key` files
  before installing a container).
- Log with the shared color helpers; CryptoPro output is cp1251 — convert with
  `iconv -fcp1251 -tutf-8` before display.
- Full naming/structure conventions: `.ai-factory/rules/base.md`.
- Detailed operating/debugging reference: the `cryptopro-gost-tunnel` skill
  (`.claude/skills/cryptopro-gost-tunnel/`).

## Example: adding a new init step safely

```bash
# In a setup script, source shared helpers and fail fast.
cd "$(dirname "$0")"
source lib/functions.sh

readonly target="/etc/stunnel/extra.crt"

if [[ ! -f "$target" ]]; then
  error "Required file missing: $target"
  exit 1
fi
ok "Extra certificate present"
```
