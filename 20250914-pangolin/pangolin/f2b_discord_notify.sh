#!/usr/bin/env bash

set -euo pipefail

JAIL="$1"; IP="$2"; BANTIME="$3"; FAILS="$4"; WEBHOOK="$5"; MATCHES="$6"

bell="🔒"

if [ "$JAIL" == "traefik-service" ]; then
    bell="🚨🚨🚨"
elif [ "$JAIL" == "traefik-sni" ]; then
    bell="⛔️"
elif [ "$JAIL" == "pangolin-auth" ]; then
    bell="🕷️"
fi

#curl -sS -X POST "$WEBHOOK" \
#  -H "Content-Type: application/json" \
#  -d '{"username":"Fail2Ban","content":"test"}'

MARKDOWN=$(cat <<EOF
$bell rnvps - **[$JAIL]** **BANNED** IP \`$IP\` for $BANTIME seconds after **$FAILS** failure(s).
Unban: \`fail2ban-client unban $IP\`
Matches:
\`\`\`
$MATCHES
\`\`\`
EOF
)

#echo MARKDOWN
#echo "$MARKDOWN"

curl -sS -X POST "$WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg user "Fail2Ban" --arg content "$MARKDOWN" '{username:$user, content:$content}')"

exit 0
