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
    └── logs/
        └── workload_identity_20260212_214803.log
```

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
├── workload-identity.sh          # Script principal interactivo
├── workload-identity-registry.csv # Registro de operaciones (ignorado en git)
├── README.md                     # Este archivo
└── .gitignore                    # Archivos ignorados
```
