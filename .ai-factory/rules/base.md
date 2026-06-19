# Project Base Rules

> Auto-detected conventions from codebase analysis. Edit as needed.

This project is shell/Docker infrastructure (a CryptoPro GOST TLS tunnel). It has
no application source code in a general-purpose language — conventions below are
derived from the Bash scripts, the `expect` script, and the Dockerfiles.

## Naming Conventions

- **Script files:** `snake_case` for setup/helper scripts (`setup_root`,
  `setup_my_certificate`, `setup_license`, `sign`); `kebab-case` with a `.sh`
  suffix for runnable multi-word scripts (`stunnel-socat.sh`, `entrypoint.sh`).
- **Bash variables:** `camelCase` for locals (`containerName`, `socatParameters`,
  `contShortName`, `contFullName`, `signResult`, `certFileName`).
- **Environment variables:** `UPPER_SNAKE_CASE` (`STUNNEL_HOST`, `STUNNEL_HTTP_PROXY`,
  `STUNNEL_DEBUG_LEVEL`, `CERTIFICATE_PIN`, `CRYPTO_PRO_LICENSE`).
- **Bash functions:** lowercase / `camelCase` (`testprivk`, `findContFullName`,
  `assert`, `info`, `ok`, `warning`, `error`).
- **Docker build args:** `UPPER_SNAKE_CASE` (`PHP_VERSION`, `TARGETARCH`,
  `CERTIFICATE_PIN`, `CRYPTO_PRO_LICENSE`).

## Module Structure

- `.docker/` — Docker build context for the tunnel: `Dockerfile`, `stunnel.conf`,
  CryptoPro CSP packages (`*.deb`, `*.tgz`).
- `.docker/scripts/` — container init and runtime scripts: `entrypoint.sh`,
  `stunnel-socat.sh`, `setup_*`, `sign`.
- `.docker/scripts/lib/` — shared Bash helpers sourced by scripts: `colors.sh`
  (ANSI color vars), `functions.sh` (`info`/`ok`/`warning`/`error`/`assert`).
- `resource/` — certificate and key material (`root.cer`, `root.zip`); contents
  are gitignored and supplied at build/run time.
- Project root `Dockerfile` + `app.sh` — a separate MarkItDown helper image used
  to convert API documentation (`api-rfm.docx` → Markdown). Keep it independent
  of the tunnel build.

## Error Handling

- Append `|| exit 1` to critical commands whose failure must abort the script.
- Guard required inputs explicitly and exit non-zero with a message:
  `if [[ -z "$var" ]]; then echo "..."; exit 1; fi`.
- Check `$?` after commands that may fail and propagate the original exit code
  (e.g. `exit $signResult`).
- Use the `assert` helper from `lib/functions.sh` for substring/expectation checks.
- Validate presence of all expected key files before installing a key container
  (see `testprivk` in `setup_my_certificate`).

## Logging

- Use `echo` / `echo -e` for output; for colored status messages source
  `lib/functions.sh` and use `info` (blue), `ok` (green), `warning` (yellow),
  `error` (red).
- Code comments are written in **Russian**; keep that convention when editing
  existing scripts.
- CryptoPro tools emit cp1251 output — pipe through `iconv -fcp1251 -tutf-8`
  before displaying names that may contain Cyrillic.
