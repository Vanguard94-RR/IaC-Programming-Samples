# Guía de Creación de PSC Endpoint en GCP

## Pasos Necesarios para Crear un PSC Endpoint

### 1. ANÁLISIS PREVIO

#### 1.1 Verificar Proyecto y APIs
```bash
gcloud projects describe PROJECT_ID
gcloud services list --project=PROJECT_ID --enabled | grep -E "compute|servicenetworking"
```

#### 1.2 Validar Red VPC
```bash
gcloud compute networks describe NETWORK_NAME --project=PROJECT_ID
gcloud compute networks subnets describe SUBNET_NAME \
  --region=REGION \
  --project=PROJECT_ID
```

#### 1.3 Identificar Service Attachment del Productor
```bash
# Service Attachment debe estar en formato:
# projects/PROJECT_ID/regions/REGION/serviceAttachments/ATTACHMENT_NAME
```

#### 1.4 Obtener Rango de IPs Disponibles
```bash
# El PSC IP debe estar dentro del rango VPC pero FUERA del rango de subnet
# Ejemplo:
#   - VPC: 10.156.0.0/16
#   - Subnet: 10.156.157.0/24
#   - PSC IP: 10.156.150.4 (dentro de 10.156.0.0/16, fuera de 10.156.157.0/24)
```

---

### 2. PRE-VALIDACIÓN (5 Checks)

```bash
# CHECK 1: Proyecto accesible
gcloud projects describe ${PROJECT_ID} --quiet

# CHECK 2: Red VPC existe
gcloud compute networks describe ${NETWORK_NAME} --project=${PROJECT_ID}

# CHECK 3: Subred existe
gcloud compute networks subnets describe ${SUBNETWORK_NAME} \
  --region=${REGION} \
  --project=${PROJECT_ID}

# CHECK 4: IP no existe previamente
gcloud compute addresses describe ${IP_ADDRESS_NAME} \
  --global \
  --project=${PROJECT_ID}

# CHECK 5: Compute API habilitada
gcloud services list --project=${PROJECT_ID} --enabled --filter="name:compute"
```

**Resultado esperado:** 5/5 checks pasados

---

### 3. CREACIÓN DEL PSC ENDPOINT (2 Pasos)

#### PASO 1: Crear Dirección PSC (Global con Propósito)

```bash
gcloud compute addresses create ${IP_ADDRESS_NAME} \
  --global \
  --addresses=${PSC_IP_ADDRESS} \
  --purpose=PRIVATE_SERVICE_CONNECT \
  --network=${NETWORK_NAME} \
  --project=${PROJECT_ID} \
  --quiet
```

**Parámetros críticos:**
- `--global`: DEBE ser global (no regional)
- `--addresses=IP`: IP específica (dentro del rango VPC, fuera de la subnet)
- `--purpose=PRIVATE_SERVICE_CONNECT`: Propósito requerido para PSC
- `--network`: Red VPC donde se conectará el PSC

**Resultado esperado:**
```
Created [https://www.googleapis.com/compute/v1/projects/.../global/addresses/...]
```

---

#### PASO 2: Crear Regla de Forwarding PSC (Regional)

```bash
gcloud compute forwarding-rules create ${IP_ADDRESS_NAME} \
  --region=${REGION} \
  --address=${IP_ADDRESS_NAME} \
  --network=${NETWORK_NAME} \
  --target-service-attachment=${TARGET_SERVICE_ATTACHMENT} \
  --target-service-attachment-region=${REGION} \
  --project=${PROJECT_ID} \
  --quiet
```

**Parámetros críticos:**
- `--region`: Regional (no global)
- `--address`: Referencia a la dirección PSC creada en Paso 1
- `--network`: OBLIGATORIO para PSC (fácil de olvidar)
- `--target-service-attachment`: Service attachment del productor
- `--target-service-attachment-region`: Región del service attachment

**Resultado esperado:**
```
Created [https://www.googleapis.com/compute/v1/projects/.../regions/REGION/forwardingRules/...]
```

---

### 4. POST-VALIDACIÓN (3 Verificaciones)

#### Verificación 1: Dirección PSC Creada
```bash
gcloud compute addresses describe ${IP_ADDRESS_NAME} \
  --global \
  --project=${PROJECT_ID} \
  --format='table(name,address,purpose,network)'
```

**Validar:**
- Name: correcto
- Address: IP asignada
- Purpose: PRIVATE_SERVICE_CONNECT
- Network: VPC correcta

---

#### Verificación 2: Regla de Forwarding PSC Creada
```bash
gcloud compute forwarding-rules describe ${IP_ADDRESS_NAME} \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format='table(name,IPAddress,target,loadBalancingScheme)'
```

**Validar:**
- Name: correcto
- IPAddress: IP de la dirección PSC
- Target: Service attachment correcto
- loadBalancingScheme: (vacío para PSC)

---

