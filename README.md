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

## Configurar credenciales del router

> **Importante:** Los valores de IP del router y su contraseña están actualmente hardcodeados en `flows.json`. Para una nueva instalación debes actualizarlos manualmente desde el editor Node-RED.

### Pasos:

1. Arranca el contenedor: `docker-compose up -d`
2. Abre el editor en `http://localhost:1881/admin`
3. Busca los nodos de tipo **function** que contienen comandos SSH. Usa `Ctrl+F` y busca `DTIC2025B` o `192.168.1.1`
4. En cada nodo, reemplaza:
   - `192.168.1.1` → IP de tu router OpenWrt
   - `DTIC2025B_jp` → tu contraseña SSH del router
5. Haz clic en **Deploy**
6. Exporta el flujo actualizado: **Menú (≡) → Export → Download** y reemplaza `flows.json`

### Nodos que requieren actualización:

| Nodo | Variable a cambiar |
|---|---|
| WiFi SSID change | `ROUTER_IP`, `ROUTER_PASS` |
| Internet block policy | `ROUTER_IP`, `ROUTER_PASS` |
| Internet rollback | `ROUTER_IP`, `ROUTER_PASS` |
| Read SSID | `ROUTER_IP`, `ROUTER_PASS` |
| DHCP lease count | `ROUTER_IP`, `ROUTER_PASS` |
| CPU/RAM load | `ROUTER_IP`, `ROUTER_PASS` |

También actualiza el **rango de subred** en el nodo de escaneo nmap (`192.168.1.0/24` → tu subred).

## Arquitectura

```
docker-compose.yml
├── Dockerfile         → Node.js 18 Alpine + nmap + openssh-client + Node-RED
├── flows.json         → Lógica backend (Node-RED) — no editar a mano
├── settings.js        → Configuración de Node-RED
├── public/
│   ├── images/        → Iconos de dispositivos y QR codes
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

`public/images/dashboard_qr.png` y `wifi_qr.png` son imágenes pre-generadas para el laboratorio de la EPN. En una nueva instalación deben regenerarse:

- **dashboard_qr.png:** genera un QR con la URL de tu dashboard (`http://TU_IP:1881`)
- **wifi_qr.png:** genera un QR con las credenciales WiFi de tu red de laboratorio

Puedes usar cualquier generador de QR online o la librería `qrcode` de Python:
```bash
pip install qrcode[pil]
python3 -c "import qrcode; qrcode.make('http://192.168.X.X:1881').save('dashboard_qr.png')"
```

Reemplaza los archivos en `public/images/` y reconstruye la imagen Docker.

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
