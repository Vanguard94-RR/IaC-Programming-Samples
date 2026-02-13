# Google Cloud Pub/Sub Manager

Herramienta idempotente y segura para gestionar Topics y Subscripciones en Google Cloud Pub/Sub con soporte completo para arquitecturas cross-project.

## 📋 Características

- ✅ **Idempotente** - No falla si recursos ya existen
- ✅ **Cross-Project** - Crea topics en un proyecto y suscripciones en otro
- ✅ **Configuración YAML** - Define recursos declarativamente
- ✅ **Flexibilidad** - Mismo archivo para múltiples proyectos
- ✅ **Logs Organizados** - Integración con sistema de tickets
- ✅ **Validación** - Scripts de verificación incluidos
- ✅ **Seguro** - Validaciones en cada paso
- ✅ **Sin Expiración** - Suscripciones configuradas para no expirar

## 📦 Requisitos

```bash
# Instalar dependencias
sudo apt-get install -y google-cloud-sdk jq yq

# Autenticar con GCP
gcloud auth login
```

## 🚀 Uso Rápido

```bash
./create-pubsub-manager.sh
```

**El script solicita:**
1. **Ticket** (opcional) - Formato: CTASK0123456
2. **Proyecto GCP** - Proyecto objetivo para la operación
3. **Archivo de configuración** - Nombre del archivo YAML en `configs/`

## 📁 Estructura del Proyecto

```
Proyecto-Pub-Sub/
├── create-pubsub-manager.sh          # Script principal de creación
├── delete-subscriptions.sh           # Eliminar suscripciones
├── validate-stela-subscriptions.sh   # Validador específico STELA
├── README.md                         # Esta documentación
├── lib/
│   ├── common.sh                     # Funciones comunes y logs
│   └── gcp-operations.sh             # Operaciones Pub/Sub
├── configs/                          # Archivos de configuración YAML
│   ├── example-only-topics.yaml
│   ├── example-only-subs.yaml
│   ├── example-create-topics-then-subs.yaml
│   ├── example-multiple.yaml
│   └── example-cross-project.yaml
└── logs/                             # Logs de ejecución
```

## 📝 Configuración YAML

### Arquitectura 1: Topics y Subs en el Mismo Proyecto

```yaml
project: gnp-calculopagoudis-uat

resources:
  - type: topic
    name: mac.estados-cuenta.masivos.generar
    retention_days: 7
  
  - type: subscription
    name: mac.estados-cuenta.masivos.generar.consumer
    topic: mac.estados-cuenta.masivos.generar
    ack_deadline: 600
    retention_days: 7
```

**Ejecución:**
```bash
./create-pubsub-manager.sh
# Proyecto: gnp-calculopagoudis-uat
# Config: example-multiple.yaml
```

### Arquitectura 2: Topics en Proyecto A, Suscripciones en Proyecto B

#### Opción 2A: Un solo archivo, dos ejecuciones

```yaml
# example-create-topics-then-subs.yaml
project: gnp-ods-uat  # Proyecto base para suscripciones

resources:
  # Topics - se crean en gnp-stela-uat
  - type: topic
    name: eventos.tesoreria.pagos.recibidos
    topic_project: gnp-stela-uat  # Especifica proyecto diferente
    retention_days: 7
  
  - type: topic
    name: eventos.tesoreria.conciliacion
    topic_project: gnp-stela-uat
    retention_days: 14
  
  # Suscripciones - se crean en gnp-ods-uat
  - type: subscription
    name: ods.pagos.recibidos.consumer
    topic: projects/gnp-stela-uat/topics/eventos.tesoreria.pagos.recibidos
    topic_project: gnp-stela-uat
    ack_deadline: 600
    retention_days: 7
```

**Ejecución (2 pasos):**
```bash
# Paso 1: Crear topics en gnp-stela-uat
./create-pubsub-manager.sh
# Proyecto: gnp-stela-uat
# Config: example-create-topics-then-subs.yaml

# Paso 2: Crear suscripciones en gnp-ods-uat
./create-pubsub-manager.sh
# Proyecto: gnp-ods-uat
# Config: example-create-topics-then-subs.yaml
```

