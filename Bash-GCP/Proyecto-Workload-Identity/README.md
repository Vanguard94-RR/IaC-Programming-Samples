# Workload Identity Manager

Script interactivo para configurar GCP Workload Identity entre Service Accounts de GCP y Kubernetes.

## Quick Start

```bash
# Ejecutar el script interactivo
./workload-identity.sh
```

## ¿Qué es Workload Identity?

Workload Identity permite que los pods de Kubernetes se autentiquen como Service Accounts de GCP sin necesidad de usar claves de cuenta de servicio. Este script automatiza la configuración:

1. **Crea el KSA** en el namespace destino (si no existe)
2. **Crea el IAM SA** en GCP (si no existe)
3. **Agrega el IAM binding** entre GCP SA y KSA
4. **Anota el KSA** para que los pods puedan acceder a servicios GCP

## Características

- ✅ **Interfaz Interactiva** - Menú intuitivo con colores y validación
- ✅ **Rastreo Completo** - Registro CSV de todas las operaciones
- ✅ **Organización por Tickets** - Logs y documentación automáticos
- ✅ **Validaciones Robustas** - Verificación de entrada y seguridad
- ✅ **Manejo de Errores** - Recuperación elegante con mensajes claros
- ✅ **Seguridad** - Permisos restrictivos en archivos sensibles
- ✅ **Performance** - Optimizaciones en búsquedas y actualizaciones
- ✅ **Código Humanizado** - Variables prefijadas, funciones documentadas

## Menú Principal

```
╔════════════════════════════════════════╗
║     WORKLOAD IDENTITY MANAGER          ║
╠════════════════════════════════════════╣
║  1) Configurar Workload Identity       ║
║  2) Verificar Workload Identity        ║
║  3) Eliminar Workload Identity         ║
║  4) Listar Workload Identities         ║
║  5) Ver Registro de Operaciones        ║
║  0) Salir                              ║
╚════════════════════════════════════════╝
```

## Opciones

### 1) Configurar Workload Identity
- Solicita Ticket/CTask para organizar logs
- Permite seleccionar proyecto y cluster
- Crea IAM SA si no existe
- Crea KSA si no existe
- Configura el binding y la anotación
- Registra la operación en CSV

### 2) Verificar Workload Identity
- Verifica si el IAM SA existe
- Verifica si el KSA existe
- Verifica la anotación del KSA
- Verifica el IAM binding

### 3) Eliminar Workload Identity
- Muestra configuraciones activas del registro
- Permite seleccionar qué eliminar:
  - Solo binding (mantiene KSA e IAM SA)
  - Binding + KSA (mantiene IAM SA)
  - Todo (Binding + KSA + IAM SA)
- Actualiza el registro con el estado

### 4) Listar Workload Identities
- Lista proyectos del registro
- Lista clusters del registro
- Muestra todos los KSAs con Workload Identity en un namespace

### 5) Ver Registro de Operaciones
- Muestra los últimos registros del CSV
- Incluye estado (activo/eliminado)

## Registro CSV

El script mantiene un archivo `workload-identity-registry.csv` con todas las operaciones:

```csv
Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status
2026-02-12 21:48:41,CTASK999999,gnp-app-qa,gke-cluster,us-central1,apps,ka-backend,sa-backend@gnp-app-qa.iam.gserviceaccount.com,activo
```

Estados posibles:
- `activo` - Configuración activa
- `eliminado-binding` - Solo se eliminó el binding
- `eliminado-binding-ksa` - Se eliminó binding + KSA
- `eliminado-todo` - Se eliminó todo (binding + KSA + IAM SA)

## Logs

Los logs se organizan por ticket:
```
Tickets/
└── CTASK999999/
    ├── logs/
    │   └── workload_identity_20260212_214803.log
    ├── docs/                 # Documentación de la operación
    └── scripts/              # Scripts relacionados
```

## Seguridad

- 🔒 **Archivos CSV** - Permisos restrictivos (600) en archivos con datos sensibles
- 🔒 **Validación de Entrada** - Validación de formato para:
  - IDs de proyecto GCP
  - Emails de IAM Service Accounts
  - Nombres de Kubernetes (DNS-1123)
  - Namespaces existentes
- 🔒 **Manejo de Errores** - Trap handlers para cleanup seguro
- 🔒 **Inyección de Comandos** - Variables siempre quoted

## Requisitos

- `gcloud` CLI configurado y autenticado
- `kubectl` configurado
- Permisos para:
  - Crear/modificar IAM Service Accounts
  - Agregar IAM bindings
  - Crear/modificar Kubernetes Service Accounts
  - Conectarse a clusters GKE

## Estructura

```
Proyecto-Workload-Identity/
├── workload-identity.sh          # Script principal interactivo (1500+ líneas)
├── workload-identity-registry.csv # Registro de operaciones (ignorado en git)
├── README.md                     # Este archivo
└── .gitignore                    # Archivos ignorados
```

## Optimizaciones Implementadas

### Performance
- ✅ Actualización CSV con awk (single-pass en O(n) en vez de O(n²))
- ✅ Búsquedas consolidadas en una sola pasada
- ✅ Reutilización de variables

### Robustez
- ✅ `set -euo pipefail` para manejo seguro de errores
- ✅ Trap handlers para cleanup en caso de fallo
- ✅ Validación completa de entrada
- ✅ Manejo graceful de casos edge

### Seguridad
- ✅ Permisos CSV 600 (solo lectura/escritura propietario)
- ✅ Variables siempre quoted
- ✅ Validación de formato de IDs y nombres
- ✅ Sanitización de entrada de usuario

### Código
- ✅ Variables globales con prefijo `G_`
- ✅ Funciones documentadas con propósito claro
- ✅ Nomenclatura consistente
- ✅ Logging en todos los puntos críticos
- ✅ Errores con contexto de línea

