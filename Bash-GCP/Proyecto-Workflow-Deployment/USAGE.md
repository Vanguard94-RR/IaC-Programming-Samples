# Workflow Deployment - Guía de Uso

Despliega workflows desde GitLab a **Google Cloud Workflows** de forma fácil e interactiva.

## 🚀 Instalación

```bash
make install
```

Requiere:
- Python 3.8+
- pyyaml, requests
- gcloud CLI

---

## 📋 Tres formas de usar

### 1️⃣ **Modo Interactivo Python (RECOMENDADO)** ⭐

La forma más amigable y completa:

```bash
make interactive
```

O directamente:

```bash
python3 workflow-deploy-interactive.py
```

**Características:**
- ✅ Interfaz paso a paso
- ✅ Validación en tiempo real
- ✅ Preview antes de desplegar
- ✅ Opción de volver atrás
- ✅ Historial de despliegues
- ✅ Manejo de errores claro

**Flujo:**
```
Paso 1: Elegir fuente GitLab
  → URL completa o componentes separados

Paso 2: Configurar destino GCP
  → Nombre del workflow
  → Project ID
  → Región

Paso 3: Opciones adicionales
  → Normal / DRY-RUN / SKIP-VALIDATION

Paso 4: Confirmación con preview
  → Revisar y ejecutar
```

---

### 2️⃣ **Modo Interactivo Bash**

Interfaz ligera similar a workload-identity.sh:

```bash
make interactive-bash
```

O directamente:

```bash
bash workflow-deploy-interactive.sh
```

**Características:**
- ✅ Mismo flujo que Python
- ✅ Más ligero
- ✅ Sin dependencias Python
- ✅ Interfaz familiar (colores y menús)

---

### 3️⃣ **Modo CLI (Línea de Comandos)**

Para automatización o scripts:

```bash
make deploy \
  URL='https://gitlab.com/grupo/proyecto/-/blob/main/workflow.yml' \
  NAME='workflow-name' \
  PROJECT='gcp-project-id'
```

**Parámetros requeridos:**
- `URL` - URL completa del archivo en GitLab
- `NAME` - Nombre del workflow en GCP
- `PROJECT` - Project ID de GCP

**Parámetros opcionales:**
- `LOCATION` - Región GCP (default: us-central1)
- `DRY_RUN=1` - Simular sin desplegar
- `SKIP_VALIDATION=1` - Omitir validación

**Ejemplos:**

```bash
# Despliegue básico
make deploy \
  URL='https://gitlab.com/gitgnp/repo/-/blob/main/workflow.yml' \
  NAME='my-workflow' \
  PROJECT='gnp-project-qa'

# Con simulación
make deploy \
  URL='...' \
  NAME='test' \
  PROJECT='proj' \
  DRY_RUN=1

# Con ubicación específica
make deploy \
  URL='...' \
  NAME='wf' \
  PROJECT='proj' \
  LOCATION='southamerica-east1'
```

---

## 📝 Formato de URL GitLab

```
https://gitlab.com/GRUPO/PROYECTO/-/blob/RAMA/RUTA/ARCHIVO.yml
```

**Ejemplos válidos:**
```
https://gitlab.com/gitgnp/cotizadores/gke-gnp-danios-config-back-end/-/blob/main/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml

https://gitlab.com/myorg/myrepo/-/blob/feature-branch/workflows/my-workflow.yml

https://gitlab.com/infrateam/workflows/-/blob/v1.0.0/production/workflow.yml?ref_type=tags
```

> El script automáticamente extracta: proyecto, rama/tag, y ruta del archivo

---

## 🔍 Modo Uso Directo (Python)

Si prefieres usar el script Python directamente sin Makefile:

```bash
# Requerir token
export GITLAB_TOKEN=$(cat ../../../../PersonalGitLabToken)

# Con URL completa
python3 workflow-deploy.py \
  --url "https://gitlab.com/grupo/proyecto/-/blob/main/workflow.yml" \
  --name mi-workflow \
  --project gcp-project-id

# Con componentes separados
python3 workflow-deploy.py \
  --gitlab-project grupo/proyecto \
  --branch main \
  --path ruta/workflow.yml \
  --name mi-workflow \
  --project gcp-project-id

# Ver ayuda
python3 workflow-deploy.py --help
```

