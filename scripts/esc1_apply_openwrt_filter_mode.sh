#!/usr/bin/env bash
set -euo pipefail

ROUTER_HOST="${ROUTER_HOST:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PASS="${ROUTER_PASS:-DTIC2025B_jp}"
SSH_OPTS="-o ConnectTimeout=8 -o StrictHostKeyChecking=no"

# PERFIL DE BLOQUEO:
# - core     : solo dominios criticos (recomendado para estabilidad)
# - extended : usa listas externas + dominios criticos
BLOCK_PROFILE="${BLOCK_PROFILE:-core}"

# En modo extended, limita el volumen de dominios para no saturar el router.
# 0 = sin limite (NO recomendado en equipos con poca RAM/CPU).
MAX_DOMAINS="${MAX_DOMAINS:-30000}"
WHITELIST_FILE="${WHITELIST_FILE:-/home/jeanpoll/Escritorio/tesis_escenario1/scripts/esc1_whitelist_domains.txt}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$(mktemp -d)"
ROUTER_LAN_IP="${ROUTER_LAN_IP:-192.168.1.1}"
REDIRECT_BLOCKED_TO_LOCAL="${REDIRECT_BLOCKED_TO_LOCAL:-1}"

PORN_SRC_STEVENBLACK="https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts"
PORN_SRC_ANTIPORN="https://raw.githubusercontent.com/4skinSkywalker/Anti-Porn-HOSTS-File/master/HOSTS.txt"
PORN_SRC_BLOCKLISTPROJECT="https://raw.githubusercontent.com/blocklistproject/Lists/master/porn.txt"
PIRACY_SRC="https://raw.githubusercontent.com/blocklistproject/Lists/master/piracy.txt"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if ! sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "echo ESC1_FILTER_CHECK" >/dev/null 2>&1; then
  CURRENT_IPS="$(hostname -I 2>/dev/null | xargs || true)"
  CURRENT_GW="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  echo "No hay acceso SSH al router objetivo: $ROUTER_HOST" >&2
  echo "IPs locales detectadas: ${CURRENT_IPS:-N/A}" >&2
  echo "Gateway actual detectado: ${CURRENT_GW:-N/A}" >&2
  echo "Conectate a la LAN/WiFi del OpenWrt y reintenta con el host correcto." >&2
  echo "Ejemplo: ROUTER_HOST=192.168.1.1 bash scripts/esc1_apply_openwrt_filter_mode.sh" >&2
  exit 1
fi

if ! [[ "$MAX_DOMAINS" =~ ^[0-9]+$ ]]; then
  echo "MAX_DOMAINS debe ser un entero mayor o igual a 0." >&2
  exit 1
fi

if [[ "$BLOCK_PROFILE" != "core" && "$BLOCK_PROFILE" != "extended" ]]; then
  echo "BLOCK_PROFILE invalido: $BLOCK_PROFILE (usa core o extended)" >&2
  exit 1
fi

echo "[1/6] Preparando base de dominios ($BLOCK_PROFILE)..."
if [[ "$BLOCK_PROFILE" == "core" ]]; then
  # Modo liviano: solo dominios criticos para minimizar carga del router.
  # Incluye dominios principales de pornhub/xvideos y antievasion DNS privada.
  cat > "$WORK_DIR/domains.raw" <<'EOF'
