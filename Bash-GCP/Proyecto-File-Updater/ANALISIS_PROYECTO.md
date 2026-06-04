# Análisis del Proyecto: GNP File Promotion

## 📋 Resumen Ejecutivo

**Proyecto-File-Updater** es un sistema de promoción automática de archivos entre repositorios de GitLab. Permite sincronizar archivos de configuración (principalmente YAMLs) desde repositorios de desarrollo a repositorios de infraestructura de forma segura, idempotente y auditable.

**Versión:** 1.0.0  
**Lenguaje:** Python 3  
**Dependencias:** requests

---

## 🎯 Propósito Principal

Automatizar la promoción de archivos de configuración (Deployment, GAE, etc.) entre repositorios GitLab sin intervención manual, manteniendo:
- **Trazabilidad**: Asociación a tickets de cambio (CTASK)
- **Idempotencia**: Ejecuciones múltiples no causan cambios innecesarios
- **Seguridad**: Control de acceso mediante tokens, logs auditables
- **Validación**: Dry-run antes de ejecución real

---

## 📁 Estructura del Proyecto

```
Proyecto-File-Updater/
├── promote-files.py              # Script principal de promoción
├── setup-config.py               # Setup interactivo de configuración
├── setup-user-install.py         # Setup de usuario (primera ejecución)
├── setup-user.py                 # Setup de usuario (no se usa actualmente)
├── promotion-config.json         # Configuración actual (producción)
├── promotion-config-test.json    # Configuración de pruebas
├── promotion-report.json         # Reporte generado después de ejecución
├── Makefile                      # Comandos automatizados
├── VERSION                       # 1.0.0
├── README.md                     # Documentación básica
├── DEPLOYMENT-GUIDE.md           # Guía de deployment completa
└── promotion.log                 # Logs de ejecución (generado)
```

---

## 🔧 Componentes Principales

### 1. **promote-files.py**
Script Python principal que implementa la lógica de promoción.

#### Clase Principal: `GitLabFilePromoter`

**Funcionalidades:**
- ✅ Validación de token GitLab
- ✅ Obtención de IDs de proyectos por ruta
- ✅ Obtención de contenido de archivos (codificado en base64)
- ✅ Creación/actualización de archivos en repositorios destino
- ✅ Detección de archivos similares cuando uno no existe
- ✅ Listado de archivos en directorios
- ✅ Comparación de contenido (idempotencia)
- ✅ Generación de reportes JSON
- ✅ Logging completo (archivo y consola)

**Métodos Clave:**

```python
validate_token()                    # Verifica validez del token
get_project_id(project_path)        # Obtiene ID del proyecto
get_file_content(project_id, path)  # Descarga archivo
create_or_update_file()             # Sube/actualiza archivo
file_exists_with_content()          # Verifica cambios (idempotencia)
find_similar_files()                # Sugiere archivos alternativos
promote()                           # Ejecuta la promoción completa
```

**Características de Confiabilidad:**
- Manejo de errores HTTP (404 = archivo no encontrado)
- Codificación segura de rutas con `requests.utils.quote()`
- Comparación base64 directa para idempotencia
- Sugerencias de archivos alternativos cuando hay errores

---

### 2. **setup-config.py**
Configurador interactivo que solicita URLs de GitLab y genera `promotion-config.json`.

**Funcionalidades:**
- Parse automático de URLs de GitLab
- Extrae: proyecto, rama, ruta de archivo
- Soporta limpiar parámetros query (`?ref_type=heads`)
- Soporta proyectos con múltiples niveles (`grupo/subgrupo/proyecto`)
- Solicita número de ticket (CTASK)

**Formato de entrada esperado:**
```
https://gitlab.com/gitgnp/foundry/repo/-/blob/rama/ruta/archivo.yaml
                  ^                 ^ proyecto ^ rama  ^ archivo
```

**Salida:** `promotion-config.json` con estructura de promociones

---

### 3. **setup-user-install.py**
Script de inicialización que solicita acrónimo de usuario una sola vez.

**Lógica:**
- ✅ Ejecutado durante `make install`
- ✅ Solicita acrónimo del usuario (máx 10 caracteres)
- ✅ Guarda en `promotion-config.json`
- ✅ No repite si ya existe usuario configurado

---

### 4. **Makefile**
Orquestación de comandos de automatización.

