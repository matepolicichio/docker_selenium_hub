# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Crear la red externa (una sola vez, antes del primer arranque)
docker network create selenium-grid

# Arrancar todo el stack
docker compose up -d

# Detener el stack
docker compose down

# Reconstruir el contenedor Tor tras cambiar Dockerfile o torrc
docker compose build tor
docker compose up -d tor

# Logs en tiempo real
docker compose logs -f tor
docker compose logs -f selenium-hub

# Estado y health checks de todos los contenedores
docker compose ps
```

## Arquitectura general

```
Internet
   │ HTTPS:443
   ▼
nginx (VPS, host)
   │ HTTP:127.0.0.1:4444
   ▼
selenium-hub:4444  ──── event bus interno (4442-4443) ────►  chrome / chrome2 / chrome3
                                                                      │
                                                               tor:9050 (SOCKS5)
                                                               (solo red Docker)
```

Un stack Docker Compose con **Selenium Grid 4** y un **proxy Tor SOCKS5**, expuesto al exterior a través de **nginx con TLS** (Let's Encrypt). Todo corre sobre la red Docker externa `selenium-grid`.

---

## Docker Compose — servicios

| Servicio | Imagen | Puerto host | Propósito |
|---|---|---|---|
| `selenium-hub` | `selenium/hub:latest` | `4444` (solo loopback) | Hub central del grid |
| `chrome`, `chrome2`, `chrome3` | `selenium/node-chrome:latest` | — | Nodos Chrome, 4 sesiones c/u (12 total) |
| `tor` | build local (`Dockerfile`) | — (solo interno) | Proxy SOCKS5 en `tor:9050` |

MongoDB y mongo-express están comentados en `compose.yaml` — listos para activar para persistencia futura.

### Seguridad del stack Docker

- **Puertos `4442-4443` (event bus)** NO expuestos en el host → evita registro de nodos maliciosos.
- **Puerto `9050` de Tor** NO expuesto en el host → el proxy solo es alcanzable dentro de la red Docker.
- Los nodos Chrome usan `depends_on` con `condition: service_healthy` → arrancan solo cuando hub y Tor pasan el healthcheck.
- `restart: unless-stopped` en todos los servicios.

---

## Selenium Hub — autenticación

Dos capas independientes de seguridad:

| Mecanismo | Variable | Protege |
|---|---|---|
| Basic Auth | `SE_ROUTER_USERNAME` / `SE_ROUTER_PASSWORD` | UI (`/grid/console`) y la API REST completa |
| Access Key | `SE_SESSION_ACCESS_KEY` | Creación de sesiones WebDriver |

Configurar ambas en `.env` antes de arrancar el stack.

**Ejemplo de conexión desde código Python:**
```python
hub_url = "https://admin:PASSWORD@selenium-hub.ingenios.com.ar/wd/hub"
driver = webdriver.Remote(command_executor=hub_url, options=webdriver.ChromeOptions())
```

---

## Tor — configuración (`torrc`)

| Parámetro | Valor | Motivo |
|---|---|---|
| `SocksPort` | `0.0.0.0:9050 IsolateClientAddr IsolateSOCKSAuth` | Cada nodo Chrome usa circuitos Tor distintos |
| `ControlPort` | `0.0.0.0:9051` | Control port accesible desde la red Docker para `SIGNAL NEWNYM` |
| `CookieAuthentication` | `0` | Sin auth: seguro porque `SOCKSPolicy` ya restringe el acceso a IPs Docker internas |
| `SOCKSPolicy` | `accept 172.16.0.0/12`, `accept 10.0.0.0/8`, `reject *` | Solo IPs Docker internas pueden usar el proxy |
| `Log` | `notice stdout` | Evita volumen excesivo de logs en producción |
| `ExitNodes` | `{us}` con `StrictNodes 0` | Salida preferente por EE.UU. |
| `MaxCircuitDirtiness` | `120` | Circuitos reciclados cada 2 minutos |
| `NewCircuitPeriod` | `60` | Nuevos circuitos intentados cada 60 segundos |

### Renovación de circuito bajo demanda (`SIGNAL NEWNYM`)

El control port permite que el bot solicite activamente un nuevo circuito Tor cuando detecta `ERR_SOCKS_CONNECTION_FAILED`. Flujo:

```
bot: asyncio.open_connection("tor", 9051)
bot → AUTHENTICATE ""
tor → 250 OK
bot → SIGNAL NEWNYM
tor → 250 OK  (nuevo circuito en construcción)
bot: espera 12s → reintenta navegación con nueva IP de salida
```

**Rate limit de Tor**: mínimo 10s entre señales NEWNYM. Si varios workers envían NEWNYM simultáneamente, Tor aplica el primero; los demás reciben `250 OK` pero comparten el nuevo circuito. Correcto sin coordinación entre workers.

**Fallback**: si el control port no responde (e.g. torrc sin `ControlPort`), la función devuelve `False` y el bot cae al backoff normal de 30–120s.

---

## Nginx — configuración (`nginx/`)

El directorio `nginx/` contiene los archivos listos para copiar al VPS.

```
nginx/
├── rate-limit.conf      → /etc/nginx/conf.d/rate-limit.conf
└── selenium-hub.conf    → /etc/nginx/sites-available/selenium-hub.conf
```

### Despliegue en el VPS

```bash
# 1. Copiar los archivos al VPS
scp nginx/rate-limit.conf   user@vps:/etc/nginx/conf.d/rate-limit.conf
scp nginx/selenium-hub.conf user@vps:/etc/nginx/sites-available/selenium-hub.conf

