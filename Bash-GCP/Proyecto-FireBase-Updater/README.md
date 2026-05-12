# Firebase Updater

Micro-agente CLI interactivo para operaciones sobre Firebase Realtime Database (RTDB).

Reemplaza bash scripts ad-hoc por ticket con un único binario parametrizable, idempotente,
operable por cualquier ingeniero GCP sin escribir código.

## Casos de uso

- Insertar nodo nuevo (PUT) con backup automático
- Actualizar campos de nodo existente (PATCH)
- Eliminar nodo con backup previo obligatorio
- Leer y volcar nodo a JSON (GET)

## Requisitos

- `gcloud` autenticado (`gcloud auth login`)
- Permisos Firebase Editor en el proyecto GCP
- Go 1.21+ **o** binario pre-compilado (ver Instalación)

## Instalación rápida (Cloud Shell / Linux)

```bash
# Opción A — compilar desde fuente
git clone <repo>
cd Proyecto-FireBase-Updater
make build
make install   # copia a /usr/local/bin/firebase-updater

# Opción B — binario pre-compilado (pendiente releases)
# curl -L <release-url> -o firebase-updater && chmod +x firebase-updater
```

## Uso interactivo

```bash
firebase-updater
```

El agente pregunta: ticket ID, proyecto, DB, path, nodo, operación, payload.

## Uso no-interactivo

```bash
firebase-updater \
  --ticket CTASK0366118 \
  --project gnp-appagentes-uat \
  --db gnp-appagentes-uat \
  --path "SectionsView/wallet/aperturaGmm" \
  --node reembolsosv2 \
  --op put \
  --payload-file payload.json \
  --yes
```

## Salida esperada

```
========================================
CTASK0366118 — Firebase Updater
DB: gnp-appagentes-uat.firebaseio.com
Path: SectionsView/wallet/aperturaGmm/reembolsosv2
Op: PUT
========================================
[PRE-VALIDATE] ✓  5/5 — backup guardado
[EXECUTE]      ✓  HTTP 200
[VALIDATE]     ✓  4/4 campos correctos
========================================
Status: COMPLETED
Backup: logs/backup_CTASK0366118_20260511_143022.json
========================================
```

## Documentación

- [PLANNING.md](docs/PLANNING.md) — diseño completo, arquitectura, fases de implementación