**Comandos Disponibles:**
```makefile
make help          # Muestra ayuda
make install       # Instala dependencias + setup de usuario
make setup         # Ejecuta setup-config.py interactivo
make promote       # Ejecuta promoción real (requiere token)
make promote-dry   # Simula promoción sin cambios (--dry-run)
make logs          # Muestra últimas 20 líneas de promotion.log
make clean         # Elimina logs y reportes
```

**Consideraciones Importantes:**
- 🔐 Token se lee de: `/home/admin/Documents/GNP/PersonalGitLabToken`
- 📍 Variable de entorno: `GITLAB_TOKEN`
- ⚠️ Ruta relativa: sube 4 niveles desde el proyecto

---

## 📊 Archivos de Configuración

### Estructura de `promotion-config.json`

```json
{
  "gitlab_url": "https://gitlab.com",
  "ticket": "CTASK0366234",
  "user": "JMCM",
  "promotions": [
    {
      "source": {
        "project": "gitgnp/bca/archivos_promocion_bca",
        "branch": "0.0.226"
      },
      "destination": {
        "project": "gitgnp/gcp/gke-config-files",
        "branch": "master"
      },
      "source_path": "GKE/selo/gke-bca-consulta-bonos/2.0/uat/...",
      "dest_path": "harness-manifests/gnp-baseunicaagentes/uat/..."
    }
  ]
}
```

