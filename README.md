# Escenario 1 — Detección de Red y Control OpenWrt

Proyecto de tesis CEC-EPN. Dashboard en tiempo real para detectar dispositivos en la red LAN, monitorear consultas DNS y controlar políticas de filtrado en un router OpenWrt, todo visualizado con D3.js a través de Node-RED.

## Qué hace

- **Escaneo de red:** detecta dispositivos activos en la subred usando `nmap`
- **Mapa de red:** visualización interactiva con D3.js (nodos y conexiones)
- **DNS syslog:** recibe logs UDP del router OpenWrt y muestra consultas en tiempo real
- **Control SSH del router:** cambia SSID, bloquea/habilita internet, aplica whitelist de dominios
- **Dashboard:** métricas de CPU/RAM del router y conteo de dispositivos conectados

## Requisitos previos

- Docker y Docker Compose instalados
- Router **OpenWrt** en la red local con SSH habilitado
- Los contenedores necesitan capacidades de red especiales (`NET_RAW`, `NET_ADMIN`) — ya están en el `docker-compose.yml`

## Setup rápido

```bash
# 1. Clonar el repositorio
git clone https://github.com/jeanpollcardosochiriboga/tesis_escenario1_git.git
cd tesis_escenario1_git

# 2. Revisar la configuración de red (ver sección siguiente)

# 3. Arrancar
docker-compose up -d

# Ver logs en tiempo real
docker-compose logs -f
```

El dashboard queda disponible en `http://localhost:1881`.

## Configurar para una nueva instalación

Toda la configuración se hace en un solo archivo `.env`. No es necesario tocar `flows.json`.

```bash
cp .env.example .env
nano .env   # editar los valores según tu red
```

| Variable | Descripción | Ejemplo |
|---|---|---|
| `ROUTER_IP` | IP del router OpenWrt | `192.168.1.1` |
| `ROUTER_PASS` | Contraseña SSH del router (usuario `root`) | `mi_password` |
| `SUBNET` | Subred a escanear con nmap | `192.168.1.0/24` |
| `MY_PC_IP` | IP del equipo administrador (excluida del mapa) | `192.168.1.10` |
| `DASH_IP` | IP del servidor donde corre Node-RED (para QR) | `192.168.1.10` |
| `DASH_PORT` | Puerto del dashboard (no cambiar salvo conflicto) | `1881` |

Los nodos de Node-RED leen estas variables automáticamente vía `env.get('NOMBRE')`. Después de editar `.env`, reinicia el contenedor para que tome los nuevos valores:

```bash
docker-compose down && docker-compose up -d
```

## Arquitectura

```
docker-compose.yml
├── Dockerfile         → Node.js 18 Alpine + nmap + openssh-client + Node-RED
├── flows.json         → Lógica backend (Node-RED) — no editar a mano
├── settings.js        → Configuración de Node-RED
├── public/
│   ├── images/        → Iconos de dispositivos
│   └── js/
│       └── d3.v7.min.js
└── scripts/
    ├── esc1_apply_openwrt_filter_mode.sh
    ├── esc1_apply_openwrt_policy.sh
    ├── esc1_rollback_openwrt_policy.sh
    └── esc1_whitelist_domains.txt  ← dominios permitidos en el filtro DNS
```

## Cómo agregar dominios a la whitelist

Edita `scripts/esc1_whitelist_domains.txt` agregando un dominio por línea:

```
epn.edu.ec
aulasvirtuales.epn.edu.ec
nuevo.dominio.ec
```

Luego aplica el cambio desde el dashboard o re-ejecuta el script SSH correspondiente.

## Código QR del dashboard

El QR del dashboard se genera **automáticamente en runtime**:

1. Node-RED ejecuta `hostname -I` para detectar la IP real del servidor.
2. Si la detección falla, usa `DASH_IP` del archivo `.env`.
3. Si ninguna está disponible, el QR no se muestra y queda un aviso en los logs.

No es necesario generar ni reemplazar ninguna imagen PNG. Con solo tener `DASH_IP` en `.env` y correr `docker-compose up -d`, el QR apunta a la instalación correcta.

El QR WiFi también es dinámico: el operador escribe el nombre de la red (SSID) en el formulario del dashboard y el QR se genera al instante.

## Cómo modificar el flujo (Node-RED)

