# Workflow Deployment - Google Cloud Workflows

Herramienta simple en Bash para desplegar workflows desde GitLab a Google Cloud Workflows.

## Características

- ✅ Interfaz interactiva paso a paso
- ✅ Descarga automática desde GitLab (ramas o tags)
- ✅ Validación de estructura YAML
- ✅ Despliegue directo con `gcloud`
- ✅ Modo dry-run para simulación
- ✅ Token GitLab auto-cargado
- ✅ Historial de despliegues

## Requisitos

- **Bash 4+**
- **gcloud CLI** (instalado y autenticado)
- **curl** (para descargar desde GitLab)
- **Token GitLab** en `/home/admin/Documents/GNP/PersonalGitLabToken`

## Instalación

```bash
# Clonar o copiar el proyecto
cd Proyecto-Workflow-Deployment

# Hacer ejecutable el script
chmod +x workflow-deploy-interactive.sh

# Crear archivo de configuración (opcional)
cat > .env.local << 'EOF'
# Configuración local (no se trackea en git)
GITLAB_TOKEN_PATH=../../../../PersonalGitLabToken
EOF
```

## Uso

### Modo Interactivo (Recomendado)

```bash
./workflow-deploy-interactive.sh
```

El script te guiará paso a paso:

1. **Paso 1: Fuente de GitLab**
   - Ingresar URL completa o detalles por separado
   - URL válida: `https://gitlab.com/grupo/proyecto/-/blob/rama/ruta/archivo.yml`

2. **Paso 2: Destino en Google Cloud**
   - Nombre del workflow
   - Project ID de GCP
   - Región (por defecto: `us-central1`)

3. **Paso 3: Opciones Adicionales**
   - Modo normal, dry-run o skip-validation

4. **Paso 4: Confirmación**
   - Revisar configuración
   - Confirmar despliegue

### Ejemplo

```bash
./workflow-deploy-interactive.sh

# Responder las preguntas interactivas
# La herramienta se encargará del resto
```

## Configuración del Token

El token GitLab se carga automáticamente desde uno de estos lugares (en orden):

1. Variable de ambiente `GITLAB_TOKEN`
2. Archivo `.env.local` en el directorio del script
3. Archivo `/home/admin/Documents/GNP/PersonalGitLabToken`

## Historial

Los despliegues se registran en `deployment_history.log`:

```
2026-03-10 10:05:30 | workflow-emision-danios | gnp-wf-danios-qa
2026-03-10 10:03:15 | workflow-test | gnp-wf-danios-qa
```

## Estructura del Proyecto

```
.
├── workflow-deploy-interactive.sh    # Script principal
├── .env.local                        # Variables de ambiente (no tracked)
├── .gitignore                        # Archivos ignorados
├── deployment_history.log            # Historial de despliegues
├── README.md                         # Este archivo
└── test-workflow.yaml                # Workflow de prueba
```

## Troubleshooting

### Error: GITLAB_TOKEN no disponible

```bash
# Asignar token manualmente
export GITLAB_TOKEN=$(cat ../../../../PersonalGitLabToken)
./workflow-deploy-interactive.sh
```

### Error: URL de GitLab inválida

Verifica que la URL esté en este formato:
```
https://gitlab.com/grupo/proyecto/-/blob/rama/ruta/archivo.yml
```

### Error: gcloud CLI no disponible

Instala gcloud SDK:
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### Error: El workflow debe tener un entry point 'main:'

El archivo YAML debe contener:
```yaml
main:
  steps:
    - step1:
        ...
```

## Licencia

GNP Infrastructure Team - 2026