**Campos:**
- `gitlab_url`: URL base de GitLab (típicamente https://gitlab.com)
- `ticket`: ID de ticket asociado (ej: CTASK0366234)
- `user`: Acrónimo del usuario que realiza promoción
- `promotions[].source`: Repositorio y rama de origen
- `promotions[].destination`: Repositorio y rama destino
- `source_path`: Ruta completa del archivo en origen
- `dest_path`: Ruta completa del archivo en destino

---

## 🔐 Seguridad

### Manejo de Tokens

1. **Generación del Token:**
   - Crear en: https://gitlab.com/profile/personal_access_tokens
   - Scopes requeridos: `api`, `read_repository`, `write_repository`

2. **Almacenamiento:**
   ```bash
   echo "token" > /home/admin/Documents/GNP/PersonalGitLabToken
   chmod 600 /home/admin/Documents/GNP/PersonalGitLabToken
   ```

3. **Uso:**
   - Inyectado vía variable de entorno `GITLAB_TOKEN`
   - Nunca almacenado en logs
   - Headers autenticados en cada request: `'PRIVATE-TOKEN': token`

### Control de Acceso

- **Acceso de lectura:** Repositorios de desarrollo
- **Acceso de escritura:** Repositorios de infraestructura
- **Validación de token:** Se valida antes de cualquier operación

---

## 📝 Reportes

### `promotion-report.json`
Generado automáticamente después de cada ejecución.

**Estructura esperada:**
```json
{
  "summary": {
    "ticket": "CTASK0366234",
    "user": "JMCM",
    "timestamp": "2024-01-15T10:30:45",
    "dry_run": false
  },
  "promotions": [
    {
      "source": "...",
      "destination": "...",
      "status": "success|skipped|error",
      "message": "Archivo promovido correctamente"
    }
  ]
}
```

**Estados Posibles:**
- ✅ `success`: Archivo creado/actualizado
- ⏭️ `skipped`: Sin cambios (idempotencia)
- ❌ `error`: Falló la operación

---

## 🚀 Workflow de Uso

### Instalación Inicial

```bash
cd /home/admin/Documents/GNP/Proyecto-File-Updater

# 1. Instalar
make install

# 2. Preparar token
echo "token" > ../PersonalGitLabToken
chmod 600 ../PersonalGitLabToken

# 3. Configurar
make setup  # Pegar URLs de GitLab
```

### Ejecución Diaria

```bash
# 1. Simular (sin cambios)
make promote-dry

# 2. Ejecutar (cambios reales)
make promote

# 3. Ver resultado
make logs
cat promotion-report.json
```

---

## 📊 Ejemplo de Caso de Uso

**Escenario:** Promocionar configuración de Deployment desde repositorio de desarrollo a producción.

1. **Origen:** 
   - Proyecto: `gitgnp/bca/archivos_promocion_bca`
   - Rama: `0.0.226`
   - Archivo: `GKE/selo/gke-bca-consulta-bonos/2.0/uat/Deployment-gke-bca-consulta-bonos.yaml`

2. **Destino:**
   - Proyecto: `gitgnp/gcp/gke-config-files`
   - Rama: `master`
   - Archivo: `harness-manifests/gnp-baseunicaagentes/uat/.../Deployment-gke-bca-consulta-bonos.yaml`

3. **Ticket:** `CTASK0366234`

4. **Usuario:** `JMCM`

**Resultado:** Archivo de deployment se sincroniza automáticamente, asegurando que la configuración esté actualizada en infraestructura.

---

## 🐛 Manejo de Errores

### Errores Comunes

| Error | Causa | Solución |
|-------|-------|----------|
| `❌ Archivo NO ENCONTRADO` | Ruta incorrecta | Revisar rutas en config, usar URLs de GitLab |
| `Token inválido o expirado` | Token expirado | Generar nuevo token en GitLab |
| `Timeout al validar token` | Conexión lenta | Reintentar, verificar conectividad |
| HTTP 404 | Archivo/proyecto no existe | Verificar existencia del repositorio |
| HTTP 401 | Permiso denegado | Verificar scopes del token |

### Sugerencias Inteligentes

Cuando no encuentra un archivo, el script sugiere alternativas:
```
❌ Archivo NO ENCONTRADO: ruta/archivo.yaml
   📋 Archivos similares disponibles:
      • ruta/archivo_old.yaml
      • ruta/app.yaml
   💡 Sugerencia: Revisar la ruta en promotion-config.json
```

---

## ✅ Características Principales

1. **Idempotencia**
   - Ejecutar múltiples veces no causa cambios innecesarios
   - Comparación de contenido base64

2. **Dry-Run**
   - `--dry-run` para simular sin hacer cambios
   - Importante antes de ejecutar en producción

3. **Trazabilidad**
   - Logs en `promotion.log`
   - Reportes JSON con status de cada promoción
   - Asociación a ticket CTASK

4. **Manejo de Errores Robusto**
   - Validación de token previo
   - Detección de archivos similares
   - Mensajes descriptivos

5. **API REST GitLab**
   - Uso completo de API v4
   - Soporta proyectos multinivel
   - Codificación segura de rutas

---

## 🔍 Aspectos Técnicos

### Dependencias

```python
import requests      # HTTP requests a GitLab API
import json          # Manejo de configuración
import base64        # Contenido de archivos
import logging       # Logs a archivo y consola
import argparse      # Parseo de argumentos CLI
```

### Tipos de Datos

- **Contenido de archivos:** Base64 (usado por API GitLab)
- **Configuración:** JSON
- **Reportes:** JSON
- **Logs:** Texto (file handler) + console

### API GitLab v4 Endpoints Utilizados

```
GET  /api/v4/user                                      # Validar token
GET  /api/v4/projects/{id}                            # Obtener proyecto
GET  /api/v4/projects/{id}/repository/files/{path}    # Obtener archivo
GET  /api/v4/projects/{id}/repository/tree            # Listar directorio
POST /api/v4/projects/{id}/repository/files/{path}    # Crear archivo
PUT  /api/v4/projects/{id}/repository/files/{path}    # Actualizar archivo
```

---

## 📈 Casos de Uso Principales

1. **Deployment Kubernetes (GKE)**
   - Sincronizar Deployment YAML desde desarrollo a producción

2. **Configuración GAE**
   - Actualizar `app.yaml` en repositorios de infraestructura

3. **Archivos Multinivel**
   - Soporta rutas complejas en repositorios grandes

4. **Cambios Controlados**
   - Asociados a tickets CTASK para auditoría

---

## 🎓 Lecciones de Arquitectura

✅ **Buenas Prácticas:**
- Separación de concerns (setup, promotion, reportes)
- Logging completo para auditoría
- Dry-run para validación previa
- Idempotencia para operaciones seguras
- Manejo robusto de errores con sugerencias

⚠️ **Áreas de Mejora Potencial:**
- Soporte para múltiples promociones simultáneas
- Rollback automático en caso de error
- Webhooks para automatización CI/CD
- UI web para administración
- Validación de esquema YAML antes de promoción

---

## 📚 Documentación Relacionada

- [README.md](README.md) - Guía rápida
- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Deployment completo
- [promotion-config.json](promotion-config.json) - Configuración en uso
- [Makefile](Makefile) - Comandos disponibles

---

**Última actualización:** 2024  
**Versión:** 1.0.0  
**Autor:** GNP Team
