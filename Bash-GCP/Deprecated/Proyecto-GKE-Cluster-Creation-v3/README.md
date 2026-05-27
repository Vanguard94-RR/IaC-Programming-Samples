# GKE Cluster Creation Script - v3.6.0

## 📋 Overview

Script automatizado para la creación de clusters de Kubernetes (GKE) en Google Cloud Platform con soporte para Shared VPC, detección dinámica de rangos secundarios, obtención de versiones actualizadas y hardening de seguridad.

**Versión Actual:** v3.6.0-dynamic-ranges  
**Autor:** Erick Alvarado  
**Última Actualización:** 2026-02-11

---

## 🎯 Características Principales

### ✨ Nuevas en v3.6.0

- **Detección Dinámica de Rangos Secundarios**: Obtiene automáticamente los nombres de rangos de IP de la subred Shared VPC
- **Obtención de Versiones en Tiempo Real**: Consulta directamente GCP para obtener las versiones de Kubernetes más actualizadas
- **Validación Temprana**: Valida configuración antes de iniciar la creación del clúster (ahorra tiempo en fallos)

### Características Generales

- ✅ Creación de clusters GKE en modo privado o público
- ✅ Soporte para **Shared VPC** con múltiples subredes
- ✅ Configuración de **Cloud NAT** y Cloud Router
- ✅ Integración con **GKE Fleet**
- ✅ Aplicación de **hardening de seguridad**:
  - Políticas de seguridad (CVE-Canary, WAF, etc.)
  - Políticas SSL con TLS 1.2+
  - Despliegue de Twistlock (entornos PRO)
- ✅ Creación automática de **assets de infraestructura**:
  - Namespace `apps`
  - Service Accounts (Kubernetes e IAM)
  - Configuración de Workload Identity
- ✅ Manejo de múltiples canales de actualización: Rapid, Regular, Stable
- ✅ Logs detallados de todas las operaciones

---

## 📦 Requisitos y Dependencias

### Obligatorios

- **Google Cloud SDK** (`gcloud`): Herramienta CLI para GCP
- **kubectl**: Cliente de Kubernetes
- **jq**: Procesador JSON en línea de comandos
- **bash 5.0+**: Intérprete de shell

### Permisos GCP Requeridos

En el **proyecto de servicio** (donde se crea el clúster):
- `roles/container.admin`
- `roles/compute.admin`
- `roles/iam.securityAdmin`

En el **proyecto host** (Shared VPC, si aplica):
- `roles/compute.xpnAdmin`
- `roles/compute.networkAdmin`

### Instalación de Dependencias

#### Debian/Ubuntu
```bash
sudo apt-get update
sudo apt-get install -y jq
# gcloud y kubectl generalmente ya están instalados
```

#### RHEL/CentOS
```bash
sudo yum install -y jq
```

#### macOS
```bash
brew install jq
# gcloud se instala del Google Cloud SDK
```

---

## 🚀 Inicio Rápido

### 1. Preparación

```bash
# Clonar o descargar el repositorio
cd Proyecto-GKE-Cluster-Creation-v3

# Otorgar permisos de ejecución
chmod +x Create_K8s_Cluster-V3.6.sh
chmod +x test-*.sh  # (Opcional) Scripts de prueba
```

### 2. Configurar Credenciales GCP

```bash
# Autenticarse en GCP
gcloud auth login

# Establecer el proyecto por defecto
gcloud config set project PROJECT_ID
```

### 3. Ejecutar el Script

```bash
# Ejecución normal
./Create_K8s_Cluster-V3.6.sh

# Con redirección de salida a archivo (recomendado)
./Create_K8s_Cluster-V3.6.sh 2>&1 | tee cluster-creation.log
```

---

## 📝 Flujo de Ejecución Paso a Paso

### Paso 1: Recopilación de Parámetros
El script solicita información sobre:
- **ID del Proyecto GCP**
- **Nombre del Clúster**
- **Región y Zona**
- **Tipo de Máquina** (n2-standard-2 para PRO, n1-standard-2 para QA/UAT)
- **Número de Nodos**
- **Canal de Actualización** (stable, regular, rapid)
- **Tipo de Clúster** (Privado o Público)
- **Acceso API** (Por defecto o Completo)
- **Flota GKE** (qa, uat, pro)

### Paso 2: Configuración del Proyecto
- Habilita APIs necesarias (Kubernetes Engine, GKE Hub, Compute)
- Valida que el proyecto sea accesible

