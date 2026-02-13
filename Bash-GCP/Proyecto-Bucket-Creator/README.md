# Proyecto-Bucket-Creator

**Script bash para crear buckets GCP** con especificaciones estándar según políticas de GNP.

## 🚀 Quick Start

```bash
# 1. Hacer ejecutable
chmod +x GCPBucketCreator.sh

# 2. Ejecutar script
./GCPBucketCreator.sh

# 3. Seguir instrucciones interactivas
```

## 📋 Características

- ✅ **Crear buckets** GCP con especificaciones estándar
- ✅ **Ubicación**: us-central1 (región única)
- ✅ **Clase de almacenamiento**: Standard
- ✅ **Acceso uniforme**: Habilitado en todos los buckets
- ✅ **Prevención de acceso público**: Habilitada por defecto

## 📦 Requisitos

- **Google Cloud SDK**: https://cloud.google.com/sdk/docs/install
  - `gcloud` CLI
- **Bash 5.1+** (probado en 5.1.16)
- **Autenticación GCP**: `gcloud auth login`

### Verificar requisitos

```bash
gcloud version
bash --version
gcloud auth list
```

## 🛠️ Uso

### Modo Interactivo

El script solicita información de forma interactiva:

```bash
./GCPBucketCreator.sh
```

Se te pedirá:

1. **Project ID**: Tu proyecto GCP (default: my-project)
2. **Bucket Name**: Nombre del bucket (default: my-bucket)

### Ejemplo de Ejecución

```
 >>----GNP Cloud Infrastructure Team----<<
 >>-------Standard Bucket Creation------<<

This is going to create a bucket with the following specs:
Single Region: us-central1
Storage Class: Standard
Bucket Level Access: Uniform
Public Access Prevention: True

Enter Your GCP Project ID (Default: my-project): my-gcp-project
Enter Your Bucket Name (Default: my-bucket): my-data-bucket

Creating Bucket...
```

## 🔧 Especificaciones de Buckets

| Propiedad                                | Valor        | Notas                          |
| ---------------------------------------- | ------------ | ------------------------------ |
| **Ubicación**                     | us-central1  | Región única                 |
| **Clase de almacenamiento**        | Standard     | Para datos frecuentes          |
| **Acceso uniforme**                | Configurable | Uniform o Fine-grained         |
| **Prevención de acceso público** | Habilitada   | Protección contra exposición |
| **Versioning**                     | Manual       | Puede habilitarse después     |

## 🔐 Modos de Control de Acceso

### Uniform (Estándar)

- Control centralizado a nivel de bucket
- IAM es la única forma de otorgar acceso
- Recomendado para seguridad y auditoría
- **Configuración estándar del script**

## 📁 Estructura del Proyecto

```
Proyecto-Bucket-Creator/
├── GCPBucketCreator.sh          # Script principal
├── README.md                     # Esta documentación
├── INSTALACION.md                # Guía de setup
├── EJEMPLOS.md                   # Casos de uso
└── Notas                          # Políticas originales
```

## 📝 Ejemplo de Uso Completo

```bash
# 1. Clonar o descargar
cd Proyecto-Bucket-Creator

# 2. Hacer ejecutable
chmod +x GCPBucketCreator.sh

# 3. Ejecutar
./GCPBucketCreator.sh

# Responder prompts:
# Project ID: production-project
# Bucket Name: app-data-prod
# Access Control: Uniform

# 4. Verificar bucket creado
gsutil ls gs://app-data-prod
gsutil stat gs://app-data-prod
```

## 🔍 Verificación Post-Creación

```bash
# Listar buckets
gsutil ls

# Ver detalles del bucket
gsutil stat gs://my-bucket-name

# Ver configuración de acceso uniforme
gcloud storage buckets describe gs://my-bucket-name \
  --format="value(uniform_bucket_level_access)"

# Ver configuración de prevención de acceso público
gcloud storage buckets describe gs://my-bucket-name \
  --format="value(public_access_prevention)"
```

## 🎨 Código de Colores

El script utiliza colores para mejor legibilidad:

- 🟢 **Verde**: Información principal y completada
- 🔵 **Azul**: Información secundaria
- 🟡 **Amarillo**: Advertencias e instrucciones
- ⚪ **Blanco**: Contenido normal

## ⚠️ Consideraciones Importantes

### Nombres de Buckets

- **Globalmente únicos** en GCP
- No puede contener el nombre de otro bucket existente
- Se recomienda: `gnp-{proyecto}-{ambiente}`

### Acceso Público

- **Prevenido por defecto** (Public Access Prevention = True)
- Protege contra exposición accidental
- Debe deshabilitarse explícitamente si se necesita

### Ubicación

- **Fija en us-central1** para este script
- Para otras regiones, usa `gcloud storage` directamente

## 📚 Próximos Pasos

1. ✅ [Instalación](INSTALACION.md) - Configurar ambiente
2. ✅ [Ejemplos](EJEMPLOS.md) - Casos de uso prácticos
3. ✅ Crear buckets según necesidades
4. ✅ Configurar permisos y accesos

## 🐛 Troubleshooting

### "Project not found"

```bash
# Verificar proyecto
gcloud config list

# Listar proyectos
gcloud projects list

# Cambiar proyecto
gcloud config set project PROJECT_ID
```

### "Bucket name already exists"

- Nombre ya está en uso globalmente
- Elige nombre diferente y más específico

### "Permission denied"

- Usuario debe tener rol `roles/storage.admin` en el proyecto
- Verificar permisos en IAM Console

### "gcloud: command not found"

- Instalar Google Cloud SDK
- Agregar a PATH si es necesario

## 📝 Licencia

Proyecto GNP Infrastructure - 2026

---

**Versión**: 1.0.0
**Autor Original**: Manuel Cortes
**Última actualización**: 2026-02-13
