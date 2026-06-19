# AGENTS.md

> Structural map for AI agents and new developers. Keep it factual and update it
> when the project structure changes significantly. Detailed specification lives
> in `.ai-factory/DESCRIPTION.md` — reference it rather than duplicating it here.

## Project Overview

`rfm-tunel` is a Dockerized CryptoPro CSP **GOST TLS tunnel**: it exposes a plain
local port and proxies traffic over a GOST-secured session (stunnel + socat) to an
upstream host, and performs detached GOST document signing. A separate MarkItDown
image converts API documentation to Markdown.

## Tech Stack

- **Programming language:** Bash + Expect (scripts); PHP 8.3 runtime for phpcades
- **Framework:** None (infrastructure / shell tooling)
- **Database:** None
- **ORM:** None
- **Crypto / runtime:** CryptoPro CSP, cprocsp-pki-phpcades (CAdES), stunnel, socat
- **Packaging:** Docker (Debian bookworm-slim; python:3.11-slim for MarkItDown)

## Project Structure

```
rfm-tunel/
├── .docker/                       # Docker build context for the GOST tunnel
│   ├── Dockerfile                 # CryptoPro CSP + stunnel + socat image (Debian)
│   ├── stunnel.conf               # stunnel client config (:8080 -> unix socket)
│   ├── cprocsp-pki-phpcades_*.deb # CryptoPro CAdES (PHP) package
│   ├── linux-arm64_deb.tgz        # CryptoPro CSP packages (arch-specific)
│   └── scripts/                   # Container init & runtime scripts
│       ├── entrypoint.sh          # CSP setup -> start socat -> exec stunnel
│       ├── stunnel-socat.sh       # socat unix-socket <-> upstream bridge (restart loop)
│       ├── setup_root             # expect: import root CA into uroot store
│       ├── setup_my_certificate   # install user cert + key container, link them
│       ├── setup_license          # install/view CryptoPro license
│       ├── sign                   # detached GOST signing via cryptcp
│       └── lib/                   # shared bash helpers (colors.sh, functions.sh)
├── resource/                      # certs/keys (gitignored): root.cer, root.zip
├── Dockerfile                     # SEPARATE MarkItDown image (docx -> markdown)
├── app.sh                         # run the MarkItDown converter
├── .mcp.json                      # MCP server config (filesystem)
├── .ai-factory/                   # AI Factory context (config, description, rules)
└── .claude/                       # Claude Code skills & agents
```

## Key Entry Points

| File | Purpose |
|------|---------|
| `.docker/scripts/entrypoint.sh` | Container entrypoint: configures CSP, imports/exports certs, launches socat + stunnel |
| `.docker/Dockerfile` | Builds the GOST tunnel image (CryptoPro CSP, stunnel, socat, phpcades) |
| `.docker/stunnel.conf` | stunnel client config: accept `:8080` -> connect `/var/run/socat.sock` |
| `.docker/scripts/stunnel-socat.sh` | socat bridge from the Unix socket to `STUNNEL_HOST` (with optional proxy) |
| `.docker/scripts/sign` | Detached GOST document signing (`cryptcp`, OID `1.2.643.7.1.1.2.2`) |
| `Dockerfile` + `app.sh` | Separate MarkItDown helper: convert `api-rfm.docx` to Markdown |

## Documentation

| Document | Path | Description |
|----------|------|-------------|
| README | `README.md` | Project intro (`gost-stunnel-CSP`) — GOST tunnel for state services (ГИС ЖКХ, Росфинмониторинг). Note: its structure section is partly stale vs. the current `.docker/` layout |
| Project specification | `.ai-factory/DESCRIPTION.md` | Stack, features, architecture notes, NFRs |

## AI Context Files

| File | Purpose |
|------|---------|
| AGENTS.md | This structural map of the project |
| .ai-factory/DESCRIPTION.md | Detailed project specification |
| .ai-factory/ARCHITECTURE.md | Architecture pattern, structure, dependency rules |
| .ai-factory/rules/base.md | Auto-detected code conventions (naming, errors, logging) |
| .ai-factory/config.yaml | AI Factory configuration (language, paths, git) |

## Agent Rules

- Decompose chained shell commands into discrete steps instead of joining them
  with `&&`, so each step's success/failure is visible and the working directory
  does not silently drift.
  - Incorrect (combined): `cd .docker/scripts && ./setup_license "$KEY"`
  - Correct (decomposed): run `./setup_license "$KEY"` from `.docker/scripts`
    using an absolute path, or change directory in its own step first.
- This project is **not** a git repository (`git.enabled: false` in
  `.ai-factory/config.yaml`); do not assume a base branch or run branch/merge
  operations.
- Never export, copy out, or log GOST private-key material; only the public
  client certificate leaves the CryptoPro store. See the `cryptopro-gost-tunnel`
  skill for the full operating rules.
