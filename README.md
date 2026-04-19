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