### Paso 3: Configuración de VPC
Opciones disponibles:
- **Opción 1**: Usar VPC existente del proyecto
- **Opción 2**: Crear nueva VPC local
- **Opción 3**: Usar VPC compartida (Shared VPC)

**Para Shared VPC:**
- Detecta dinámicamente los rangos secundarios (pods y servicios)
- Configura permisos IAM necesarios
- Valida que los rangos existan antes de continuar

### Paso 4: Cloud NAT (Opcional)
- Crea Cloud Router y Cloud NAT si no existen
- Obligatorio para PRO, opcional para QA/UAT

### Paso 5: Obtención de Versión de Cluster
- Consulta GCP para obtener versiones disponibles del canal seleccionado
- Usa versiones por defecto si falla la consulta

### Paso 6: Creación del Clúster GKE
- Ejecuta `gcloud container clusters create` con parámetros configurados
- Valida que el clúster se cree exitosamente

### Paso 7: Registro en Fleet
- Registra el clúster en la flota GKE correspondiente
- Configura Workload Identity

### Paso 8: Hardening de Seguridad (Opcional)
- Aplica políticas de seguridad según el ambiente:
  - **PRO**: 3 reglas (CVE-Canary, WAF, Default Deny)
  - **QA/UAT**: 7 reglas (adicionales para Apigee, ZScaler, etc.)
- Crea y aplica política SSL con TLS 1.2+
- Despliega Twistlock (solo PRO)

### Paso 9: Creación de Assets (Opcional)
- Crea namespace `apps`
- Crea Kubernetes Service Account
- Crea IAM Service Account
- Configura Workload Identity binding

### Paso 10: Resumen Final
Muestra información de:
- Proyecto, Clúster, Flota
- VPC, Cloud Router, Cloud NAT
- Workload Identity (si aplica)

---

## 🔧 Funciones Principales

### `get_cluster_versions(region, channel)`
Obtiene dinámicamente la versión de Kubernetes recomendada para un canal y región.

**Parámetros:**
- `region`: Región GCP (ej: us-central1)
- `channel`: Canal de actualización (rapid, regular, stable)

**Retorna:** Versión más actualizada disponible

**Ejemplo de salida:**
```
[VERSIONS] Obteniendo versiones disponibles de GKE para región: us-central1
[✓] Versión detectada para canal regular: 1.34.3-gke.1051003
```

### `detect_secondary_ranges(subnet, host_project)`
Detecta automáticamente los nombres de rangos secundarios en una subred Shared VPC.

**Parámetros:**
- `subnet`: Nombre de la subred
- `host_project`: Proyecto anfitrión de la Shared VPC

**Características:**
- Soporta variantes de nombres: pods/pod, services/servicios/service
- Valida que ambos rangos existan
- Proporciona CIDR de cada rango

**Ejemplo de salida:**
```
[SHARED-VPC] Detectando rangos secundarios en la subred 'gnp-cfdi-uat'...
[SHARED-VPC] Rangos secundarios encontrados:
  • pods → 10.88.8.0/21
  • servicios → 10.82.4.64/27
[✓] Rango de Pods detectado: pods (10.88.8.0/21)
[✓] Rango de Servicios detectado: servicios (10.82.4.64/27)
```

### `configure_shared_vpc_permissions(service_project, host_project)`
Configura los permisos IAM necesarios para usar Shared VPC.

### `apply_cluster_hardening()`
Aplica políticas de seguridad y endurecimiento según el ambiente.

### `deploy_twistlock()`
Despliega Twistlock DaemonSet en el clúster (entornos PRO).

---

## 📊 Variables Globales

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `project_id` | ID del proyecto GCP | gnp-cfdi-uat |
| `cluster_name` | Nombre del clúster | gke-gnp-cfdi-uat |
| `region` | Región GCP | us-central1 |
| `zone` | Zona GCP | us-central1-f |
| `machine_type` | Tipo de máquina | n2-standard-2 |
| `num_nodes` | Número de nodos | 2 |
| `channel` | Canal de actualización | regular |
| `VPC_NAME` | Nombre de la VPC | gnp-datalake-qa |
| `SUBNET_NAME` | Nombre de la subred | gnp-cfdi-uat |
| `PODS_RANGE_NAME` | Nombre del rango de pods | pods |
| `SERVICES_RANGE_NAME` | Nombre del rango de servicios | servicios |
| `cluster_version` | Versión del cluster | 1.34.3-gke.1051003 |
| `fleet_id` | ID de la flota | gnp-fleets-uat |

---

## 🧪 Scripts de Prueba

### Test de Detección de Rangos

```bash
./test-range-detection.sh gnp-cfdi-uat gnp-red-data-central us-central1
```

