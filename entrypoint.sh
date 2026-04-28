#!/bin/sh
# reference-postfix entrypoint
#
# 1. Set sensible defaults for any unset env vars (no restmail-specifics).
# 2. Render /etc/postfix-defaults/main.cf.tmpl -> /etc/postfix/main.cf via envsubst.
# 3. Copy the baked-in master.cf into place.
# 4. Merge files from /etc/postfix-overlay/ on top (overlay wins).
# 5. Install any CA certs found in $POSTFIX_TLS_CA_PATH into the system trust store.
# 6. exec the supplied command (default: supervisord).
set -eu

# --- Identity ----------------------------------------------------------------
: "${POSTFIX_HOSTNAME:=$(hostname -f 2>/dev/null || hostname)}"
: "${POSTFIX_DOMAIN:=${POSTFIX_HOSTNAME#*.}}"
: "${POSTFIX_MYNETWORKS:=127.0.0.0/8 [::1]/128}"

# --- Database (no restmail-specific defaults; require explicit values) -------
: "${POSTFIX_DB_HOST:=}"
: "${POSTFIX_DB_PORT:=5432}"
: "${POSTFIX_DB_NAME:=}"
: "${POSTFIX_DB_USER:=}"
: "${POSTFIX_DB_PASSWORD:=}"

# --- TLS ---------------------------------------------------------------------
: "${POSTFIX_TLS_CERT:=/certs/${POSTFIX_HOSTNAME}.crt}"
: "${POSTFIX_TLS_KEY:=/certs/${POSTFIX_HOSTNAME}.key}"
: "${POSTFIX_TLS_CA_PATH:=/certs/ca.d}"
: "${POSTFIX_CA_NAME:=local}"

# --- Logging -----------------------------------------------------------------
: "${POSTFIX_LOG_LEVEL:=info}"

export POSTFIX_HOSTNAME POSTFIX_DOMAIN POSTFIX_MYNETWORKS \
       POSTFIX_DB_HOST POSTFIX_DB_PORT POSTFIX_DB_NAME POSTFIX_DB_USER POSTFIX_DB_PASSWORD \
       POSTFIX_TLS_CERT POSTFIX_TLS_KEY POSTFIX_TLS_CA_PATH POSTFIX_CA_NAME \
       POSTFIX_LOG_LEVEL

echo "reference-postfix: rendering config for ${POSTFIX_HOSTNAME} (${POSTFIX_DOMAIN})"

# --- Render baked-in defaults -----------------------------------------------
mkdir -p /etc/postfix
envsubst </etc/postfix-defaults/main.cf.tmpl >/etc/postfix/main.cf
cp /etc/postfix-defaults/master.cf /etc/postfix/master.cf

# --- Merge overlay (files in /etc/postfix-overlay/ win over baked-in) -------
OVERLAY_DIR="${POSTFIX_OVERLAY_DIR:-/etc/postfix-overlay}"
if [ -d "$OVERLAY_DIR" ]; then
    # Copy any top-level files (main.cf, master.cf, *.cf) directly into /etc/postfix/.
    # Subdirectories (e.g. sql/) are mirrored as-is.
    find "$OVERLAY_DIR" -mindepth 1 -maxdepth 1 -type f -exec cp -f {} /etc/postfix/ \;
    find "$OVERLAY_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r d; do
        name=$(basename "$d")
        mkdir -p "/etc/postfix/$name"
        cp -rf "$d"/. "/etc/postfix/$name/"
    done
fi

# --- Lock down SQL lookup files (they may contain DB passwords) -------------
if [ -d /etc/postfix/sql ]; then
    chmod 640 /etc/postfix/sql/*.cf 2>/dev/null || true
    chown root:postfix /etc/postfix/sql/*.cf 2>/dev/null || true
fi

# --- Install CA certs from $POSTFIX_TLS_CA_PATH -----------------------------
# Single-file legacy mount point: /certs/ca.crt — installed as ${POSTFIX_CA_NAME}-ca.crt.
if [ -f /certs/ca.crt ]; then
    cp /certs/ca.crt "/usr/local/share/ca-certificates/${POSTFIX_CA_NAME}-ca.crt"
fi
# Directory mount point for one or more CAs.
if [ -d "$POSTFIX_TLS_CA_PATH" ]; then
    for ca in "$POSTFIX_TLS_CA_PATH"/*.crt; do
        [ -f "$ca" ] || continue
        cp "$ca" "/usr/local/share/ca-certificates/$(basename "$ca")"
    done
fi
update-ca-certificates 2>/dev/null || true

# --- Postfix chroot fixups ---------------------------------------------------
mkdir -p /var/spool/postfix/etc
cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf 2>/dev/null || true
cp /etc/services    /var/spool/postfix/etc/services    2>/dev/null || true

# --- Log level ---------------------------------------------------------------
case "$POSTFIX_LOG_LEVEL" in
    debug) postconf -e debug_peer_level=2 ;;
    info|warn|error) : ;;
esac

# Ensure postfix internal state is consistent with the rendered config.
postfix check 2>&1 || true
newaliases 2>/dev/null || true

echo "reference-postfix: ready"
exec "$@"
