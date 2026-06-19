# CryptoPro GOST Tunnel — Operations Reference

Detailed command reference, failure signatures, and fixes for the `rfm-tunel`
CryptoPro CSP GOST TLS tunnel. The source of truth is the project's own files:
`.docker/Dockerfile`, `.docker/stunnel.conf`, and `.docker/scripts/*`.

## CryptoPro CLI commands used in this project

| Command | Where | What it does |
|---------|-------|--------------|
| `cpconfig -license -set "$KEY"` | `setup_license` | Install license; without a key, falls back to trial |
| `cpconfig -license -view` | `setup_license` | Print current license status |
| `certmgr -inst -all -store uroot -file <f>` | `setup_root` | Import root CA into user root store (interactive `(o)OK`) |
| `certmgr -install -file CA.crt -store mCA -silent` | `entrypoint.sh` | Import intermediate CA |
| `certmgr -inst -store uMy -file <cert> -cont '\\.\HDIMAGE\<name>'` | `setup_my_certificate` | Install user cert linked to a key container |
| `certmgr -inst -file <cert> -cont "<container>" -silent` | `entrypoint.sh` | Install cert + private key into discovered container |
| `certmgr -export -dest /etc/stunnel/client.crt -container "<c>"` | `entrypoint.sh` | Export public client cert for stunnel |
| `csptest -keys -enum -verifyc -fqcn -un` | `entrypoint.sh` | Enumerate key containers; filter `HDIMAGE` to find the private-key container |
| `cryptcp -sign -thumbprint <hash> -nochain -hashAlg 1.2.643.7.1.1.2.2 -detached <in> <out>` | `sign` | Produce a detached GOST signature |

### Key container store layout

- Private-key containers live under `/var/opt/cprocsp/keys/root/<containerShortName>/`.
- A container directory holds: `header.key`, `masks.key`, `masks2.key`,
  `name.key`, `primary.key`, `primary2.key`. `setup_my_certificate:testprivk`
  validates all six are present before installing — replicate that check if you
  add new key handling.
- The **full** container name (needed to link a cert to its key) is stored in
  `name.key`; the script reads it with `tail -c+5 "$contShortName/name.key"`.

## stunnel.conf reference

```ini
pid=/var/opt/cprocsp/tmp/stunnel_cli.pid
foreground=yes

[https]
client = yes
accept = 8080                       # local plain port clients connect to
verify = 0                          # upstream cert verification (0 = off)
connect = /var/run/socat.sock       # hand off to socat, not the network
cert = /etc/stunnel/client.crt      # exported GOST client certificate
```

`entrypoint.sh` rewrites the `debug=` line from `STUNNEL_DEBUG_LEVEL` before
launch. `foreground=yes` is required so the container's main process is stunnel.

## socat bridge reference (`stunnel-socat.sh`)

Direct:
```
socat UNIX-LISTEN:/var/run/socat.sock,reuseaddr,fork TCP:${STUNNEL_HOST}
```
Through an HTTP proxy:
```
socat UNIX-LISTEN:/var/run/socat.sock,reuseaddr,fork \
  PROXY:${STUNNEL_HTTP_PROXY}:${STUNNEL_HOST},proxyport=${STUNNEL_HTTP_PROXY_PORT},proxyauth=${STUNNEL_HTTP_PROXY_CREDENTIALS}
```
- `reuseaddr,fork` lets the listener accept repeated connections.
- The script loops forever, removing a stale socket and restarting socat after
  a 1s sleep, so an upstream drop self-heals.

## Failure signatures and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Keys container not found` then exit 1 | `csptest ... grep HDIMAGE` returned nothing | Key container not imported / wrong store; check `resource/root.zip` contents and that `setup_my_certificate` ran during build |
| `Error on export client certificate` | `certmgr -export` produced no `/etc/stunnel/client.crt` | Cert not linked to a private key (no PrivateKey Link); verify cert+container pairing and `CERTIFICATE_PIN` |
| `No PrivateKey Link` warning at build | Cert installed without a matching container | Ensure the bundle contains both the cert and its key container; pass the correct PIN |
| stunnel handshake fails / resets | Wrong upstream, GOST cipher mismatch, or `verify` issue | Raise `STUNNEL_DEBUG_LEVEL` (e.g. `7`), confirm `STUNNEL_HOST`, confirm the upstream speaks GOST TLS |
| Connection hangs with proxy set | Proxy host/port/auth wrong | Check `STUNNEL_HTTP_PROXY*`; test the `PROXY:` socat line manually |
| `containerHash is not specified` from `sign` | `containerHash` left empty in `sign` | Bake the actual thumbprint into the script at image build time |
| `cryptcp -sign` non-zero exit | Wrong PIN, wrong thumbprint, or non-GOST `-hashAlg` | Verify PIN arg, thumbprint matches the installed cert, OID is `1.2.643.7.1.1.2.2` |
| Garbled Cyrillic in logs | cp1251 output shown as UTF-8 | Pipe through `iconv -fcp1251 -tutf-8` |

## Debugging tips

- **Raise stunnel verbosity:** set `STUNNEL_DEBUG_LEVEL` to `7` to see the full
  GOST handshake; it is patched into `stunnel.conf` at start.
- **List installed certs/containers:** `certmgr -list` and
  `csptest -keys -enum -verifyc -fqcn -un` inside the running container.
- **Test the socket path independently:** confirm `/var/run/socat.sock` exists
  and socat is alive (`ps`), then connect a client to `:8080`.
- **Verify a signature locally:** `cryptcp -verify -detached <file> <file.sig>`.

## Build-time gotchas

- `der2xer`, `certmgr`, `cpverify`, `cryptcp`, `csptest`, `cpconfig` are
  symlinked from `/opt/cprocsp/{bin,sbin}/$ARCH/` into `/bin` during build.
  `$ARCH` is resolved from `ls /opt/cprocsp/bin/`.
- The `cprocsp-pki-phpcades` package provides the PHP CAdES bindings; keep its
  version (`2.0.15000-1`) aligned with the CSP packages.
- The root `Dockerfile` + `app.sh` (MarkItDown, `python:3.11-slim`) are a
  **separate** documentation-conversion image — do not mix it into the tunnel
  build context.
