# Guía de integración — Selenium Hub

Cómo conectar proyectos externos al Selenium Hub, tanto desde contenedores en el mismo VPS como desde hosts remotos.

---

## Arquitectura de red

```
┌─────────────────────────────────────────────────────────────┐
│  VPS                                                        │
│                                                             │
│  ┌──────────────── red: selenium-grid ──────────────────┐  │
│  │                                                       │  │
│  │   selenium-hub:4444   chrome/chrome2/chrome3   tor   │  │
│  │                                                       │  │
│  │   [proyecto-cliente]  ← puede unirse a esta red      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  nginx:443  →  127.0.0.1:4444  (selenium-hub)              │
└─────────────────────────────────────────────────────────────┘
         ↑
    acceso externo via HTTPS
    selenium-hub.ingenios.com.ar
```

Hay dos formas de conectarse al hub:

| Escenario | URL | Cuándo usarla |
|---|---|---|
| **Interno** | `http://selenium-hub:4444` | Proyecto en el mismo VPS, unido a la red `selenium-grid` |
| **Externo** | `https://selenium-hub.ingenios.com.ar` | Proyecto en otro host o desde local |

La conexión interna es preferible: evita el salto por nginx, no tiene rate limiting y la latencia es menor.

---

## Escenario 1 — Mismo VPS, red `selenium-grid`

### 1.1 Configurar `docker-compose.yml` del proyecto cliente

El proyecto cliente debe unirse a la red `selenium-grid` como red externa:

```yaml
services:
  mi-servicio:
    image: mi-imagen:latest
    environment:
      - SELENIUM_HUB_URL=http://selenium-hub:4444
      - SELENIUM_HUB_USER=${SELENIUM_HUB_USER}
      - SELENIUM_HUB_PASS=${SELENIUM_HUB_PASS}
    networks:
      - selenium-grid

networks:
  selenium-grid:
    external: true        # ← La red ya existe, no la crea Compose
```

### 1.2 Variables de entorno del proyecto cliente

Crear un `.env` en el proyecto cliente:

```bash
SELENIUM_HUB_USER=admin
SELENIUM_HUB_PASS=tu_password_aqui
```

### 1.3 Verificar conectividad antes de codear

Desde el contenedor cliente (o desde el host del VPS):

```bash
# Verificar que el hub responde y está listo
curl -s http://admin:password@selenium-hub:4444/wd/hub/status | python3 -m json.tool

# Respuesta esperada:
# { "value": { "ready": true, "message": "Selenium Grid ready." } }
```

---

## Escenario 2 — Host externo (otro VPS, local, CI/CD)

No es necesario unirse a ninguna red. Se conecta directamente por HTTPS:

```bash
# Verificar desde fuera del VPS
curl -s https://admin:password@selenium-hub.ingenios.com.ar/wd/hub/status
```

> **Rate limiting activo:** el endpoint `/session` está limitado a 6 req/min por IP.
> Para pipelines de CI/CD con muchas sesiones paralelas, usar la conexión interna.

---

## Ejemplos de código

### Python

**Instalación:**
```bash
pip install selenium
```

**Conexión básica:**
```python
from selenium import webdriver

# Interno (mismo VPS)
HUB_URL = "http://admin:password@selenium-hub:4444"

# Externo
# HUB_URL = "https://admin:password@selenium-hub.ingenios.com.ar"

options = webdriver.ChromeOptions()
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")

driver = webdriver.Remote(
    command_executor=HUB_URL,
    options=options
)

driver.get("https://example.com")
print(driver.title)
driver.quit()
```

**Con proxy Tor** (solo disponible desde la red `selenium-grid`):
```python
from selenium import webdriver

HUB_URL = "http://admin:password@selenium-hub:4444"

options = webdriver.ChromeOptions()
options.add_argument("--proxy-server=socks5://tor:9050")   # Proxy Tor interno
options.add_argument("--proxy-bypass-list=<-loopback>")    # Forzar todo el tráfico por Tor
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")

driver = webdriver.Remote(
    command_executor=HUB_URL,
    options=options
)

driver.get("https://check.torproject.org")
print(driver.find_element("css selector", "h1").text)      # "Congratulations. This browser is configured to use Tor."
driver.quit()
```