1. Asegúrate de que el contenedor esté corriendo
2. Abre el editor en `http://localhost:1881/admin`
3. Realiza los cambios en el editor visual
4. **Menú (≡) → Export → Download** para obtener el `flows.json` actualizado
5. Reemplaza el `flows.json` del proyecto y haz commit

## Detener el servicio

```bash
docker-compose down
```

## Conectividad de campo

### Prioridades de internet para la demo (sin comandos — todo automático)

Sigue este orden. Si la opción actual es inestable o lenta, pasa a la siguiente.

| Prioridad | Fuente de internet | Qué conectar | Tiempo |
|---|---|---|---|
| **① Mejor** | Cable ethernet del venue | Cable directo al puerto **WAN azul** del router | ~10 seg |
| **② Buena** | Datos móviles del celular | Cable USB al PC + tethering activo en el celular | ~10 seg |
| **③ Última** | WiFi del PC | PC conectado a un WiFi con internet | automático |

**Notas importantes:**
- Verificar siempre que la opción funcione cargando una página en el PC antes de empezar la demo.
- **No usar tethering del celular si el celular está en la misma WiFi que el PC** — crea un bucle y la conexión se vuelve inestable.
- El adaptador USB-LAN (`enx000a4300a7b1`) debe estar **desconectado** durante la demo para evitar conflictos de rutas.
- Si el WiFi del PC muestra buena velocidad LAN pero sin internet (páginas no cargan), es un problema del proveedor o captive portal — pasar a la opción ②.

---

El router TP-Link Archer C7 AC1750 con OpenWrt tiene las bandas asignadas así:

| Radio | Banda | Rol fijo |
|---|---|---|
| `radio1` | **2.4 GHz** | AP del laboratorio — siempre activo, siempre AP |
| `radio0` | **5 GHz** | Upstream cliente (STA) — solo en modo B2; desactivado en los demás casos |

SSID del laboratorio: **CASA ABIERTA TI** (sin contraseña, radio1).

### Escenario A — Hay punto de red cableado

Conectar el cable ethernet del venue al puerto WAN del router. El router obtiene internet por DHCP sobre WAN sin ninguna reconfiguración. Ambas bandas quedan en modo AP; deshabilitar radio0 si no se necesita.

### Escenario B1 — Sin cable: USB tethering (método primario)

```
[Datos móviles]
      │
  Celular
      │ cable USB
  Laptop / PC admin
      │ cable Ethernet  →  Puerto WAN azul del router
                                   │
                       radio1 (2.4 GHz, AP) → red del laboratorio
                       radio0 (5 GHz) → desactivado
```

El PC actúa como gateway NAT entre el tethering USB del celular y el puerto WAN del router. Requiere configuración manual en Linux (probado en Ubuntu con UFW activo).

**Requisito previo:** `dnsmasq` instalado — `sudo apt install dnsmasq` si no está.

**Paso 0 — Tethering USB:**
Celular → Ajustes → Punto de acceso → Tethering USB → activar. Verificar que aparece una interfaz `enx...` con IP `10.13.103.x`:
```bash
ip addr show | grep "enx"
```

**Paso 1 — IP estática en la interfaz que va al WAN del router** (normalmente `eno1`):
```bash
sudo ip addr add 10.42.0.1/24 dev eno1
```

**Paso 2 — Habilitar IP forwarding:**
```bash
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
```

**Paso 3 — Iniciar dnsmasq como servidor DHCP en eno1:**
```bash
sudo dnsmasq --interface=eno1 --bind-interfaces \
  --dhcp-range=10.42.0.10,10.42.0.50,12h \
  --server=8.8.8.8 --pid-file=/tmp/dnsmasq-eno1.pid
```

**Paso 4 — NAT e iptables FORWARD:**
```bash
sudo iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i eno1 -j ACCEPT
sudo iptables -A FORWARD -o eno1 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

**Paso 5 — CRÍTICO: desactivar UFW (cortafuegos)**

UFW tiene dos efectos que rompen el tethering:
1. Bloquea UDP puerto 67 en INPUT → `dnsmasq` no recibe los DHCP Discovers del router.
2. Establece política `FORWARD DROP` → aunque se agreguen reglas `iptables ACCEPT`, las cadenas internas de UFW (`ufw-before-forward`, `ufw-reject-forward`) procesan el tráfico antes que esas reglas y lo bloquean.

```bash
# Permitir DHCP en eno1 (necesario aunque se deshabilite UFW después)
sudo ufw allow in on eno1 to any port 67 proto udp
sudo ufw allow in on eno1 to any port 68 proto udp
# Desactivar UFW — solución definitiva para el contexto de demo
sudo ufw disable
```

> **Nota:** `sudo ufw enable` restaura el cortafuegos al terminar la presentación.

**Paso 6 — Conectar el cable y reconectar WAN del router:**
1. Conectar el cable Ethernet del PC al **puerto WAN azul** del router (no a los puertos LAN amarillos).
2. En LuCI (`http://192.168.1.1`) → Network → Interfaces → WAN → **Restart**.
3. Esperar 10 segundos — el WAN debe mostrar una IP `10.42.0.x`.

