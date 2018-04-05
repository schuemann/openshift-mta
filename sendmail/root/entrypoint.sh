#!/bin/bash

set -e
if [ ! -z "${ENTRYPOINT_DEBUG}" ]; then
    set -x
fi

export SENDMAIL_FEATURE_no_default_msa=${SENDMAIL_FEATURE_no_default_msa:-true}
export SENDMAIL_FEATURE_nouucp=${SENDMAIL_FEATURE_nouucp:-nospecial}

#if [ -f /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
#    echo "Kubernetes environment detected ..."
#    export SENDMAIL_DEFINE_confDOMAIN_NAME=${SENDMAIL_DEFINE_confDOMAIN_NAME:-"${HOSTNAME}.$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace).svc.cluster.local"}
#else
#    export SENDMAIL_DEFINE_confDOMAIN_NAME=${SENDMAIL_DEFINE_confDOMAIN_NAME:-"${HOSTNAME}.docker.local"}
#fi

export SENDMAIL_DEFINE_confLOG_LEVEL=${SENDMAIL_DEFINE_confLOG_LEVEL:-9}
export SENDMAIL_DEFINE_confCACERT_PATH=${SENDMAIL_DEFINE_confCACERT_PATH:-/etc/pki/tls/certs}
export SENDMAIL_DEFINE_confPID_FILE=${SENDMAIL_DEFINE_confPID_FILE:-/tmp/sendmail.pid}
export SENDMAIL_DEFINE_confTRUSTED_USER=${SENDMAIL_DEFINE_confTRUSTED_USER:-openshift}
export SENDMAIL_DEFINE_STATUS_FILE=${SENDMAIL_DEFINE_STATUS_FILE:-/var/spool/mqueue/statistics}
export SENDMAIL_DEFINE_confDONT_BLAME_SENDMAIL=${SENDMAIL_DEFINE_confDONT_BLAME_SENDMAIL:-"\`GroupReadableSASLDBFile,GroupReadableKeyFile,GroupWritableDirPathSafe'"}

# Add authentication for relay hosts
if [ ! -z "${SENDMAIL_DEFINE_SMART_HOST}" ] && [ ! -z "${SENDMAIL_RELAYHOST_USER}" ] && [ ! -z "${SENDMAIL_RELAYHOST_PASSWORD}" ]; then
    echo "Setting AuthInfo for relayhost '${SENDMAIL_DEFINE_SMART_HOST}'"
    export SENDMAIL_RELAYHOST_AUTH=${SENDMAIL_RELAYHOST_AUTH:-PLAIN}
    export SENDMAIL_FEATURE_authinfo=true
    printf 'AuthInfo:%s "U:%s" "P:%s" "M:%s"' "${SENDMAIL_DEFINE_SMART_HOST}" "${SENDMAIL_RELAYHOST_USER}" "${SENDMAIL_RELAYHOST_PASSWORD}" "${SENDMAIL_RELAYHOST_AUTH}" >> /etc/mail/authinfo
fi

# Override sendmails access files.
if [ ! -z "${SENDMAIL_ACCESS}" ]; then
    echo -e "${SENDMAIL_ACCESS}" > /etc/mail/access
fi

# Disable check for lookup sender IP. Require for kubernetes based environments
if [ ! -z "${SENDMAIL_DISABLE_SENDER_RDNS}" ] && [ "${SENDMAIL_DISABLE_SENDER_RDNS}" == "true" ]; then
    echo "Disable rDNS for senders..."
    cp /usr/share/sendmail-cf/m4/proto.m4 /tmp
    patch -s /tmp/proto.m4 < /usr/local/src/remove-sender-lookup-check.patch
    cp /tmp/proto.m4 /usr/share/sendmail-cf/m4/proto.m4
    rm /tmp/proto.m4
fi

# Listen on specific address
if [ ! -z "${SENDMAIL_LISTEN}" ]; then
    echo "DAEMON_OPTIONS(\`Port=smtp, Name=MTA, Addr=${SENDMAIL_LISTEN}')dnl" >> /etc/mail/sendmail.mc
else
    echo "DAEMON_OPTIONS(\`Port=smtp, Name=MTA')dnl" >> /etc/mail/sendmail.mc
fi

# Drop bounces
if [ ! -z "${SENDMAIL_DROP_BOUNCE_MAILS}" ] && [ "${SENDMAIL_DROP_BOUNCE_MAILS}" == "true" ]; then
    echo '| /dev/null' > /tmp/.forward
    export SENDMAIL_DEFINE_LUSER_RELAY=local:openshift
fi