**Patrón recomendado con context manager:**
```python
import os
from contextlib import contextmanager
from selenium import webdriver

HUB_URL = "http://{user}:{pwd}@selenium-hub:4444".format(
    user=os.environ["SELENIUM_HUB_USER"],
    pwd=os.environ["SELENIUM_HUB_PASS"],
)

@contextmanager
def chrome_session(use_tor: bool = False):
    options = webdriver.ChromeOptions()
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    if use_tor:
        options.add_argument("--proxy-server=socks5://tor:9050")
        options.add_argument("--proxy-bypass-list=<-loopback>")

    driver = webdriver.Remote(command_executor=HUB_URL, options=options)
    try:
        yield driver
    finally:
        driver.quit()    # Siempre liberar el slot del nodo

# Uso:
with chrome_session(use_tor=True) as driver:
    driver.get("https://example.com")
    print(driver.title)
```

---

### Node.js

**Instalación:**
```bash
npm install selenium-webdriver
```

**Conexión básica:**
```javascript
const { Builder } = require("selenium-webdriver");
const chrome = require("selenium-webdriver/chrome");

const HUB_URL = "http://admin:password@selenium-hub:4444";

async function run() {
  const options = new chrome.Options();
  options.addArguments("--no-sandbox");
  options.addArguments("--disable-dev-shm-usage");

  const driver = await new Builder()
    .forBrowser("chrome")
    .setChromeOptions(options)
    .usingServer(HUB_URL)
    .build();

  try {
    await driver.get("https://example.com");
    console.log(await driver.getTitle());
  } finally {
    await driver.quit();
  }
}

run();
```

**Con proxy Tor:**
```javascript
const { Builder } = require("selenium-webdriver");
const chrome = require("selenium-webdriver/chrome");

const HUB_URL = "http://admin:password@selenium-hub:4444";

async function runWithTor() {
  const options = new chrome.Options();
  options.addArguments("--proxy-server=socks5://tor:9050");
  options.addArguments("--proxy-bypass-list=<-loopback>");
  options.addArguments("--no-sandbox");
  options.addArguments("--disable-dev-shm-usage");

  const driver = await new Builder()
    .forBrowser("chrome")
    .setChromeOptions(options)
    .usingServer(HUB_URL)
    .build();

  try {
    await driver.get("https://check.torproject.org");
    const heading = await driver.findElement({ css: "h1" });
    console.log(await heading.getText());
  } finally {
    await driver.quit();
  }
}

runWithTor();
```

---

## Opciones de Chrome recomendadas para contenedores

```python
options = webdriver.ChromeOptions()

# Requeridas en Docker
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")

# Opcionales según el caso de uso
options.add_argument("--disable-gpu")
options.add_argument("--window-size=1920,1080")
options.add_argument("--disable-extensions")
options.add_argument("--disable-blink-features=AutomationControlled")   # Reduce detección de bot

# User agent personalizado
options.add_argument(
    "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

# Ignorar errores de certificado SSL (solo para testing)
options.add_argument("--ignore-certificate-errors")
```

---

## Gestión de sesiones concurrentes

El grid tiene **12 slots en total** (3 nodos × 4 sesiones). Para proyectos que crean muchas sesiones:

```python
import time
from selenium.common.exceptions import WebDriverException

def create_session_with_retry(hub_url: str, options, max_retries: int = 5):
    """
    Reintenta crear una sesión si no hay slots disponibles.
    El hub devuelve error si la cola de espera se agota (SE_SESSION_REQUEST_TIMEOUT).
    """
    for attempt in range(max_retries):
        try:
            return webdriver.Remote(command_executor=hub_url, options=options)
        except WebDriverException as e:
            if "Could not start a new session" in str(e) and attempt < max_retries - 1:
                wait = 2 ** attempt  # backoff exponencial: 1s, 2s, 4s, 8s...
                time.sleep(wait)
            else:
                raise
```