pornhub.com
pornhub.net
pornhub.org
pornhubpremium.com
phncdn.com
phprcdn.com
xvideos.com
xvideos.es
xvideos2.com
xvideos-cdn.com
dns.google
dns.quad9.net
cloudflare-dns.com
one.one.one.one
mozilla.cloudflare-dns.com
security.cloudflare-dns.com
family.cloudflare-dns.com
doh.opendns.com
dns.nextdns.io
dns.adguard.com
EOF
else
  # Modo extendido: descarga listas externas y luego recorta por MAX_DOMAINS.
  echo "[1/6] Descargando listas externas..."
  curl -L --fail --silent --show-error "$PORN_SRC_STEVENBLACK" -o "$WORK_DIR/porn_stevenblack.hosts"
  curl -L --fail --silent --show-error "$PORN_SRC_ANTIPORN" -o "$WORK_DIR/porn_antiporn.hosts"
  curl -L --fail --silent --show-error "$PORN_SRC_BLOCKLISTPROJECT" -o "$WORK_DIR/porn_blocklistproject.txt"
  curl -L --fail --silent --show-error "$PIRACY_SRC" -o "$WORK_DIR/piracy.txt"

  echo "[2/6] Normalizando dominios descargados..."
  awk '
    /^[[:space:]]*#/ {next}
    NF==0 {next}
    {
      if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && NF>=2) {
        print $2
      } else {
        print $1
      }
    }
  ' "$WORK_DIR/porn_stevenblack.hosts" "$WORK_DIR/porn_antiporn.hosts" "$WORK_DIR/porn_blocklistproject.txt" "$WORK_DIR/piracy.txt" \
    | sed 's/#.*$//' \
    | sed 's/^www\.//' \
    | tr '[:upper:]' '[:lower:]' \
    | grep -E '^[a-z0-9.-]+$' \
    | grep -vE '^localhost$|^broadcasthost$|^local$' > "$WORK_DIR/domains.raw"

  # Dominios de DNS cifrado para reducir bypass por DoH/DoT.
  cat <<'EOF' >> "$WORK_DIR/domains.raw"
dns.google
dns.quad9.net
cloudflare-dns.com
one.one.one.one
mozilla.cloudflare-dns.com
security.cloudflare-dns.com
family.cloudflare-dns.com
doh.opendns.com
dns.nextdns.io
dns.adguard.com
EOF
fi

sort -u "$WORK_DIR/domains.raw" > "$WORK_DIR/domains.unique"

if [[ -f "$WHITELIST_FILE" ]]; then
  grep -E '^[a-zA-Z0-9.-]+$' "$WHITELIST_FILE" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^www\.//' \
    | sort -u > "$WORK_DIR/whitelist.clean"
  grep -vxFf "$WORK_DIR/whitelist.clean" "$WORK_DIR/domains.unique" > "$WORK_DIR/domains.filtered"
else
  cp "$WORK_DIR/domains.unique" "$WORK_DIR/domains.filtered"
fi

if [[ "$BLOCK_PROFILE" == "extended" && "$MAX_DOMAINS" -gt 0 ]]; then
  # Recorte de seguridad para routers con recursos limitados.
  head -n "$MAX_DOMAINS" "$WORK_DIR/domains.filtered" > "$WORK_DIR/domains.candidate"
else
  cp "$WORK_DIR/domains.filtered" "$WORK_DIR/domains.candidate"
fi

# Dominios criticos que SIEMPRE deben quedar incluidos, aunque haya whitelist o recorte.
cat > "$WORK_DIR/critical.domains" <<'EOF'
pornhub.com
pornhub.net
pornhub.org
pornhubpremium.com
phncdn.com
phprcdn.com
xvideos.com
xvideos.es
xvideos2.com
xvideos-cdn.com
dns.google
cloudflare-dns.com
one.one.one.one
mozilla.cloudflare-dns.com
dns.quad9.net
doh.opendns.com
dns.nextdns.io
dns.adguard.com
EOF

cat "$WORK_DIR/domains.candidate" "$WORK_DIR/critical.domains" | sort -u > "$WORK_DIR/domains.final"

BLOCK_IPV4="0.0.0.0"
if [[ "$REDIRECT_BLOCKED_TO_LOCAL" == "1" ]]; then
  BLOCK_IPV4="$ROUTER_LAN_IP"
fi

# Genera bloqueo dual-stack por dominio para evitar bypass por AAAA/IPv6
awk -v v4="$BLOCK_IPV4" -v v6="::" '{print v4" "$1; print v6" "$1}' "$WORK_DIR/domains.final" > "$WORK_DIR/esc1-blocklist.hosts"
{
  echo "# ESC1 blocklist (filter mode) generado: $STAMP"
  cat "$WORK_DIR/esc1-blocklist.hosts"
} > "$WORK_DIR/esc1-blocklist.with-header.hosts"

# Refuerzo wildcard para subdominios y CNAME (ej. www.*)
awk -v v4="$BLOCK_IPV4" -v v6="::" '{print "address=/"$1"/"v4; print "address=/"$1"/"v6}' "$WORK_DIR/domains.final" > "$WORK_DIR/esc1-blocklist.wildcard.conf"