**Verificación:**
```bash
# Confirmar que el router obtuvo IP (via SSH desde el PC si wlp3s0 está en la LAN)
sshpass -p 'TU_ROUTER_PASS' ssh root@192.168.1.1 "ip addr show eth0.2 | grep inet"
```
Desde un dispositivo conectado a **CASA ABIERTA TI**: `ping 8.8.8.8`

**Diagnóstico — si el router no obtiene IP:**
```bash
# Verificar que los DHCP Discovers del router llegan a eno1
# (ejecutar y luego hacer Restart del WAN en LuCI)
sudo tcpdump -i eno1 port 67 -n -c 5
# Buscar paquetes con Vendor-Class "udhcp" y hostname "OpenWrt"
# Si no aparece nada → el cable está en un puerto LAN amarillo, no en el WAN azul
```

**Preguntas frecuentes sobre B1:**

**¿Si consigo punto de red cableado en el venue, tengo que deshacer la configuración B1?**
No afecta nada — simplemente conecta el cable del venue al WAN azul del router y el router obtiene internet directamente por DHCP. La configuración B1 (dnsmasq, iptables, UFW) no entra en juego. Puedes restaurar el cortafuegos con `sudo ufw enable` al terminar.

**¿Puedo usar una red WiFi con internet en vez de datos móviles del celular?**
Sí, funciona igual. La regla `MASQUERADE` no especifica interfaz de salida — usa automáticamente la ruta por defecto del PC. Si `wlp3s0` está conectada a un WiFi con internet y es la ruta por defecto, el NAT sale por ahí sin cambiar ningún comando de los Pasos 4 ni 5. La única consecuencia: `wlp3s0` no puede estar simultáneamente en el WiFi de internet y en **CASA ABIERTA TI**, por lo que el SSH al router vía `192.168.1.1` no estará disponible desde el PC — pero los dispositivos del laboratorio tienen internet igual.


## Diagnóstico: estado del router post-reconfiguración manual

Si el dashboard Node-RED perdió las funciones SSH después de una manipulación via LuCI, ejecutar estos comandos para leer el estado UCI actual:

```bash
# 1. Verificar acceso SSH
ssh root@192.168.1.1 "echo SSH_OK"

# 2. Interfaces activas y rutas (¿hay default route?)
ssh root@192.168.1.1 "ip addr show; echo ---; ip route show"

# 3. Modos de los radios (AP vs STA) y SSIDs configurados
ssh root@192.168.1.1 "uci show wireless"

# 4. Interfaces de red (¿existe wwan? ¿tiene dispositivo?)
ssh root@192.168.1.1 "uci show network"

# 5. Firewall (¿wwan está en zona WAN? ¿quedan reglas esc1_*?)
ssh root@192.168.1.1 "uci show firewall | grep -E '(esc1|name|target|src|dest|network|zone)'"

# 6. Estado de wwan
ssh root@192.168.1.1 "ip addr show wwan0 2>/dev/null || ip addr show | grep -A3 wwan || echo 'sin wwan activo'"
```

**Qué buscar:**
- `uci show wireless` con `mode='sta'` en un radio → ese radio está en modo cliente, no AP.
- `wifinet1.network` con múltiples valores (`wwan wan lan wan6`) → error de LuCI, corregir a solo `'wwan'`.
- `ip route show` sin `default via` → NAT/gateway no funciona.
- Reglas con prefijo `esc1_` → pueden bloquear tráfico inesperadamente.

**Limpiar configuración residual (red mal asignada en wifinet1):**
```bash
ssh root@192.168.1.1 "uci set wireless.wifinet1.network='wwan' && uci commit wireless"
ssh root@192.168.1.1 "wifi reload &"
```