**Verificar slots disponibles antes de crear una sesión:**
```bash
curl -s http://admin:password@selenium-hub:4444/status | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  [print(f'{n[\"slots\"][0][\"stereotype\"][\"browserName\"]}: {sum(1 for s in n[\"slots\"] if not s[\"session\"])}/{len(n[\"slots\"])} libres') \
  for n in d['value']['nodes']]"
```

---

## Verificación y troubleshooting

### Verificar estado del grid

```bash
# Estado general (desde el VPS o desde un contenedor en la red)
curl -s http://admin:password@selenium-hub:4444/wd/hub/status

# Ver nodos registrados y sesiones activas
curl -s http://admin:password@selenium-hub:4444/status
```

### Verificar que el proxy Tor funciona

```bash
# Desde un contenedor en la red selenium-grid
curl --socks5 tor:9050 https://check.torproject.org/api/ip

# Respuesta esperada: {"IsTor":true,"IP":"..."}
```

### Renovar circuito Tor bajo demanda (`SIGNAL NEWNYM`)

El control port (`tor:9051`) permite solicitar activamente un nuevo circuito cuando el nodo de salida actual está bloqueado o caído:

```python
import asyncio

async def renew_tor_circuit() -> bool:
    """Solicita nuevo circuito Tor vía control port. Requiere CookieAuthentication 0 en torrc."""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection("tor", 9051), timeout=5
        )
        writer.write(b'AUTHENTICATE ""\r\n')
        await reader.read(1024)
        writer.write(b"SIGNAL NEWNYM\r\n")
        response = await reader.read(1024)
        writer.close()
        await writer.wait_closed()
        return b"250" in response
    except Exception:
        return False
```

Esperar 10–15s después del NEWNYM para que el nuevo circuito quede disponible. Tor impone un cooldown de 10s entre señales NEWNYM consecutivas.

```bash
# Verificar control port desde un contenedor en la red selenium-grid
echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc tor 9051
# Respuesta esperada: 250 OK (x2)
```

### Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Connection refused` en `selenium-hub:4444` | Contenedor no está en la red `selenium-grid` | Añadir `networks: selenium-grid: external: true` al compose del cliente |
| `401 Unauthorized` | Credenciales incorrectas | Verificar `SE_ROUTER_USERNAME`/`SE_ROUTER_PASSWORD` en el hub y en la URL del cliente |
| `Could not start a new session` | Sin slots disponibles | Esperar y reintentar, o reducir `SE_NODE_MAX_SESSIONS` para liberar RAM |
| `Session timeout` | Sesión idle superó `SE_NODE_SESSION_TIMEOUT` (300s) | Llamar a `driver.quit()` explícitamente; usar context managers |
| `ERR_SOCKS_CONNECTION_FAILED` | Nodo de salida Tor bloqueado o caído | Enviar `SIGNAL NEWNYM` al control port, esperar 12s, reintentar |
| Tor no rutea el tráfico | `--proxy-bypass-list` faltante o incorrecto | Añadir `--proxy-bypass-list=<-loopback>` a ChromeOptions |
| `429 Too Many Requests` | Rate limit de nginx superado (acceso externo) | Usar conexión interna, o reducir frecuencia de creación de sesiones |
| `Connection refused` en `tor:9051` | Control port no expuesto | Verificar `ControlPort 0.0.0.0:9051` y `CookieAuthentication 0` en `torrc` |

### Ver sesiones activas en tiempo real

```bash
# Desde el VPS
watch -n 2 'curl -s http://admin:password@selenium-hub:4444/status | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  sessions=[s for n in d[\"value\"][\"nodes\"] for s in n[\"slots\"] if s.get(\"session\")]; \
  print(f\"{len(sessions)} sesiones activas\")"'
```
