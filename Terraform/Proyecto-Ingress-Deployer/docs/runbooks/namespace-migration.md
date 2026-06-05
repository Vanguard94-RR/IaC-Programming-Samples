# Runbook: Migración de Ingress entre Namespaces

**Aplica a:** Tickets donde se solicita eliminar un ingress existente en un namespace (generalmente `default`) y desplegarlo en otro (`apps`) manteniendo la misma IP estática.

**Caso de referencia:** CTASK0370461 — `gnp-wsbancasegurogmm-pro`

---

## Síntomas que identifican este patrón

- El ticket indica "eliminar el ingress existente antes de instalar"
- El nuevo YAML usa la misma IP estática que el ingress actual
- El ingress cambia de namespace (e.g. `default` → `apps`)

---

## Riesgos

| Riesgo | Consecuencia | Prevención |
|---|---|---|
| Forwarding rule manual `https` en la misma IP | Error 400: IP in-use durante provisión LB | Eliminar antes del deploy |
| No esperar deprovisión del LB viejo | IP conflict con el LB en construcción | Verificar forwarding rules libres antes de deploy |
| Ventana de downtime | ~15-25 min sin servicio | Comunicar antes de ejecutar |

---

## Pre-requisitos

```bash
# 1. Verificar IP estática y qué forwarding rules la usan
gcloud compute addresses describe <ip-name> \
  --global --project=<PROJECT_ID> \
  --format="yaml(address,status,users)"

# 2. Si existe forwarding rule manual (sin prefijo k8s2-), eliminarla
gcloud compute forwarding-rules delete <nombre-manual> \
  --global --project=<PROJECT_ID>

# 3. Obtener credenciales del cluster
gcloud container clusters get-credentials <CLUSTER> \
  --project=<PROJECT_ID> --zone=<ZONE>
```

---

## Secuencia de ejecución

### Paso 1 — Eliminar ingress viejo

```bash
kubectl delete ingress <INGRESS_NAME> -n <NAMESPACE_ORIGEN>
```

Verificar que las forwarding rules GKE (`k8s2-*`) se eliminaron:

```bash
gcloud compute forwarding-rules list \
  --project=<PROJECT_ID> \
  --filter="IPAddress=<IP>" \
  --format="table(name,portRange)"
```

Esperar hasta que no quede ninguna regla usando la IP (~5-15 min).

### Paso 2 — Deploy con Ingress Deployer

```bash
TICKET_ID=<CTASK> \
PROJECT_ID=<PROJECT_ID> \
NAMESPACE=<NAMESPACE_DESTINO> \
STATIC_IP_NAME=<IP_NAME> \
INGRESS_URL=<GITLAB_URL> \
ACTION=apply \
CI=true \
make deploy
```

El deployer ejecutará automáticamente:
- Pre-flight check de IP conflicts (`check_ip_conflicts`)
- FrontendConfig auto-generado desde annotation
- Cloud Armor adjunto a backends
- Espera de IP assignment

### Paso 3 — Verificar

```bash
# Confirmar IP asignada
kubectl get ingress <INGRESS_NAME> -n <NAMESPACE_DESTINO>

# Confirmar solo existe en namespace destino
kubectl get ingress -A | grep <INGRESS_NAME>
```

### Paso 4 — Actualizar DNS (si IP cambió)

Si la IP del nuevo ingress es diferente a la original, actualizar registro DNS del dominio correspondiente.

---

## Caso ejecutado: CTASK0370461

| Campo | Valor |
|---|---|
| Proyecto | `gnp-wsbancasegurogmm-pro` |
| Cluster | `gke-gnp-wsbancasegurogmm-pro` (us-central1-f) |
| Namespace origen | `default` |
| Namespace destino | `apps` |
| Ingress name | `wsbancagmm-ingress` |
| IP estática | `ip-wsbancagmm` = `34.49.140.45` |
| SSL cert | `wildcarddigicertgnpcommx2023` (auto-detectado) |
| FrontendConfig | `http-redirect-config` (auto-generado) |
| Cloud Armor | `cve-canary` → 2 backends adjuntados |
| DNS | Sin cambio (misma IP) |

**Forwarding rule manual eliminada manualmente antes del deploy:** `https` (puerto 443)

---

## Mejora pendiente en Ingress Deployer

Este patrón requiere pasos manuales (delete + espera) que podrían automatizarse con:

- Flag `--delete-from-namespace=<ns>` — elimina el ingress del namespace origen y espera deprovisión LB antes de aplicar el nuevo
- O `ACTION=migrate` — orquesta delete + wait + deploy en un solo flujo

Ver memoria del proyecto para contexto de implementación futura.