TOTAL_DOMAINS="$(wc -l < "$WORK_DIR/domains.final")"
echo "Dominios bloqueados (final): $TOTAL_DOMAINS [perfil=$BLOCK_PROFILE]"
if [[ "$REDIRECT_BLOCKED_TO_LOCAL" == "1" ]]; then
  echo "Modo bloqueo: redireccion DNS al router ($ROUTER_LAN_IP) + pagina educativa (HTTP)."
else
  echo "Modo bloqueo: sinkhole DNS a 0.0.0.0/::"
fi

echo "[3/6] Subiendo blocklist al router..."
sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" \
  "cat > /tmp/esc1-blocklist.hosts" < "$WORK_DIR/esc1-blocklist.with-header.hosts"
sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" \
  "cat > /tmp/esc1-blocklist.wildcard.conf" < "$WORK_DIR/esc1-blocklist.wildcard.conf"

echo "[4/6] Aplicando politica funcional (filtro por contenido)..."
sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "STAMP='$STAMP' REDIRECT_BLOCKED_TO_LOCAL='$REDIRECT_BLOCKED_TO_LOCAL' sh -s" <<'EOF_REMOTE'
set -e

cp /etc/config/dhcp "/etc/config/dhcp.bak-esc1-${STAMP}"
cp /etc/config/firewall "/etc/config/firewall.bak-esc1-${STAMP}"
cp /etc/config/uhttpd "/etc/config/uhttpd.bak-esc1-${STAMP}"

mv /tmp/esc1-blocklist.hosts /etc/esc1-blocklist.hosts
chmod 644 /etc/esc1-blocklist.hosts

mkdir -p /etc/esc1-dnsmasq.d
mv /tmp/esc1-blocklist.wildcard.conf /etc/esc1-dnsmasq.d/esc1-blocklist.wildcard.conf
chmod 644 /etc/esc1-dnsmasq.d/esc1-blocklist.wildcard.conf

uci -q del_list dhcp.@dnsmasq[0].addnhosts='/etc/esc1-blocklist.hosts' || true
uci add_list dhcp.@dnsmasq[0].addnhosts='/etc/esc1-blocklist.hosts'
uci -q del_list dhcp.@dnsmasq[0].confdir='/etc/esc1-dnsmasq.d' || true
uci add_list dhcp.@dnsmasq[0].confdir='/etc/esc1-dnsmasq.d'
uci set dhcp.@dnsmasq[0].localservice='1'
uci commit dhcp

# Anti-bypass minimo
uci -q delete firewall.esc1_force_dns || true
uci set firewall.esc1_force_dns='redirect'
uci set firewall.esc1_force_dns.name='ESC1-Force-DNS'
uci set firewall.esc1_force_dns.src='lan'
uci set firewall.esc1_force_dns.proto='tcp udp'
uci set firewall.esc1_force_dns.src_dport='53'
uci set firewall.esc1_force_dns.target='DNAT'
uci set firewall.esc1_force_dns.dest_port='53'

uci -q delete firewall.esc1_block_dot || true
uci set firewall.esc1_block_dot='rule'
uci set firewall.esc1_block_dot.name='ESC1-Block-DoT-853'
uci set firewall.esc1_block_dot.src='lan'
uci set firewall.esc1_block_dot.dest='wan'
uci set firewall.esc1_block_dot.proto='tcp udp'
uci set firewall.esc1_block_dot.dest_port='853'
uci set firewall.esc1_block_dot.target='REJECT'

# Limpia reglas del modo estricto para devolver Internet normal
uci -q delete firewall.esc1_http_redirect || true
uci -q delete firewall.esc1_block_https || true
uci -q delete firewall.esc1_block_quic || true
uci -q delete firewall.esc1_block_wan || true

