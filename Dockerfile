# ---------------------------------------------------------
# IMAGEN BASE PURA: NODE JS (Versión 18 Alpine)
# Esta imagen existe seguro y funciona en todos lados.
# ---------------------------------------------------------
FROM node:18-alpine

# 1. INSTALAMOS HERRAMIENTAS DEL SISTEMA (Con apk)
# Como la base es Alpine pura, 'apk' funcionará 100%.
RUN apk add --no-cache \
    nmap \
    iputils \
    bash \
    curl \
    sudo \
    openssh-client \
    sshpass \
    python3 \
    make \
    g++

# 2. INSTALAMOS NODE-RED MANUALMENTE
# Al instalarlo nosotros, evitamos problemas de versiones raras.
RUN npm install -g --unsafe-perm node-red node-red-dashboard d3

# 3. CREAMOS EL DIRECTORIO DE TRABAJO
WORKDIR /data

# 4. COPIAMOS TUS ARCHIVOS
# Nota: Aquí no usamos usuario 'node-red' porque en la base pura somos 'root' por defecto,
# lo cual es más fácil para tu tesis (menos problemas de permisos).
COPY flows.json /data/flows.json
COPY settings.js /data/settings.js
COPY public /data/public

# 5. VARIABLES Y PUERTO
ENV FLOWS=/data/flows.json
ENV NODE_RED_ENABLE_PROJECTS=false
EXPOSE 1880

# 6. COMANDO DE ARRANQUE
CMD ["node-red", "--userDir", "/data", "flows.json"]
