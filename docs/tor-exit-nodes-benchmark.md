# Tor Exit Nodes — Benchmark por país

Comparativa secuencial para identificar el pool de exit nodes óptimo.
Cada fase usa el mismo torrc base (IsolateDestAddr, MaxCircuitDirtiness 60) cambiando solo `ExitNodes`.

---

## Condiciones del test

| Parámetro | Valor |
|-----------|-------|
| Workers activos | 2 (synch=25), 1 (synch=15) |
| Duración por fase | ~4h (1 ciclo completo de worker) |
| Métrica principal | Ratio ciclos con NEWNYM / ciclos totales |
| Métrica secundaria | Tiempo promedio ciclos limpios (s) |
| Portal objetivo | `ais.usvisa-info.com` |

---

## Cómo aplicar cada fase

```bash
# 1. Editar torrc en docker_selenium_hub/ según la tabla de fases
# 2. Subir cambio al repo
git add torrc && git commit -m "test: tor exit nodes fase X/4 — {países}"
git push

# 3. En el VPS — git pull PRIMERO (evita capa cacheada de Docker)
git pull
docker compose build tor && docker compose up -d --force-recreate tor

# 4. Confirmar que Tor arrancó con la nueva config
docker compose logs tor | grep "ExitNode\|notice.*Open\|warn"

# 5. Registrar métricas tras ~4h de operación
docker compose logs --since 4h bot | grep -E "Navegación:|Circuito Tor|Error temporal|Error de navegación|Error crítico"
```

---

## Fases de test

### Fase 1 — `{us}` solo (baseline)
**torrc:** `ExitNodes {us}`

| Métrica | Valor |
|---------|-------|
| Período | 2026-03-10 ~4h |
| Workers | 0, 1, 2, 3, 4 |
| Total ciclos | 318 |
| Ciclos limpios | ~307 (est.) |
| % ciclos con NEWNYM (ERR_SOCKS nav) | 3.46% (11/318) |
| Avg tiempo todas las ciclos | 7.06s |
| 1x NEWNYM (ERR_SOCKS) | 11 |
| 2x NEWNYM | — |
| 3x NEWNYM | — |
| TemporaryNavException | presentes, pendiente de contar |
| Crashes de worker | 2 (incidentes de arranque paralelo) |
| Observaciones | Crashes causados por saturación del pool {us} durante arranques simultáneos de 4-5 workers. Fix aplicado: STAGGER_DELAY=60s en supervisor. Post-fix, 0 crashes en resto de sesión. |

---

### Fase 2 — `{us},{ca}`
**torrc:** `ExitNodes {us},{ca}`

| Métrica | Valor |
|---------|-------|
| Período | — |
| Workers | — |
| Total ciclos | — |
| Ciclos limpios | — |
| % ciclos con NEWNYM | — |
| Avg tiempo ciclo limpio | — |
| 1x NEWNYM (ERR_SOCKS) | — |
| 2x NEWNYM | — |
| 3x NEWNYM | — |
| TemporaryNavException | — |
| Crashes de worker | — |
| Observaciones | — |

---

### Fase 3 — `{us},{ca},{gb},{de}`
**torrc:** `ExitNodes {us},{ca},{gb},{de}`

| Métrica | Valor |
|---------|-------|
| Período | — |
| Workers | — |
| Total ciclos | — |
| Ciclos limpios | — |
| % ciclos con NEWNYM | — |
| Avg tiempo ciclo limpio | — |
| 1x NEWNYM (ERR_SOCKS) | — |
| 2x NEWNYM | — |
| 3x NEWNYM | — |
| TemporaryNavException | — |
| Crashes de worker | — |
| Observaciones | — |

---

### Fase 4 — `{us},{ca},{gb},{de},{nl},{au}` (config actual)
**torrc:** `ExitNodes {us},{ca},{gb},{de},{nl},{au}`

| Métrica | Valor |
|---------|-------|
| Período | 2026-03-09 16:27 → 17:20 (~53 min, parcial) |
| Workers | 1, 2 |
| Total ciclos | ~55 |
| Ciclos limpios | 41 |
| % ciclos con NEWNYM | ~25% |
| Avg tiempo ciclo limpio | 3.24s |
| 1x NEWNYM (ERR_SOCKS) | 6 |
| 2x NEWNYM | 2 |
| 3x NEWNYM | 1 |
| TemporaryNavException | 3 |
| Crashes de worker | 0 (worker 1 en login, no en navegación) |
| Observaciones | Datos parciales — sesión interrumpida a los 53 min. Buena estabilidad post-arranque. |

---

## Script de extracción de métricas

Para calcular automáticamente las métricas de una sesión de logs:

```bash
# Guardar logs de la sesión en archivo
docker compose logs --since 4h bot > /tmp/bot-fase-X.log

# Contar ciclos totales
grep -c "Navegación:" /tmp/bot-fase-X.log

# Contar ciclos limpios (sin NEWNYM en el mismo ciclo)
grep "Navegación:" /tmp/bot-fase-X.log | grep -v "retries" | wc -l

# Extraer todos los tiempos de navegación
grep -oP "Navegación: \K[\d.]+" /tmp/bot-fase-X.log

# Contar por tipo de NEWNYM
grep -c "Circuito Tor renovado (1/" /tmp/bot-fase-X.log   # veces que hubo al menos 1 NEWNYM
grep -c "Circuito Tor renovado (2/" /tmp/bot-fase-X.log   # al menos 2
grep -c "Circuito Tor renovado (3/" /tmp/bot-fase-X.log   # 3

# Contar TemporaryNavException
grep -c "título genérico\|mantenimiento" /tmp/bot-fase-X.log

# Contar crashes de worker
grep -c "Error crítico, terminando tarea" /tmp/bot-fase-X.log
```

---

## Resultado final (a completar)

| Fase | ExitNodes | % NEWNYM | Avg limpio | Crashes |
|------|-----------|----------|------------|---------|
| 1 | `{us}` | — | — | — |
| 2 | `{us},{ca}` | — | — | — |
| 3 | `{us},{ca},{gb},{de}` | — | — | — |
| 4 | `{us},{ca},{gb},{de},{nl},{au}` | ~25% | 3.24s | 0 |
