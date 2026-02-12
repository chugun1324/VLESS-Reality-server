#!/usr/bin/env bash
set -euo pipefail

SNI="www.cloudflare.com"
TAG="myvps-reality"
SERVER_IP="$(curl -4s https://api.ipify.org || hostname -I | awk '{print $1}')"

apt update
apt -y install curl unzip openssl ca-certificates ufw

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

systemctl stop nginx apache2 caddy 2>/dev/null || true
systemctl disable nginx apache2 caddy 2>/dev/null || true

UUID="$(cat /proc/sys/kernel/random/uuid)"
SID="$(openssl rand -hex 8)"
KEYS="$(/usr/local/bin/xray x25519 2>&1 || true)"

PRIV="$(printf '%s\n' "$KEYS" | awk -F': ' '/^PrivateKey:/{print $2} /^Private key:/{print $2}' | head -n1)"
PUB="$(printf '%s\n' "$KEYS" | awk -F': ' '/^PublicKey:/{print $2} /^Public key:/{print $2} /^Password:/{print $2}' | head -n1)"

[ -n "${PRIV:-}" ] && [ -n "${PUB:-}" ] || { echo "ERROR: key parse failed"; echo "$KEYS"; exit 1; }

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
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

ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable

LINK="vless://$UUID@$SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=tcp&headerType=none#$TAG"
echo "$LINK" | tee /root/vless.txt

echo "Saved: /root/vless.txt"
systemctl status xray --no-pager -l
