# Proyecto: Creación de Subnet en Shared VPC

## Descripción
Script automatizado para crear subnets en una Shared VPC existente en Google Cloud Platform.

## Características
- ✅ Creación de subnets en Shared VPC
- ✅ Validación de permisos y recursos
- ✅ Configuración de rangos IP secundarios (para GKE)
- ✅ Soporte para múltiples regiones
- ✅ Logs detallados de operaciones

## Requisitos
- Google Cloud SDK (gcloud) instalado
- Permisos en el Host Project de la Shared VPC:
  - `roles/compute.networkAdmin` o `roles/compute.securityAdmin`
- Permisos en el Service Project (si aplica):
  - `roles/compute.networkUser`

## Estructura del Proyecto
```
Proyecto-Shared-VPC-Subnet/
├── README.md
├── create-subnet.sh           # Script principal
├── configs/
│   └── subnet-config.example  # Ejemplo de configuración
├── lib/
│   ├── validators.sh          # Funciones de validación
│   └── utils.sh               # Utilidades comunes
└── logs/                      # Directorio de logs
```

## Uso

### Modo Interactivo
```bash
./create-subnet.sh
```

### Modo con Configuración
```bash
./create-subnet.sh --config configs/subnet-config.yaml
```

## Parámetros de Configuración

### Básicos
- **Host Project ID**: Proyecto que contiene la Shared VPC
- **VPC Network Name**: Nombre de la VPC compartida
- **Subnet Name**: Nombre de la subnet a crear
- **Region**: Región de GCP (ej: us-central1)
- **IP Range**: Rango CIDR principal (ej: 10.0.0.0/24)

### Opcionales
- **Secondary Ranges**: Rangos IP secundarios para Pods y Services (GKE)
- **Private Google Access**: Habilitar acceso privado a APIs de Google
- **Flow Logs**: Habilitar logs de flujo de red

## Ejemplos

### Subnet Simple
```bash
Host Project: gnp-shared-vpc-host
VPC Network: gnp-vpc-shared
Subnet Name: subnet-app-prod
Region: us-central1
IP Range: 10.10.0.0/24
```

### Subnet para GKE
```bash
Host Project: gnp-shared-vpc-host
VPC Network: gnp-vpc-shared
Subnet Name: subnet-gke-prod
Region: us-central1
IP Range Primary: 10.20.0.0/24
Secondary Range (Pods): 10.21.0.0/16
Secondary Range (Services): 10.22.0.0/20
```

## Notas
- La subnet se crea en el Host Project de la Shared VPC
- Los Service Projects pueden usar la subnet después de ser attachados
- Verificar que los rangos IP no se superpongan con subnets existentes

## Logs
Los logs se guardan en: `logs/subnet-creation-YYYYMMDD-HHMMSS.log`

## Autor
Erick Alvarado

## Versión
1.0.0