#### Opción 2B: Dos archivos separados

**example-only-topics.yaml**
```yaml
project: gnp-stela-uat

resources:
  - type: topic
    name: eventos.tesoreria.pagos.recibidos
    retention_days: 7
```

**example-only-subs.yaml**
```yaml
project: gnp-ods-uat

resources:
  - type: subscription
    name: ods.pagos.recibidos.consumer
    topic: projects/gnp-stela-uat/topics/eventos.tesoreria.pagos.recibidos
    topic_project: gnp-stela-uat
    ack_deadline: 600
```

**Ejecución:**
```bash
# Paso 1: Crear topics
./create-pubsub-manager.sh
# Proyecto: gnp-stela-uat
# Config: example-only-topics.yaml

# Paso 2: Crear suscripciones
./create-pubsub-manager.sh
# Proyecto: gnp-ods-uat
# Config: example-only-subs.yaml
```

### Parámetros Disponibles

#### Topics
| Parámetro | Tipo | Requerido | Default | Descripción |
|-----------|------|-----------|---------|-------------|
| `type` | string | ✅ | - | Debe ser `topic` |
| `name` | string | ✅ | - | Nombre del topic |
| `topic_project` | string | ❌ | project | Proyecto donde crear el topic |
| `retention_days` | int | ❌ | 7 | Días de retención de mensajes |

#### Subscriptions
| Parámetro | Tipo | Requerido | Default | Descripción |
|-----------|------|-----------|---------|-------------|
| `type` | string | ✅ | - | Debe ser `subscription` |
| `name` | string | ✅ | - | Nombre de la suscripción |
| `topic` | string | ✅ | - | Topic (local o ruta completa) |
| `topic_project` | string | ❌ | project | Proyecto del topic si es diferente |
| `ack_deadline` | int | ❌ | 600 | Tiempo en segundos para ACK |
| `retention_days` | int | ❌ | 7 | Días de retención de mensajes |

## 🔄 Idempotencia

El script es completamente idempotente - ejecuta múltiples veces sin problemas.

**Primera ejecución:**
```
ℹ Topic: eventos.tesoreria.pagos.recibidos (en proyecto: gnp-stela-uat)
✓ Creado
ℹ Subscription: ods.pagos.recibidos.consumer -> projects/gnp-stela-uat/topics/...
✓ Creada
✓ Completado: 2 creados, 0 errores
```

**Segunda ejecución:**
```
ℹ Topic: eventos.tesoreria.pagos.recibidos (en proyecto: gnp-stela-uat)
⚠ Ya existe
ℹ Subscription: ods.pagos.recibidos.consumer -> projects/gnp-stela-uat/topics/...
⚠ Ya existe
✓ Completado: 0 creados, 0 errores
```

## 📊 Logs

Los logs se guardan automáticamente:

- **Sin ticket:** `logs/pubsub-manager.log`
- **Con ticket:** `/home/admin/Documents/GNP/Tickets/<TICKET>/logs/pubsub-manager-<TICKET>-<timestamp>.log`

## 🔐 Permisos Cross-Project

Después de crear suscripciones cross-project, asigna permisos:

```bash
# Método 1: Por topic individual
gcloud pubsub topics add-iam-policy-binding TOPIC_NAME \
  --project=gnp-stela-uat \
  --member="serviceAccount:consumer@gnp-ods-uat.iam.gserviceaccount.com" \
  --role="roles/pubsub.viewer"

# Método 2: Múltiples topics en loop
for topic in eventos.tesoreria.pagos.recibidos eventos.tesoreria.conciliacion; do
  gcloud pubsub topics add-iam-policy-binding $topic \
    --project=gnp-stela-uat \
    --member="serviceAccount:consumer@gnp-ods-uat.iam.gserviceaccount.com" \
    --role="roles/pubsub.viewer"
done
```

## 📚 Casos de Uso Completos

