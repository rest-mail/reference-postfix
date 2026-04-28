FROM alpine:3.20

# postfix + rsyslog (legitimate co-process per CONVENTIONS §1: rsyslog acts as
# a transparent log relay so postfix's syslog output reaches stdout) + tini for
# proper SIGCHLD reaping in this multi-process container.
RUN apk add --no-cache \
        postfix \
        postfix-pgsql \
        rsyslog \
        tini \
        ca-certificates \
        cyrus-sasl \
        cyrus-sasl-login \
        cyrus-sasl-crammd5 \
        gettext \
        netcat-openbsd \
    && mkdir -p /etc/postfix-overlay /certs /var/spool/postfix/etc

COPY defaults/main.cf.tmpl /etc/postfix-defaults/main.cf.tmpl
COPY defaults/master.cf    /etc/postfix-defaults/master.cf
COPY rsyslog.conf          /etc/rsyslog.d/postfix.conf
COPY supervisord.conf      /etc/supervisord.conf
COPY entrypoint.sh         /usr/local/bin/entrypoint.sh

RUN apk add --no-cache supervisor && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 25 465 587

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD postconf mail_version >/dev/null 2>&1 && nc -z 127.0.0.1 25 || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]
