# Changelog

Calver-tagged. Newest on top.

## Unreleased

### Added
- **DB-driven virtual lookup maps are now baked in.** `defaults/sql/virtual_{domains,mailboxes,aliases}.cf.tmpl`
  render from `POSTFIX_DB_*` at startup (symmetric with reference-dovecot's
  `dovecot-sql.conf.ext`) — the query shape is the schema contract, the connection
  comes from env. Instances no longer ship an `sql/` overlay, just DB env. Rendering
  is skipped when `POSTFIX_DB_HOST` is unset (an empty `dbname` is fatal), so the
  image stays standalone-runnable with no database.
- **Env-gated mail-flow wiring** for the full Postfix+Dovecot(+rspamd) topology,
  all opt-in with standalone-safe defaults:
  - `POSTFIX_VIRTUAL_TRANSPORT` (default `virtual`) — set `lmtp:inet:<dovecot>:24` to hand delivery to Dovecot LMTP.
  - `POSTFIX_SASL_PATH` / `POSTFIX_SASL_TYPE` (default `dovecot`) — submission/smtps auth backend, wired via `postconf` only when a path is set (an empty `smtpd_sasl_path` is fatal).
  - `POSTFIX_MILTERS` — e.g. `inet:<rspamd>:11332`; sets `smtpd_milters`/`non_smtpd_milters` + `milter_default_action=accept` only when provided.

### Notes
- Fully backward-compatible: with none of the new vars set the image renders and
  runs exactly as before (verified — standalone still answers EHLO on :25, no fatals).
- Verified end-to-end in the testbed: SMTP receipt → SQL recipient match → LMTP to
  Dovecot → maildir → IMAP retrieval, with rspamd milter filtering.

## 2026.04.28

- Initial release.
- Alpine 3.20 + postfix + postfix-pgsql + rsyslog, supervised by tini + supervisord.
- rsyslog runs as a transparent log relay forwarding `mail.*` to stdout (legitimate
  co-process per CONVENTIONS §1).
- Overlay config via `/etc/postfix-overlay/` — files override baked-in defaults at startup.
- Generic env vars: `POSTFIX_HOSTNAME`, `POSTFIX_DOMAIN`, `POSTFIX_MYNETWORKS`,
  `POSTFIX_DB_*`, `POSTFIX_TLS_CERT/KEY/CA_PATH`, `POSTFIX_CA_NAME`, `POSTFIX_LOG_LEVEL`.
- No restmail-specific defaults: `POSTFIX_MYNETWORKS` defaults to `127.0.0.0/8 [::1]/128`,
  DB env vars have no defaults, CA file installs as `${POSTFIX_CA_NAME:-local}-ca.crt`.
- Healthcheck: `postconf mail_version` + `nc -z 127.0.0.1 25`.
- Multi-arch publish: linux/amd64, linux/arm64.