### Caso 1: Todo en un Proyecto
**Escenario:** Crear topics y suscripciones en el mismo proyecto.

```bash
./create-pubsub-manager.sh
# Proyecto: gnp-calculopagoudis-uat
# Config: example-multiple.yaml
```

### Caso 2: Topics en Proyecto A, Suscripciones en Proyecto B
**Escenario:** Sistema STELA publica eventos, sistema ODS los consume.

```bash
# Paso 1: Crear topics en gnp-stela-uat
./create-pubsub-manager.sh
# Ticket: CTASK0123456
# Proyecto: gnp-stela-uat
# Config: example-create-topics-then-subs.yaml

# Paso 2: Crear suscripciones en gnp-ods-uat
./create-pubsub-manager.sh
# Ticket: CTASK0123456
# Proyecto: gnp-ods-uat
# Config: example-create-topics-then-subs.yaml

# Paso 3: Asignar permisos
for topic in eventos.tesoreria.pagos.recibidos eventos.tesoreria.conciliacion; do
  gcloud pubsub topics add-iam-policy-binding $topic \
    --project=gnp-stela-uat \
    --member="serviceAccount:consumer@gnp-ods-uat.iam.gserviceaccount.com" \
    --role="roles/pubsub.viewer"
done
```

### Caso 3: Solo Crear Topics (Suscripciones después)
**Escenario:** Preparar topics primero, suscripciones las crea otro equipo.

```bash
./create-pubsub-manager.sh
# Proyecto: gnp-stela-uat
# Config: example-only-topics.yaml
```

### Caso 4: Solo Crear Suscripciones (Topics ya existen)
**Escenario:** Topics ya existen, solo agregar nuevas suscripciones.

```bash
./create-pubsub-manager.sh
# Proyecto: gnp-ods-uat
# Config: example-only-subs.yaml
```

## ✅ Validación

Script para validar suscripciones STELA:

```bash
./validate-stela-subscriptions.sh
```

**Valida:**
- ✅ Existencia de suscripciones
- ✅ Topics correctos
- ✅ Configuración sin expiración
- ✅ Permisos IAM en topics

## 🗑️ Eliminación de Recursos

```bash
./delete-subscriptions.sh
```

## 🛠️ Troubleshooting

### Error: Topic no existe en proyecto diferente

```bash
# Verificar que el topic existe
gcloud pubsub topics describe TOPIC_NAME --project=gnp-stela-uat

# Si no existe, ejecutar primero la creación de topics
./create-pubsub-manager.sh
# Proyecto: gnp-stela-uat
# Config: tu-config.yaml
```

### Error: Permission denied (Cross-Project)

```bash
# Verificar permisos actuales
gcloud pubsub topics get-iam-policy TOPIC_NAME --project=gnp-stela-uat

# Asignar permisos
gcloud pubsub topics add-iam-policy-binding TOPIC_NAME \
  --project=gnp-stela-uat \
  --member="serviceAccount:SA@gnp-ods-uat.iam.gserviceaccount.com" \
  --role="roles/pubsub.viewer"
```

### Verificar configuración cross-project

```bash
# Ver suscripción
gcloud pubsub subscriptions describe SUB_NAME \
  --project=gnp-ods-uat \
  --format="value(topic)"

# Debe retornar: projects/gnp-stela-uat/topics/TOPIC_NAME
```

## 📖 Referencia Rápida

```bash
# Listar topics
gcloud pubsub topics list --project=<proyecto>

# Listar suscripciones
gcloud pubsub subscriptions list --project=<proyecto>

# Ver permisos de un topic
gcloud pubsub topics get-iam-policy TOPIC_NAME --project=<proyecto>

# Publicar mensaje de prueba
gcloud pubsub topics publish TOPIC_NAME --message="test" --project=<proyecto>

# Consumir mensajes
gcloud pubsub subscriptions pull SUB_NAME --limit=5 --project=<proyecto>
```

## 🏗️ Arquitectura del Script