# Enable debug
if [ ! -z "${SENDMAIL_DEBUG}" ] && [ "${SENDMAIL_DEBUG}" == "true" ]; then
    set -- "$@" "-d" "-X" "/proc/fd/self/1"
fi

# Force receiver address
if [ ! -z "${SENDMAIL_FORCE_SENDER_ADDRESS}" ]; then
    export _LOCAL_PART=$(echo "${SENDMAIL_FORCE_SENDER_ADDRESS}" | cut -d@ -f1)
    export _DOMAIN_PART=$(echo "${SENDMAIL_FORCE_SENDER_ADDRESS}" | cut -d@ -f2)

    # http://www.harker.com/sendmail/rules-overview.html
    export SENDMAIL_RAW_APPEND=$(cat <<EOF
${SENDMAIL_RAW_APPEND}
LOCAL_RULE_1
R \$+@\$+\t\$@ ${_LOCAL_PART} < @ ${_DOMAIN_PART}. >
EOF
)
    unset _LOCAL_PART
    unset _DOMAIN_PART
fi

# Force receiver address
if [ ! -z "${SENDMAIL_FORCE_RECEIVER_ADDRESS}" ]; then
    export _LOCAL_PART=$(echo "${SENDMAIL_FORCE_RECEIVER_ADDRESS}" | cut -d@ -f1)
    export _DOMAIN_PART=$(echo "${SENDMAIL_FORCE_RECEIVER_ADDRESS}" | cut -d@ -f2)

    # https://serverfault.com/questions/356160/configure-sendmail-to-only-send-to-local-domain
    export SENDMAIL_RAW_APPEND=$(cat <<EOF
${SENDMAIL_RAW_APPEND}
LOCAL_RULE_0
R\$* < \$*. > \$*\t\$: ${_LOCAL_PART} < @ ${_DOMAIN_PART}. > \$3
EOF
)
    unset _LOCAL_PART
    unset _DOMAIN_PART
fi

if [ ! -z "${SENDMAIL_RAW_PREPEND}" ]; then
    sed -i "s/MAILER(smtp)dnl/FEATURE\(\`${SENDMAIL_RAW_PREPEND}'\)dnl\nMAILER(smtp)dnl/" /etc/mail/sendmail.mc
fi

if [ ! -z "${SENDMAIL_RAW_APPEND}" ]; then
    _RAW_APPEND="${SENDMAIL_RAW_APPEND}"
fi

# https://stackoverflow.com/a/25765360
# Configure sendmail from environments
while IFS='=' read -r name value ; do
    if [[ $name == 'SENDMAIL_'* ]]; then
        if [[ $name == 'SENDMAIL_DEFINE_'* ]]; then
            sed -i "s/MAILER(smtp)dnl/define\(\`${name/SENDMAIL_DEFINE_/}', \`${!name//\//\\/}')dnl\nMAILER(smtp)dnl/" /etc/mail/sendmail.mc
        elif [[ $name == 'SENDMAIL_FEATURE_'* ]]; then
            if [[ "${!name}" == "true" ]]; then
                sed -i "s/MAILER(smtp)dnl/FEATURE\(\`${name/SENDMAIL_FEATURE_/}'\)dnl\nMAILER(smtp)dnl/" /etc/mail/sendmail.mc
            else
                sed -i "s/MAILER(smtp)dnl/FEATURE\(\`${name/SENDMAIL_FEATURE_/}'\, \`${!name//\//\\/}')dnl\nMAILER(smtp)dnl/" /etc/mail/sendmail.mc
            fi
        fi
        unset ${name}
    fi
done < <(env)

echo "openshift:x:$(id -u):$(id -g)::/tmp:/sbin/nologin" >> /etc/passwd

if [ ! -z "${_RAW_APPEND}" ]; then
    echo -e "${_RAW_APPEND}" >> /etc/mail/sendmail.mc
    unset _RAW_APPEND
fi

# prevent error:
# makemap: error opening type hash map *.db: File changed after open
rm -f /etc/mail/*.db
/etc/mail/make

export LIBLOGFAF_SENDTO=${LIBLOGFAF_SENDTO:-/tmp/log}

# Setup log environment
if [[ "${LIBLOGFAF_SENDTO}" == '/tmp/'* ]]; then
    mkfifo ${LIBLOGFAF_SENDTO}
    tail --pid=1 -f ${LIBLOGFAF_SENDTO} &
fi

if [ ! -z "${ENTRYPOINT_DEBUG}" ]; then
    cat /etc/mail/sendmail.mc
fi

LD_PRELOAD="liblogfaf.so" exec "$@"