---

## 📊 Comparativa de Opciones

| Característica | Python Interactive | Bash Interactive | CLI |
|---|---|---|---|
| **Interfaz amigable** | ⭐⭐⭐ | ⭐⭐ | ❌ |
| **Preview antes de desplegar** | ✅ | ✅ | ❌ |
| **Validación en tiempo real** | ✅ | ✅ | ✅ |
| **Historial de despliegues** | ✅ | ✅ | ❌ |
| **Dependencias externas** | Python | Bash | Python |
| **Automatización** | ⭐ | ⭐ | ⭐⭐⭐ |
| **Uso en scripts** | ❌ | ❌ | ✅ |

---

## 📚 Otros Comandos

```bash
# Ver logs en tiempo real
make logs

# Limpiar logs
make clean

# Ver ayuda
make help
```

---

## 🔄 Flujo Completo (Modo Interactivo)

```
$ make interactive

╔══════════════════════════════════════════════════════════════════╗
║    Workflow Deployment Manager - Modo Interactivo              ║
╚══════════════════════════════════════════════════════════════════╝

════════════════════════════════════════════════
║ Paso 1: Fuente de GitLab
════════════════════════════════════════════════

¿De dónde descargar el workflow?

  1) Ingresar URL completa de GitLab
  2) Ingresar detalles por separado (proyecto, rama, archivo)
  0) Cancelar

Opción: 1

URL de GitLab: https://gitlab.com/gitgnp/repo/-/blob/main/workflow.yml

[... más pasos ...]

════════════════════════════════════════════════
║ Paso 4: Confirmación
════════════════════════════════════════════════

Resumen de la configuración:

Fuente (GitLab):
  URL: https://gitlab.com/gitgnp/repo/-/blob/main/workflow.yml

Destino (GCP):
  Workflow: my-workflow
  Proyecto: gnp-project-qa
  Región: us-central1

Opciones:
  Modo: ✓ Normal
  Validación: Habilitada

¿Qué deseas hacer?

  1) Continuar con el despliegue
  2) Volver al paso anterior
  0) Cancelar todo

Opción: 1

════════════════════════════════════════════════
║ Ejecutando Despliegue
════════════════════════════════════════════════

✓ Despliegue completado exitosamente
```

---

## 🏆 Recomendaciones

| Caso de uso | Opción recomendada |
|---|---|
| 👤 Primer uso / Usuario no técnico | **Python Interactivo** |
| 🔧 Familiar con herramientas | **Python Interactivo** |
| 🤖 Automatización en CI/CD | **CLI** |
| ⚡ Despliegues rápidos | **CLI** |
| 🐚 Solo bash disponible | **Bash Interactivo** |

---

## 📋 Requisitos

### Autenticación GitLab
El token debe estar en: `/home/admin/Documents/GNP/PersonalGitLabToken`

```bash
# Verificar que existe
cat /home/admin/Documents/GNP/PersonalGitLabToken
```

### Autenticación GCP
```bash
gcloud auth login
gcloud config set project TU_PROJECT_ID
```

### Permisos requeridos
- `workflows.workflows.create`
- `workflows.workflows.update`
- `workflows.workflows.get`

---

## 🐛 Troubleshooting

### "GITLAB_TOKEN no definida"
```bash
# Solución
export GITLAB_TOKEN=$(cat ../../../../PersonalGitLabToken)
```

### "gcloud CLI no encontrado"
```bash
# Instalar Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

### "No se puede conectar a GitLab"
- Verificar conectividad a internet
- Verificar que la URL sea válida
- Verificar permisos del token

### "Error en validación del workflow"
- Verificar que el archivo YAML sea válido
- Usar `make deploy ... SKIP_VALIDATION=1` para saltarla (no recomendado)

---

## 📝 Notas

- Los despliegues se registran en `deployment_history.log`
- Los logs se guardan en `workflow.log`
- Se crea un archivo temporal durante el despliegue (se elimina automáticamente)
- El modo DRY-RUN simula el despliegue sin realizarlo realmente

---

## 📞 Soporte

Para problemas o sugerencias, contacta al equipo de Infrastructure.
