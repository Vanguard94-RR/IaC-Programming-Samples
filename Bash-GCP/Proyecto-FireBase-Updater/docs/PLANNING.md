# Proyecto-FireBase-Updater — Planning Doc

## Problema

Tareas tipo CTASK0366118 requieren operaciones sobre Firebase Realtime Database (RTDB) mediante
REST API con autenticación gcloud. Hoy se ejecutan con bash scripts ad-hoc por ticket.

**Dolor actual:**
- Bash scripts por ticket = no reutilizables, no parametrizables
- Validación manual pre/post
- Sin backup automático verificado
- Requiere ingeniero que sepa construir el script desde cero
- Sin idempotencia garantizada

---

## Objetivo

Micro-agente CLI interactivo, idempotente, que cualquier ingeniero GCP pueda correr
**sin escribir código** para ejecutar operaciones RTDB estándar.

**Criterios de éxito:**
- Ingenieros GCP sin conocimiento previo del ticket pueden operar el agente
- Salida ✓/✗ por fase, idéntica al formato actual de tickets
- Falla antes de escribir si pre-validate no pasa
- Reanudar ejecución es seguro (idempotente)
- Funciona en: Cloud Shell, Linux local, macOS local

---

## Alcance

### Operaciones soportadas (MVP)

| Op      | HTTP  | Descripción                                |
|---------|-------|--------------------------------------------|
| `put`   | PUT   | Insertar/reemplazar nodo completo           |
| `patch` | PATCH | Actualizar campos sin borrar nodo           |
| `get`   | GET   | Leer nodo (solo lectura, sin backup)        |
| `delete`| DELETE| Eliminar nodo (con backup obligatorio)      |

### Fuera de alcance (MVP)

- Firebase Auth (usuarios, reglas de seguridad)
- Firestore (distinto producto)
- Firebase Storage
- Múltiples operaciones en batch (v2)

---

## Stack técnico

| Componente     | Decisión      | Razón                                              |
|----------------|---------------|----------------------------------------------------|
| Lenguaje       | **Go**        | Binario estático, no deps runtime, Cloud Shell OK  |
| Auth           | `gcloud auth print-access-token` | Ya en env del ingeniero    |
| HTTP           | `net/http` stdlib | Sin deps externas                              |
| CLI interactivo| `bufio.Scanner` + `os.Stdin` | Sin deps, portable       |
| JSON           | `encoding/json` stdlib | Suficiente para RTDB REST                |
| Build          | `Makefile`    | `make build` → binario listo                       |

**Fallback Python:** Si el entorno no tiene Go, `firebase_updater.py` con stdlib únicamente
(`urllib.request`, `json`, `subprocess` para gcloud token).

---

## Arquitectura

```
firebase-updater (binario)
│
├── cmd/main.go                  ← Entry point, orquesta fases
│
├── internal/config/
│   └── config.go                ← Struct Config, validación básica
│
├── internal/auth/
│   └── gcloud.go                ← exec gcloud auth print-access-token
│
├── internal/firebase/
│   ├── client.go                ← HTTP client (GET/PUT/PATCH/DELETE)
│   ├── backup.go                ← Descarga y guarda backup JSON local
│   └── validate.go              ← Comparación post-ejecución
│
└── internal/interactive/
    └── prompt.go                ← Prompts CLI con defaults y confirmación
```

---

## Flujo de ejecución

```
START
  │
  ▼
[PHASE 0 — INPUT]
  Prompt interactivo: DB, path, operación, nodo, payload
  Aceptar flags --db --path --node --op --payload-file (no-interactivo)
  │
  ▼
[PHASE 1 — PRE-VALIDATE]
  1. gcloud auth token válido
  2. Proyecto accesible (gcloud projects describe)
  3. Firebase endpoint responde HTTP 200
  4. Para PUT: nodo NO existe (idempotencia)
     Para PATCH: nodo existe
     Para DELETE: nodo existe
  5. Backup del nodo padre → backup_{timestamp}.json
  │  Exit 1 si cualquier check falla
  ▼
[PHASE 2 — CONFIRM]
  Mostrar resumen: DB, path, op, payload
  "¿Confirmar ejecución? [s/N]:"
  │
  ▼
[PHASE 3 — EXECUTE]
  PUT/PATCH/DELETE → Firebase REST API
  Guardar respuesta cruda en logs/
  │
  ▼
[PHASE 4 — VALIDATE]
  GET nodo post-ejecución
  Comparar con payload enviado (campos esperados presentes)
  Para DELETE: verificar 404/null
  Reporte ✓/✗ por campo
  │
  ▼
[OUTPUT]
  ==============================
  {TICKET_ID} — Firebase Updater
  DB: {db}.firebaseio.com
  Path: {path}
  ==============================
  [PRE-VALIDATE] ✓ 5/5
  [EXECUTE]      ✓ HTTP 200
  [VALIDATE]     ✓ 4/4 campos
  ==============================
  Status: COMPLETED | FAILED
  Backup: logs/backup_{ts}.json
  ==============================
```

---

## Idempotencia