# 2. Activar el sitio
sudo ln -s /etc/nginx/sites-available/selenium-hub.conf \
           /etc/nginx/sites-enabled/selenium-hub.conf

# 3. Verificar y recargar
sudo nginx -t && sudo systemctl reload nginx
```

### Qué hace cada archivo

**`rate-limit.conf`** — define las zonas de rate limiting en el bloque `http` de nginx:
- `selenium_general`: 60 req/min por IP (burst 20) — para la UI y la API general.
- `selenium_sessions`: 6 req/min por IP (burst 3) — para la creación de sesiones WebDriver.

**`selenium-hub.conf`** — virtual host del hub:

| Feature | Detalle |
|---|---|
| TLS | Certificado Let's Encrypt gestionado por Certbot |
| HSTS | `Strict-Transport-Security` con 1 año + subdomains |
| Security headers | `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `X-XSS-Protection` |
| Rate limiting | Zonas diferenciadas por endpoint (general vs. sesiones) |
| WebSocket | Headers `Upgrade`/`Connection` para la Grid UI en tiempo real |
| `proxy_buffering off` | Evita que el streaming del Grid UI se interrumpa |
| `X-Real-IP` / `X-Forwarded-For` | IP real del cliente visible en los logs del hub |
| `server_tokens off` | No expone la versión de nginx |

### Flujo de seguridad completo

```
Cliente
  │
  │  HTTPS (TLS 1.2/1.3, HSTS)
  ▼
nginx:443
  ├── rate limiting (429 si se supera)
  ├── security headers
  │
  │  HTTP interno (loopback 127.0.0.1:4444)
  ▼
selenium-hub
  ├── SE_ROUTER_USERNAME/PASSWORD  → protege UI y API
  └── SE_SESSION_ACCESS_KEY        → protege creación de sesiones
```

---

## Documentación adicional

| Archivo | Contenido |
|---|---|
| `docs/guia-integracion.md` | Cómo conectar proyectos externos al hub (Python, Node.js, Tor, troubleshooting) |

---

## Variables de entorno (`.env`, en .gitignore)

```bash
# Selenium Hub
SELENIUM_SESSION_ACCESS_KEY=    # Bearer token para crear sesiones
SE_ROUTER_USERNAME=             # Usuario para Basic Auth (UI + API)
SE_ROUTER_PASSWORD=             # Contraseña para Basic Auth (UI + API)

# MongoDB — inactivo, para implementación futura
MONGO_INITDB_ROOT_USERNAME=
MONGO_INITDB_ROOT_PASSWORD=
ME_CONFIG_MONGODB_ADMINUSERNAME=
ME_CONFIG_MONGODB_ADMINPASSWORD=
ME_CONFIG_MONGODB_URL=
ME_CONFIG_BASICAUTH_USERNAME=
ME_CONFIG_BASICAUTH_PASSWORD=
```