if [ "${REDIRECT_BLOCKED_TO_LOCAL:-1}" = "1" ]; then
  if [ -f /www/index.html ] && ! grep -q 'ESC1-BLOCK-PAGE-INDEX' /www/index.html 2>/dev/null; then
    cp /www/index.html "/www/index.html.bak-esc1-${STAMP}"
  fi

  cat > /www/esc1-bloqueado.html <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESC1 - Sitio bloqueado</title>
  <style>
    :root {
      --bg1: #06243d;
      --bg2: #0f4c75;
      --card: rgba(255,255,255,0.10);
      --text: #f5fbff;
      --accent: #ffd166;
      --line: rgba(255,255,255,0.24);
    }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: "Trebuchet MS", "Segoe UI", sans-serif;
      color: var(--text);
      padding: 22px;
      background:
        radial-gradient(circle at 18% 12%, #1b9aaa 0%, transparent 42%),
        linear-gradient(145deg, var(--bg1), var(--bg2));
    }
    .card {
      width: min(920px, 100%);
      border: 1px solid var(--line);
      border-radius: 16px;
      background: var(--card);
      box-shadow: 0 20px 40px rgba(0,0,0,.25);
      backdrop-filter: blur(4px);
      padding: 26px;
    }
    .pill {
      display: inline-block;
      font-size: 12px;
      letter-spacing: .08em;
      text-transform: uppercase;
      padding: 6px 10px;
      border-radius: 999px;
      color: var(--accent);
      border: 1px solid rgba(255,209,102,.55);
      background: rgba(255,209,102,.18);
    }
    h1 { margin: 12px 0 10px; font-size: clamp(1.6rem, 4vw, 2.35rem); }
    p { margin: 8px 0; line-height: 1.55; font-size: 1.02rem; }
    .box {
      margin-top: 14px;
      border-left: 4px solid var(--accent);
      padding-left: 12px;
      color: #e9f8ff;
    }
    ul { margin: 12px 0 0; padding-left: 18px; }
    li { margin: 6px 0; }
  </style>
</head>
<body>
  <main class="card">
    <span class="pill">ESC1 Filtro Educativo</span>
    <h1>Acceso restringido por politica de red</h1>
    <p>Esta solicitud fue bloqueada por la configuracion de seguridad del laboratorio.</p>
    <div class="box">
      Uso permitido: contenido academico, investigacion y recursos educativos.
    </div>
    <ul>
      <li>Se bloquea contenido adulto, pirateria y evasiones DNS.</li>
      <li>Si crees que es un falso positivo, solicita revision del dominio.</li>
      <li>Para continuar, abre un sitio academico autorizado.</li>
    </ul>
  </main>
</body>
</html>
HTML

  cat > /www/index.html <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <!-- ESC1-BLOCK-PAGE-INDEX -->
  <meta http-equiv="refresh" content="0; url=/esc1-bloqueado.html">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESC1 - Redirigiendo</title>
</head>
<body>
  <p>Redirigiendo a pagina informativa...</p>
</body>
</html>
HTML

  # En rutas largas que no existan, uhttpd responde con la pagina educativa.
  uci set uhttpd.main.error_page='/esc1-bloqueado.html'
else
  LATEST_INDEX="$(ls -1t /www/index.html.bak-esc1-* 2>/dev/null | head -n 1 || true)"
  rm -f /www/esc1-bloqueado.html
  uci -q delete uhttpd.main.error_page || true
  if [ -n "$LATEST_INDEX" ]; then
    cp "$LATEST_INDEX" /www/index.html
  fi
fi

uci commit uhttpd

uci commit firewall

/etc/init.d/dnsmasq restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart
EOF_REMOTE

echo "[5/6] Verificando reglas aplicadas..."
sshpass -p "$ROUTER_PASS" ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" \
  "uci show firewall.esc1_force_dns; uci show firewall.esc1_block_dot; uci -q show firewall.esc1_block_wan || true; uci -q show firewall.esc1_block_https || true; grep -n '/etc/esc1-blocklist.hosts' /etc/config/dhcp || true; uci -q show dhcp.@dnsmasq[0].confdir || true; uci -q show uhttpd.main.error_page || true; wc -l /etc/esc1-blocklist.hosts; wc -l /etc/esc1-dnsmasq.d/esc1-blocklist.wildcard.conf; ls -l /www/esc1-bloqueado.html /www/index.html 2>/dev/null || true"

echo "[6/6] Modo filtro aplicado correctamente."
echo "Backups remotos: /etc/config/dhcp.bak-esc1-$STAMP, /etc/config/firewall.bak-esc1-$STAMP, /etc/config/uhttpd.bak-esc1-$STAMP"
