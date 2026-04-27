#!/usr/bin/env bash
set -euo pipefail

ROUTER_HOST="${ROUTER_HOST:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PASS="${ROUTER_PASS:-DTIC2025B_jp}"

echo "Deshabilitando AP WiFi (wifinet2)..."
sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
  "$ROUTER_USER@$ROUTER_HOST" \
  "uci set wireless.wifinet2.disabled='1'; uci commit wireless; wifi reload &"

echo "AP WiFi deshabilitado."
