# Changelog

Calver-tagged. Newest on top.

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
