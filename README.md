# reference-postfix

A small, generic [Postfix](https://www.postfix.org/) container with overlay-config support and env-var templating. Built on Alpine, supervised by `tini` + `supervisord` (postfix + rsyslog co-process per [CONVENTIONS](https://github.com/rest-mail/conventions) §1), multi-arch (`linux/amd64` + `linux/arm64`), shipped under MIT.

Useful as a standalone SMTP server or as the SMTP layer of a larger mail stack. No assumptions about your database, hostnames, or trusted networks — supply them via env vars and/or mounted overlay config.

## Image

```
ghcr.io/rest-mail/reference-postfix:latest          # always newest
ghcr.io/rest-mail/reference-postfix:YYYY.MM.DD      # immutable calver tag
```

## Quick start (standalone)

```bash
docker run --rm -p 2525:25 \
  -e POSTFIX_HOSTNAME=mail.example.test \
  -e POSTFIX_DOMAIN=example.test \
  ghcr.io/rest-mail/reference-postfix:latest

# In another terminal:
nc 127.0.0.1 2525
# 220 mail.example.test ESMTP
EHLO test
QUIT
```

The default config has no users, no virtual domains backed by a real database, and no SASL — it'll start, accept connections, and reject mail until you mount overlay config.

## Overlay config

The entrypoint copies any files from `/etc/postfix-overlay/` on top of the rendered defaults at startup. Mount a directory:

```bash
docker run --rm -p 2525:25 \
  -e POSTFIX_HOSTNAME=mail.example.test \
  -e POSTFIX_DOMAIN=example.test \
  -v $(pwd)/my-postfix:/etc/postfix-overlay:ro \
  ghcr.io/rest-mail/reference-postfix:latest
```

Top-level files in the overlay (e.g. `main.cf`, `master.cf`, additional `.cf` lookup tables) land in `/etc/postfix/`. Subdirectories (e.g. `sql/`) are mirrored as-is — that's where pgsql lookup `.cf` files live (the baked-in `main.cf` references `/etc/postfix/sql/virtual_*.cf`).

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTFIX_HOSTNAME` | yes (recommended) | container `hostname -f` | Postfix `myhostname` and SMTP banner. |
| `POSTFIX_DOMAIN` | yes (recommended) | derived from `POSTFIX_HOSTNAME` | Postfix `mydomain` / `myorigin`. |
| `POSTFIX_MYNETWORKS` | no | `127.0.0.0/8 [::1]/128` | Trusted networks. Whitespace-separated CIDR list. |
| `POSTFIX_DB_HOST` | no | *(empty)* | Database host for pgsql lookup `.cf` files. No default to avoid leaking a host name. |
| `POSTFIX_DB_PORT` | no | `5432` | Database port. |
| `POSTFIX_DB_NAME` | no | *(empty)* | Database name. No default. |
| `POSTFIX_DB_USER` | no | *(empty)* | Database user. No default. |
| `POSTFIX_DB_PASSWORD` | no | *(empty)* | Database password. No default. |
| `POSTFIX_TLS_CERT` | no | `/certs/${POSTFIX_HOSTNAME}.crt` | Path to TLS certificate inside the container. |
| `POSTFIX_TLS_KEY` | no | `/certs/${POSTFIX_HOSTNAME}.key` | Path to TLS private key inside the container. |
| `POSTFIX_TLS_CA_PATH` | no | `/certs/ca.d` | Directory of CA certs to add to the system trust store. |
| `POSTFIX_CA_NAME` | no | `local` | Used as `${POSTFIX_CA_NAME}-ca.crt` when a single `/certs/ca.crt` file is present. |
| `POSTFIX_LOG_LEVEL` | no | `info` | `debug` enables `debug_peer_level=2`; `info`/`warn`/`error` are silent flags today. |
| `POSTFIX_OVERLAY_DIR` | no | `/etc/postfix-overlay` | Where to look for overlay config. |

The DB env vars are referenced inside your overlay's `sql/virtual_*.cf` files (typical pattern: `hosts = ${POSTFIX_DB_HOST}`, etc.); they're set in the container's environment for any other tooling you bake on top.

## Healthcheck

```bash
postconf mail_version >/dev/null 2>&1 && nc -z 127.0.0.1 25
```

A success means postfix's runtime config is parseable *and* the SMTP listener is up.

## Signals

- **SIGTERM** → graceful shutdown (handled by `tini` + supervisord).
- **SIGHUP** → reload — supervisord re-reads its config; for postfix-only reloads run `docker exec <container> postfix reload`. Postfix re-reads `main.cf` on reload, which is enough to pick up rotated TLS cert files mounted at the same paths.

## Ports

- `25` — SMTP (inbound)
- `465` — SMTPS (implicit TLS)
- `587` — Submission (authenticated outbound)

## TLS

Mount cert/key as files at `POSTFIX_TLS_CERT` / `POSTFIX_TLS_KEY`. To trust a custom CA, mount either:

- a single file at `/certs/ca.crt` — installed as `${POSTFIX_CA_NAME}-ca.crt`, or
- a directory at `POSTFIX_TLS_CA_PATH` (default `/certs/ca.d`) — every `*.crt` file there is added.

`update-ca-certificates` is run at startup.

## Layout

```
.
├── Dockerfile
├── entrypoint.sh
├── supervisord.conf
├── rsyslog.conf
├── defaults/
│   ├── main.cf.tmpl       # baked-in default; rendered by envsubst at startup
│   └── master.cf          # baked-in default; copied verbatim
├── .github/workflows/
│   └── build.yml          # multi-arch GHCR publish on push to master
└── tests/
    └── smoke.sh           # build + run + EHLO verify
```

## Building locally

```bash
docker build -t reference-postfix:dev .
docker run --rm -p 2525:25 \
  -e POSTFIX_HOSTNAME=mail.example.test \
  -e POSTFIX_DOMAIN=example.test \
  reference-postfix:dev
```

## License

MIT.

## See also

- [`rest-mail/conventions`](https://github.com/rest-mail/conventions) — the contract every `reference-*` image follows (overlay paths, env var naming, signal handling, calver tagging).
- [`rest-mail/reference-dovecot`](https://github.com/rest-mail/reference-dovecot) — paired IMAP/POP3/LMTP server.
- [`rest-mail/testbed`](https://github.com/rest-mail/testbed) — full local-internet sandbox composing this image with dnsmasq, certgen, dovecot, rspamd.
