#!/usr/bin/env bash
set -euo pipefail

ROUTER_HOST="${ROUTER_HOST:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PASS="${ROUTER_PASS:-DTIC2025B_jp}"
ROUTER_LAN_IP="${ROUTER_LAN_IP:-192.168.1.1}"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "[1/4] Aplicando modo Internet restringido (metodo unico recomendado)..."
sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_HOST" \
  "STAMP='$STAMP' ROUTER_LAN_IP='$ROUTER_LAN_IP' sh -s" <<'EOF_REMOTE'
set -e

cp /etc/config/dhcp "/etc/config/dhcp.bak-esc1-${STAMP}"
cp /etc/config/firewall "/etc/config/firewall.bak-esc1-${STAMP}"
if [ -f /www/index.html ]; then
  cp /www/index.html "/www/index.html.bak-esc1-${STAMP}"
fi

# Limpieza de bloqueo por blocklist para evitar reglas mezcladas.
uci -q del_list dhcp.@dnsmasq[0].addnhosts='/etc/esc1-blocklist.hosts' || true
uci set dhcp.@dnsmasq[0].localservice='1'
uci commit dhcp
rm -f /etc/esc1-blocklist.hosts

cat > /www/esc1-bloqueado.html <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESC1 - Sitio bloqueado</title>
  <style>
    :root {
      --bg1: #0b132b;
      --bg2: #1c2541;
      --card: rgba(255,255,255,0.10);
      --text: #f7f9fb;
      --accent: #ffd166;
      --danger: #ff5d5d;
    }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: "Trebuchet MS", "Segoe UI", sans-serif;
      background: radial-gradient(circle at 20% 10%, #3a506b 0%, var(--bg1) 45%),
                  linear-gradient(135deg, var(--bg1), var(--bg2));
      color: var(--text);
      padding: 24px;
    }
    .card {
      width: min(880px, 100%);
      border-radius: 18px;
      background: var(--card);
      border: 1px solid rgba(255,255,255,0.20);
      padding: 28px;
      box-shadow: 0 18px 44px rgba(0,0,0,0.35);
      backdrop-filter: blur(3px);
    }
    .badge {
      display: inline-block;
      font-size: 12px;
      letter-spacing: .08em;
      text-transform: uppercase;
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(255,209,102,0.18);
      color: var(--accent);
      border: 1px solid rgba(255,209,102,0.55);
      margin-bottom: 10px;
    }
    h1 {
      margin: 0 0 10px;
      font-size: clamp(1.6rem, 4vw, 2.4rem);
      line-height: 1.15;
    }
    p {
      margin: 10px 0;
      line-height: 1.55;
      font-size: 1.03rem;
    }
    .pica {
      color: #c3ecff;
      border-left: 4px solid var(--danger);
      padding-left: 12px;
      margin-top: 14px;
    }
    ul {
      margin: 14px 0 0;
      padding-left: 18px;
    }
    li { margin: 6px 0; }
    .foot {
      margin-top: 18px;
      font-size: .9rem;
      opacity: .88;
    }
  </style>
</head>
<body>
  <main class="card">
    <span class="badge">ESC1 Internet Restringido</span>
    <h1>Sitio bloqueado por normas de uso de red</h1>
    <p>Este acceso fue detenido por la politica de seguridad del laboratorio.</p>
    <p class="pica">
      Mensaje didactico: este dominio se fue a la banca por violar reglas
      (contenido adulto, pirateria o riesgo para la red).
    </p>
    <ul>
      <li>La red esta destinada a actividades academicas y de investigacion.</li>
      <li>Se prioriza seguridad, trazabilidad y uso responsable.</li>
      <li>Si consideras que fue un bloqueo incorrecto, solicita revision al administrador.</li>
    </ul>
    <p class="foot">ESC1 - Politica activa de control de navegacion.</p>
  </main>
</body>
</html>
HTML

cat > /www/index.html <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=/esc1-bloqueado.html">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESC1 - Redirigiendo</title>
</head>
<body>
  <p>Redirigiendo a pagina informativa...</p>
</body>
</html>
HTML

# Anti-bypass basico de DNS cifrado y DNS externo.
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

# Redirige toda navegacion HTTP hacia la pagina informativa del router.
uci -q delete firewall.esc1_http_redirect || true
uci set firewall.esc1_http_redirect='redirect'
uci set firewall.esc1_http_redirect.name='ESC1-HTTP-BlockPage'
uci set firewall.esc1_http_redirect.src='lan'
uci set firewall.esc1_http_redirect.proto='tcp'
uci set firewall.esc1_http_redirect.src_dport='80'
uci set firewall.esc1_http_redirect.target='DNAT'
uci set firewall.esc1_http_redirect.dest_port='80'

# Bloquea HTTPS y QUIC para impedir salida web por canales cifrados directos.
uci -q delete firewall.esc1_block_https || true
uci set firewall.esc1_block_https='rule'
uci set firewall.esc1_block_https.name='ESC1-Block-HTTPS-443'
uci set firewall.esc1_block_https.src='lan'
uci set firewall.esc1_block_https.dest='wan'
uci set firewall.esc1_block_https.proto='tcp'
uci set firewall.esc1_block_https.dest_port='443'
uci set firewall.esc1_block_https.target='REJECT'

uci -q delete firewall.esc1_block_quic || true
uci set firewall.esc1_block_quic='rule'
uci set firewall.esc1_block_quic.name='ESC1-Block-QUIC-443'
uci set firewall.esc1_block_quic.src='lan'
uci set firewall.esc1_block_quic.dest='wan'
uci set firewall.esc1_block_quic.proto='udp'
uci set firewall.esc1_block_quic.dest_port='443'
uci set firewall.esc1_block_quic.target='REJECT'

# Regla final: bloqueo total de salida WAN para clientes LAN.
uci -q delete firewall.esc1_block_wan || true
uci set firewall.esc1_block_wan='rule'
uci set firewall.esc1_block_wan.name='ESC1-Block-All-WAN'
uci set firewall.esc1_block_wan.src='lan'
uci set firewall.esc1_block_wan.dest='wan'
uci set firewall.esc1_block_wan.proto='all'
uci set firewall.esc1_block_wan.target='REJECT'

uci commit firewall

/etc/init.d/dnsmasq restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart
EOF_REMOTE

echo "[2/4] Verificando reglas activas..."
sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_HOST" \
  "uci show firewall.esc1_force_dns; uci show firewall.esc1_block_dot; uci show firewall.esc1_http_redirect; uci show firewall.esc1_block_https; uci show firewall.esc1_block_quic; uci show firewall.esc1_block_wan"

echo "[3/4] Verificando pagina educativa..."
sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_HOST" \
  "ls -l /www/esc1-bloqueado.html /www/index.html | cat"

echo "[4/4] Modo restringido aplicado correctamente."
echo "Backups remotos:"
echo "  - /etc/config/dhcp.bak-esc1-$STAMP"
echo "  - /etc/config/firewall.bak-esc1-$STAMP"
echo "  - /www/index.html.bak-esc1-$STAMP"