```
┌─────────────────────────────────────────┐
│  create-pubsub-manager.sh               │
│  - Proceso interactivo                  │
│  - Validación de tickets                │
│  - Orquestación de recursos             │
│  - Soporte multi-proyecto               │
└───────────┬─────────────────────────────┘
            │
            ├──> lib/common.sh
            │    - Funciones de UI
            │    - Logs y validaciones
            │    - Gestión de tickets
            │
            └──> lib/gcp-operations.sh
                 - Operaciones idempotentes
                 - Validación de recursos
                 - Gestión cross-project
```

## 💡 Mejores Prácticas

1. **Usar archivos separados** para topics y suscripciones cuando trabajes cross-project
2. **Siempre validar** que los topics existen antes de crear suscripciones
3. **Asignar permisos IAM** inmediatamente después de crear recursos cross-project
4. **Usar tickets** para trazabilidad de cambios
5. **Probar con `pull`** después de crear para verificar conectividad

## 📄 Licencia

Uso interno GNP - Infraestructura GCP

---

**Última actualización:** Noviembre 2025  
**Mantenedor:** Equipo de Infraestructura GNP

## 🔧 Scripts Disponibles

### Scripts Genéricos (Recomendados)

| Script | Descripción | Uso |
|--------|-------------|-----|
| `create-pubsub-manager.sh` | Crear topics y suscripciones | Cualquier proyecto |
| `delete-pubsub-resources.sh` | Eliminar recursos desde YAML | Cualquier proyecto |
| `validate-pubsub-resources.sh` | Validar recursos desde YAML | Cualquier proyecto |

### Scripts Específicos (Legacy)

| Script | Descripción | Proyecto |
|--------|-------------|----------|
| `validate-stela-subscriptions.sh` | Validar suscripciones STELA | gnp-ods-uat |
| `delete-subscriptions.sh` | Eliminar suscripciones STELA | gnp-ods-uat |

## 🎯 Workflows Completos

### Workflow 1: Crear, Validar y Limpiar

```bash
# 1. Crear recursos
./create-pubsub-manager.sh
# Proyecto: gnp-calculopagoudis-uat
# Config: example-multiple.yaml

# 2. Validar recursos
./validate-pubsub-resources.sh
# Proyecto: gnp-calculopagoudis-uat
# Config: example-multiple.yaml

# 3. Eliminar si es necesario
./delete-pubsub-resources.sh
# Proyecto: gnp-calculopagoudis-uat
# Config: example-multiple.yaml
```

### Workflow 2: Cross-Project Completo

```bash
# Paso 1: Crear topics en proyecto source
./create-pubsub-manager.sh
# Ticket: CTASK0123456
# Proyecto: gnp-stela-uat
# Config: example-create-topics-then-subs.yaml

# Paso 2: Validar topics
./validate-pubsub-resources.sh
# Proyecto: gnp-stela-uat
# Config: example-create-topics-then-subs.yaml

# Paso 3: Crear suscripciones en proyecto consumer
./create-pubsub-manager.sh
# Ticket: CTASK0123456
# Proyecto: gnp-ods-uat
# Config: example-create-topics-then-subs.yaml

# Paso 4: Asignar permisos IAM
for topic in eventos.tesoreria.pagos.recibidos; do
  gcloud pubsub topics add-iam-policy-binding $topic \
    --project=gnp-stela-uat \
    --member="serviceAccount:consumer@gnp-ods-uat.iam.gserviceaccount.com" \
    --role="roles/pubsub.viewer"
done

# Paso 5: Validar suscripciones
./validate-pubsub-resources.sh
# Proyecto: gnp-ods-uat
# Config: example-create-topics-then-subs.yaml
```

### Workflow 3: Rollback Completo

```bash
# Eliminar suscripciones primero
./delete-pubsub-resources.sh
# Proyecto: gnp-ods-uat
# Config: tu-config.yaml

# Luego eliminar topics
./delete-pubsub-resources.sh
# Proyecto: gnp-stela-uat
# Config: tu-config.yaml
```

