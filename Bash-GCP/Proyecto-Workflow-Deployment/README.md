# Workflow Deployment

Despliega workflows desde GitLab a **Google Cloud Workflows** directamente desde línea de comandos.

## Instalación

```bash
make install
```

Requiere:
- Python 3.8+
- pyyaml, requests
- gcloud CLI

## Uso

```bash
make deploy URL='<gitlab-url>' NAME='<workflow-name>' PROJECT='<gcp-project>'
```

### Parámetros Requeridos

| Parámetro | Descripción |
|-----------|-------------|
| `URL` | URL completa del archivo en GitLab |
| `NAME` | Nombre del workflow en GCP |
| `PROJECT` | Project ID de GCP |

### Parámetros Opcionales

| Parámetro | Descripción | Default |
|-----------|-------------|---------|
| `LOCATION` | Región de GCP | us-central1 |
| `DRY_RUN=1` | Simular sin desplegar | - |
| `SKIP_VALIDATION=1` | Omitir validación | - |

## Ejemplos

### Despliegue básico

```bash
make deploy \
  URL='https://gitlab.com/gitgnp/cotizadores/gke-gnp-danios-config-back-end/-/blob/celula-4/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml' \
  NAME='workflow-emision-danios' \
  PROJECT='gnp-wf-danios-qa'
```

### Dry-run (simular)

```bash
make deploy \
  URL='https://gitlab.com/grupo/proyecto/-/blob/main/workflow.yml' \
  NAME='mi-workflow' \
  PROJECT='mi-proyecto' \
  DRY_RUN=1
```

### Con ubicación específica

```bash
make deploy \
  URL='...' \
  NAME='workflow' \
  PROJECT='proyecto' \
  LOCATION='southamerica-east1'
```

### Sin validación

```bash
make deploy URL='...' NAME='wf' PROJECT='proj' SKIP_VALIDATION=1
```

## Uso directo con Python

```bash
export GITLAB_TOKEN=$(cat ../PersonalGitLabToken)

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

## Formato de URL

```
https://gitlab.com/grupo/proyecto/-/blob/rama/ruta/archivo.yml
                   └─────┬─────┘       └─┬─┘ └──────┬──────┘
                      proyecto        rama      archivo
```

## Requisitos GCP

```bash
# Autenticarse
gcloud auth login

# Habilitar API
gcloud services enable workflows.googleapis.com --project=PROJECT_ID
```

## Logs

```bash
make logs    # Ver últimos logs
make clean   # Limpiar logs
```