#### Verificación 3: Configuración de Red
```bash
gcloud compute networks subnets describe ${SUBNETWORK_NAME} \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format='value(ipCidrRange, network)'
```

**Validar:**
- Subnet CIDR correcta
- Network correcta

---

### 5. ARQUITECTURA DEL PSC ENDPOINT

```
┌─────────────────────────────────────────────────────────────┐
│ PROYECTO CONSUMIDOR (gnp-vida-emision-aesa-pro)           │
│                                                             │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ RED VPC: 10.156.0.0/16                                │ │
│ │                                                        │ │
│ │ ┌──────────────────────────────────────────────────┐  │ │
│ │ │ SUBNET: 10.156.157.0/24                         │  │ │
│ │ │ (Rango para recursos normales)                  │  │ │
│ │ └──────────────────────────────────────────────────┘  │ │
│ │                                                        │ │
│ │ PSC ADDRESS: 10.156.150.4 (Global)                   │ │
│ │ PSC FORWARDING RULE: Regional (us-central1)          │ │
│ │                                                        │ │
│ │      ↓ Conexión privada cifrada                       │ │
│ │      └─────────────────────────────────────────────┐  │ │
│ └────────────────────────────────────────────────────┼──┘ │
└─────────────────────────────────────────────────────┼─────┘
                                                       │
                ╔═══════════════════════════════════╗ │
                ║ PROYECTO PRODUCTOR               ║ │
                ║ (h68279829de7fa3d3p-tp)          ║ │
                ║                                   ║ │
                ║ SERVICE ATTACHMENT               ║ │
                ║ (Cloud SQL Private IP)           ║←┘
                ╚═══════════════════════════════════╝
```

---

### 6. ERRORES COMUNES Y SOLUCIONES

| Error | Causa | Solución |
|-------|-------|----------|
| `Invalid choice: 'private-service-connections'` | Comando incorrecto | Usar `forwarding-rules` no `private-service-connections` |
| `Invalid purpose for regional internal addresses` | Dirección regional con PSC purpose | Usar `--global` para dirección PSC |
| `No network specified for PSC forwarding rule` | Falta `--network` en forwarding rule | Agregar `--network=${NETWORK_NAME}` |
| `Invalid IP CIDR conflicts with subnet` | IP dentro del rango de subnet | Usar IP fuera del rango de subnet pero dentro del VPC |
| `Resource not found` | Address no creada antes de forwarding rule | Crear address primero, luego forwarding rule |
| `Invalid service attachment` | Service attachment incorrecto o no existe | Verificar formato y acceso al service attachment |

---

### 7. CONFIGURACIÓN RECOMENDADA

```bash
# Variables para ejecutar
PROJECT_ID="gnp-vida-emision-aesa-pro"
REGION="us-central1"
NETWORK_NAME="gnp-vida-emision-aesa-pro"
SUBNETWORK_NAME="gnp-vida-emision-aesa-pro"
IP_ADDRESS_NAME="aesa-psc-pro"
PSC_IP_ADDRESS="10.156.150.4"  # Dentro VPC, fuera de subnet

# Service Attachment (productor)
TARGET_SERVICE_ATTACHMENT="projects/h68279829de7fa3d3p-tp/regions/us-central1/serviceAttachments/a-0aa03743a37f-psc-service-attachment-10314d9441950c78"
```

---

### 8. SCRIPT COMPLETO

Consultar:
- [config.env](config.env) - Configuración
- [analyze.sh](analyze.sh) - Análisis técnico detallado
- [validate-pre.sh](validate-pre.sh) - Pre-validación (5 checks)
- [execute.sh](execute.sh) - Ejecución (2 pasos)
- [validate.sh](validate.sh) - Post-validación (3 verificaciones)

---

### 9. CHECKLIST DE CREACIÓN

- [ ] Proyecto GCP accesible
- [ ] APIs habilitadas (compute, servicenetworking)
- [ ] VPC y Subnet verificadas
- [ ] Service attachment del productor validado
- [ ] IP PSC identificada (dentro VPC, fuera subnet)
- [ ] Pre-validación: 5/5 checks ✓
- [ ] Dirección PSC creada (global, purpose PSC)
- [ ] Regla de Forwarding creada (regional, network especificada)
- [ ] Post-validación: 3/3 verificaciones ✓
- [ ] Conectividad funcional verificada (opcional)

---

### 10. SIGUIENTE: USO DEL PSC ENDPOINT

Una vez creado el PSC endpoint, los recursos en la red VPC pueden acceder al service attachment (Cloud SQL privado, etc.) usando la dirección PSC:

```bash
# Ejemplo: Conexión a Cloud SQL Private IP
mysql -h 10.156.150.4 -u user -p database
```

El PSC proporciona:
- ✓ Conexión privada (sin IP pública)
- ✓ Cifrado de Google network
- ✓ Acceso entre proyectos
- ✓ Control vía service attachment
