# GKE Cluster Creation — v4

Automated GKE cluster creation with modular Bash library structure. Single entrypoint with subcommand dispatch, dry-run support, and centralized logging.

**Version:** v4.0  
**Autor:** Juan Manuel Cortes  
**Última Actualización:** 2026-04-25

---

## Inicio Rápido

```bash
# Otorgar permisos
chmod +x bin/create_gke_cluster.sh

# Autenticarse en GCP
gcloud auth login
gcloud config set project PROJECT_ID

# Crear cluster (interactivo)
./bin/create_gke_cluster.sh create

# Crear cluster con parámetros pre-cargados (sin prompts)
./bin/create_gke_cluster.sh create \
  --project gnp-cfdi-qa \
  --cluster gke-gnp-cfdi-qa \
  --region us-central1 \
  --env qa
```

---

## Subcomandos

| Subcomando | Descripción |
|---|---|
| `create` (default) | Creación completa de cluster GKE (10 pasos) |
| `update-armor` | Aplicar/actualizar reglas de Cloud Armor |
| `rollback-armor` | Restaurar Cloud Armor desde backup JSON |
| `fix-shared-vpc` | Asociar proyecto de servicio a Shared VPC host |
| `log4j` | Aplicar o respaldar reglas WAF de log4j |

## Flags Globales

| Flag | Efecto |
|---|---|
| `--dry-run` | Imprime todas las llamadas gcloud/kubectl sin ejecutarlas |
| `--verbose` | Salida diagnóstica adicional |
| `--project <id>` | Pre-cargar project ID (omite prompt) |
| `--cluster <name>` | Pre-cargar nombre del cluster |
| `--region <region>` | Pre-cargar región GCP |
| `--env <qa\|uat\|pro>` | Pre-cargar ambiente (sets machine type, channel, fleet) |
| `-h, --help` | Mostrar ayuda y salir |

---

## Desarrollo y Pruebas

```bash
make lint    # shellcheck en todos los scripts
make test    # lint + smoke test (sin credenciales GCP)
make run     # ejecución interactiva
```

El smoke test usa `NO_CLUSTER=1 DRY_RUN=true` — ejecuta el flujo completo sin ninguna llamada real a GCP.

---

## Flujo de Ejecución (`create` — 10 pasos)

1. Recopilación de parámetros (respeta flags pre-cargados)
2. Habilitar APIs GCP (container, gkehub, compute)
3. Selección de VPC: existente / nueva / Shared VPC
4. Cloud NAT (obligatorio PRO, opcional QA/UAT)
5. Obtención dinámica de versión GKE vía `get_cluster_versions(region, channel)`
6. `gcloud container clusters create` con todos los flags
7. Registro en Fleet + configuración Workload Identity
8. Hardening: Cloud Armor policies + SSL policy TLS 1.2+
9. Deploy Twistlock DaemonSet (solo PRO)
10. Assets: namespace `apps`, KSA `apps-gke`, IAM SA `apps-sa`, WI binding

---

## Convenciones por Ambiente

| Env | Machine type | Channel | Fleet project |
|-----|-------------|---------|---------------|
| PRO | n2-standard-2 | regular | gnp-fleets-pro |
| UAT | n1-standard-2 | rapid | gnp-fleets-uat |
| QA | n1-standard-2 | rapid | gnp-fleets-qa |

Shared VPC host project: `gnp-red-data-central`

---

## Estructura

```
Proyecto-GKE-Cluster-Creation-v4/
├── bin/
│   └── create_gke_cluster.sh   # Entrypoint único
├── lib/
│   ├── ui.sh                   # UI TTY-aware (colores, spinners)
│   ├── utils.sh                # run_or_dry, prompt_or_arg, log
│   ├── vpc.sh                  # Selección VPC, Cloud NAT
│   ├── shared_vpc.sh           # Shared VPC permissions, detect ranges
│   ├── cluster.sh              # Orquestador 10 pasos, get_cluster_versions
│   ├── hardening.sh            # Cloud Armor (update/rollback/apply)
│   ├── workload_identity.sh    # Namespace, KSA, IAM SA, WI binding
│   ├── twistlock.sh            # DaemonSet deploy
│   ├── ssl.sh                  # Classic SSL certificate
│   └── log4j.sh                # log4j WAF rules (apply/backup)
├── config/
│   ├── daemonset.yaml          # Twistlock manifest
│   └── bundle.cer              # SSL certificate bundle
├── test/
│   ├── run-smoke.sh            # Smoke test (NO_CLUSTER=1)
│   └── fixtures/
│       └── cluster_params.env  # Mock fixture
├── logs/                       # Auto-creado en runtime
├── Makefile
├── CLAUDE.md
└── README.md
```

---

## Dependencias

- `gcloud` (Google Cloud SDK), autenticado
- `kubectl`
- `jq`
- `bash 5.0+`

## Permisos GCP Requeridos

**Proyecto de servicio:** `roles/container.admin`, `roles/compute.admin`, `roles/iam.securityAdmin`

**Proyecto host (Shared VPC):** `roles/compute.xpnAdmin`, `roles/compute.networkAdmin`

---

## Archivos de Datos (raíz)

- `cluster.csv` — nombres de clusters para operaciones batch
- `data-script.csv` — formato: `cluster_name,lb_url,backend_name,zone,project_id` (usado por `update-armor`)
- `log4j.csv` — lista de clusters para reglas log4j batch
