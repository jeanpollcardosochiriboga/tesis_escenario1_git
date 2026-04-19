#!/usr/bin/env bash
set -euo pipefail

# Parametros de acceso al router OpenWrt.
ROUTER_HOST="${ROUTER_HOST:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PASS="${ROUTER_PASS:-DTIC2025B_jp}"
SSH_OPTS="-o ConnectTimeout=8 -o StrictHostKeyChecking=no"

# Verifica conectividad SSH antes de intentar restaurar archivos.
if ! sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "echo ESC1_ROLLBACK_CHECK" >/dev/null 2>&1; then
  CURRENT_IPS="$(hostname -I 2>/dev/null | xargs || true)"
  CURRENT_GW="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  echo "No hay acceso SSH al router objetivo: $ROUTER_HOST" >&2
  echo "IPs locales detectadas: ${CURRENT_IPS:-N/A}" >&2
  echo "Gateway actual detectado: ${CURRENT_GW:-N/A}" >&2
  echo "Conectate a la LAN/WiFi del OpenWrt y reintenta con el host correcto." >&2
  echo "Ejemplo: ROUTER_HOST=192.168.1.1 bash scripts/esc1_rollback_openwrt_policy.sh" >&2
  exit 1
fi

echo "Buscando backups mas recientes..."
# Toma el backup mas nuevo de cada componente critico.
LATEST_DHCP="$(sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "ls -1t /etc/config/dhcp.bak-esc1-* 2>/dev/null | head -n 1")"
LATEST_FW="$(sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "ls -1t /etc/config/firewall.bak-esc1-* 2>/dev/null | head -n 1")"
LATEST_UHTTPD="$(sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "ls -1t /etc/config/uhttpd.bak-esc1-* 2>/dev/null | head -n 1")"
LATEST_INDEX="$(sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "ls -1t /www/index.html.bak-esc1-* 2>/dev/null | head -n 1")"

if [[ -z "$LATEST_DHCP" || -z "$LATEST_FW" ]]; then
  echo "No se encontraron backups de ESC1 para rollback." >&2
  exit 1
fi

echo "Restaurando DHCP: $LATEST_DHCP"
echo "Restaurando Firewall: $LATEST_FW"
if [[ -n "$LATEST_UHTTPD" ]]; then
  echo "Restaurando uhttpd: $LATEST_UHTTPD"
else
  echo "No hay backup de /etc/config/uhttpd; se limpiara solo esc1 error_page si existe."
fi
if [[ -n "$LATEST_INDEX" ]]; then
  echo "Restaurando Web index: $LATEST_INDEX"
else
  echo "No hay backup de /www/index.html; se mantiene el actual."
fi

sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" <<EOF
set -e
# Restaura configuraciones base de red y firewall.
cp "$LATEST_DHCP" /etc/config/dhcp
cp "$LATEST_FW" /etc/config/firewall

# Restaura uhttpd si hay backup; de lo contrario limpia solo error_page.
if [ -n "$LATEST_UHTTPD" ]; then
  cp "$LATEST_UHTTPD" /etc/config/uhttpd
else
  uci -q delete uhttpd.main.error_page || true
  uci commit uhttpd
fi

# Limpia artefactos de bloqueo DNS/HTTP creados por ESC1.
rm -f /etc/esc1-blocklist.hosts
rm -f /etc/esc1-dnsmasq.d/esc1-blocklist.wildcard.conf
if [ -d /etc/esc1-dnsmasq.d ] && [ -z "$(ls -A /etc/esc1-dnsmasq.d 2>/dev/null)" ]; then
  rmdir /etc/esc1-dnsmasq.d || true
fi
rm -f /www/esc1-bloqueado.html

# Restaura index original si existia backup.
if [ -n "$LATEST_INDEX" ]; then
  cp "$LATEST_INDEX" /www/index.html
fi

# Reinicia servicios para aplicar estado limpio.
/etc/init.d/dnsmasq restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart
EOF

echo "Rollback completado correctamente."