| Op      | Comportamiento idempotente                              |
|---------|---------------------------------------------------------|
| `put`   | Si nodo existe con mismo payload → skip, reportar OK    |
| `put`   | Si nodo existe con diferente payload → FAIL en pre-val  |
| `patch` | PATCH es naturalmente idempotente si payload es igual   |
| `delete`| Si nodo ya no existe → skip, reportar OK                |
| `get`   | Siempre idempotente                                     |

Regla: **pre-validate detecta estado actual → decide si proceder**.
Nunca sobreescribir sin confirmación explícita.

---

## Estructura de archivos del proyecto

```
Proyecto-FireBase-Updater/
├── cmd/
│   └── main.go
├── internal/
│   ├── auth/
│   │   └── gcloud.go
│   ├── firebase/
│   │   ├── client.go
│   │   ├── backup.go
│   │   └── validate.go
│   ├── interactive/
│   │   └── prompt.go
│   └── config/
│       └── config.go
├── docs/
│   ├── PLANNING.md              ← este archivo
│   └── USAGE.md                 ← guía operacional (post-build)
├── testdata/
│   └── sample_payload.json      ← ejemplo de payload para CTASK0366118
├── go.mod
├── Makefile
└── README.md
```

---

## Contrato de Config (struct)

```go
type Config struct {
    TicketID   string          // CTASK0366118
    ProjectID  string          // gnp-appagentes-uat
    FirebaseDB string          // gnp-appagentes-uat
    Path       string          // SectionsView/wallet/aperturaGmm
    Node       string          // reembolsosv2
    Operation  string          // put | patch | get | delete
    Payload    json.RawMessage // contenido a escribir
    LogDir     string          // ./logs/ por default
    DryRun     bool            // print sin ejecutar
}
```

---

## Validación post-ejecución

El validador compara el nodo resultante contra el payload enviado:

1. **Tipo correcto** — bool, string, number, object
2. **Campos presentes** — todos los keys del payload existen
3. **Whitelist** — acepta dict `{"1":...}` O array `[null,...]` (Firebase auto-convierte)
4. **Integridad del padre** — nodos hermanos no cambiaron

---

## Payload de ejemplo (CTASK0366118)

```json
{
  "pilot": true,
  "show": true,
  "timestamp": 1770150847438,
  "whitelist": {
    "1": "mariomontalvo@segurosmontalvo.com",
    "2": "Agente@desarrollo.com"
  }
}
```

---

## Makefile targets

```makefile
build:      # go build → bin/firebase-updater
test:       # go test ./...
install:    # cp bin/firebase-updater /usr/local/bin/
clean:      # rm -rf bin/ logs/
run:        # go run cmd/main.go (dev)
```

---

## Modo no-interactivo (CI / automatización)

```bash
firebase-updater \
  --ticket CTASK0366118 \
  --project gnp-appagentes-uat \
  --db gnp-appagentes-uat \
  --path "SectionsView/wallet/aperturaGmm" \
  --node reembolsosv2 \
  --op put \
  --payload-file payload.json \
  --yes   # skip confirmación interactiva
```

---

## Fases de implementación

### Fase 1 — Core MVP (semana 1)

- [ ] `go.mod` init (`firebase-updater`)
- [ ] `config.go` — struct + parse flags + validate
- [ ] `gcloud.go` — exec token
- [ ] `client.go` — GET/PUT/PATCH/DELETE con token
- [ ] `backup.go` — descarga y guarda JSON
- [ ] `prompt.go` — prompts interactivos básicos
- [ ] `main.go` — orquesta 4 fases, output formato ticket
- [ ] `Makefile` — build, run, clean
- [ ] `testdata/sample_payload.json`

### Fase 2 — Validación robusta (semana 1-2)

- [ ] `validate.go` — comparación payload vs GET resultado
- [ ] Manejo whitelist dict/array (Firebase quirk)
- [ ] Integridad de nodos hermanos
- [ ] `--dry-run` flag

### Fase 3 — UX y distribución (semana 2)

- [ ] `USAGE.md` — guía operacional para ingenieros
- [ ] `README.md` — instalación + ejemplo completo
- [ ] `make install` funcional en Cloud Shell
- [ ] Tests unitarios `*_test.go`

---

## Riesgos y mitigaciones

| Riesgo                              | Mitigación                                    |
|-------------------------------------|-----------------------------------------------|
| Firebase convierte `{"1":...}` → array | validate.go acepta ambos formatos         |
| Token gcloud expira mid-ejecución   | Refrescar token antes de cada fase            |
| Path con caracteres especiales      | URL encode en client.go                       |
| Ingenieros sin Go instalado         | `make install` descarga binario pre-compilado |
| Cloud Shell sin permisos escritura  | Logs en `/tmp/firebase-updater/` como fallback|

---

## Referencias

- Firebase REST API: `https://{db}.firebaseio.com/{path}.json`
- Auth: `gcloud auth print-access-token`
- Ticket base: CTASK0366118 — `Tickets/CTASK0366118/scripts/`
- Chatmode guía: `.github/chatmodes/tareas-tickets-2.chatmode.md`
