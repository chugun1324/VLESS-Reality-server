#!/usr/bin/env bash
set -euo pipefail

SNI="www.microsoft.com"
TAG="myvps-reality-xhttp"
SERVER_IP="31.192.235.159"

apt update
apt -y install curl unzip openssl ca-certificates ufw

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

UUID="$(cat /proc/sys/kernel/random/uuid)"
SID="$(openssl rand -hex 8)"
KEYS="$(/usr/local/bin/xray x25519 2>&1)"

PRIV="$(printf '%s\n' "$KEYS" | awk -F': ' '/^PrivateKey:/{print $2} /^Private key:/{print $2}' | head -n1)"
PUB="$(printf '%s\n' "$KEYS" | awk -F': ' '/^PublicKey:/{print $2} /^Public key:/{print $2} /^Password:/{print $2}' | head -n1)"

[ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "Key parse failed"; echo "$KEYS"; exit 1; }

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "xhttpSettings": { "mode": "auto" },
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$SNI:443",
        "serverNames": ["$SNI"],
        "privateKey": "$PRIV",
        "shortIds": ["$SID"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
  }],
  "outbounds": [
    { "protocol": "freedom" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF

/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
systemctl enable xray
systemctl restart xray
systemctl status xray --no-pager -l

ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable

LINK="vless://$UUID@$SERVER_IP:443?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=xhttp#$TAG"
echo "$LINK" | tee /root/vless.txt
echo "Saved: /root/vless.txt"