**Valida:**
- Conectividad a GCP
- Existencia de la subred
- Presencia de rangos secundarios
- Nombres correctos de rangos

### Test de Obtención de Versiones

```bash
./test-cluster-versions.sh
```

**Prueba:**
- Versión canal RAPID
- Versión canal REGULAR
- Versión canal STABLE
- Manejo de errores

---

## ⚠️ Troubleshooting

### Error: "jq: command not found"
```bash
# Instalar jq
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS
brew install jq          # macOS
```

### Error: "Secondary range does not exist"
El script ahora lo detecta automáticamente, pero si persiste:

1. Verificar nombres de rangos en GCP Console:
   ```
   VPC Network > Subnets > [subred] > Secondary IP ranges
   ```

2. Ejecutar test de detección:
   ```bash
   ./test-range-detection.sh SUBNET_NAME HOST_PROJECT REGION
   ```

### Error: Permisos insuficientes
Verificar roles en ambos proyectos:
```bash
# Proyecto de servicio
gcloud projects get-iam-policy PROJECT_ID --format=json

# Proyecto host (Shared VPC)
gcloud projects get-iam-policy HOST_PROJECT --format=json
```

### Error: Versión de cluster obsoleta
El script obtiene versiones dinámicamente. Si aún falla:

```bash
# Verificar versiones disponibles manualmente
gcloud container get-server-config --region=REGION --format=json | jq '.channels'
```

---

## 📋 Ejemplos de Uso

### Crear cluster en QA con Shared VPC

```bash
./Create_K8s_Cluster-V3.6.sh

# Responder a los prompts:
>> Ingrese el ID del Proyecto de GKE: gnp-cfdi-qa
>> Ingrese el Nombre del Clúster: gke-gnp-cfdi-qa
>> Ingrese la Región de GCP: us-central1
>> Ingrese la Zona de GCP: us-central1-f
>> Ingrese el Tipo de Máquina: n1-standard-2
>> Ingrese el Número de Nodos: 1
>> Seleccione Canal (stable, regular, rapid): regular
>> ¿Clúster privado? ([1]Privado, [2]Público): 1
>> Rango IP Control Plane: 172.19.0.0/28
>> ¿Qué desea hacer? ([1]Usar actual, [2]Crear nueva, [3]Usar Shared VPC): 3
>> ID del proyecto anfitrión: gnp-red-data-central
>> Nombre de VPC compartida: gnp-datalake-qa
>> Nombre de subnet compartida: gnp-cfdi-uat
```

### Output Esperado

```
========================================
     CREACION COMPLETADA
========================================
Proyecto: gnp-cfdi-qa
Clúster: gke-gnp-cfdi-qa
Flota: gnp-fleets-qa
VPC: gnp-datalake-qa
Cloud Router: gnp-cfdi-qa-router
Cloud NAT: gnp-cfdi-qa-nat
========================================
 Workload Identity
========================================
Namespace: apps
Kubernetes SA: apps-gke
IAM SA: apps-sa@gnp-cfdi-qa.iam.gserviceaccount.com
========================================
 Cluster listo en región us-central1
========================================
```

---

## 🔄 Cambios Recientes (v3.6.0)

### 2026-02-11
- ✅ Función `get_cluster_versions()` para obtención dinámica de versiones
- ✅ Integración de detección de versiones en flujo de creación
- ✅ Mejora de formato en resumen final de Workload Identity

### 2026-01-29
- ✅ Función `detect_secondary_ranges()` para detección dinámica de rangos
- ✅ Integración en creación de clúster con Shared VPC
- ✅ Soporte para ambigüedad "services" vs "servicios"
- ✅ Validación temprana de rangos antes de crear clúster

### 2026-01-27
- ✅ Corrección de sintaxis en comandos gcloud
- ✅ Separación de flags en múltiples líneas

---

## 📚 Documentación Oficial

- [GKE Release Notes](https://cloud.google.com/kubernetes-engine/docs/release-notes)
- [GKE API Reference](https://cloud.google.com/kubernetes-engine/docs/reference/rest)
- [Shared VPC Documentation](https://cloud.google.com/vpc/docs/shared-vpc)
- [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

---

## 📞 Soporte

Para problemas o sugerencias:
1. Revisar los logs generados (hardening_*.log)
2. Ejecutar scripts de test correspondientes
3. Verificar permisos IAM en GCP
4. Consultar documentación oficial de GCP

---

**Versión:** 3.6.0  
**Última Actualización:** 2026-02-11  
**Estado:** ✅ Producción
