# Proyecto PubSub Discovery - Enfoque en Suscripciones

Herramienta para descubrir, verificar y replicar suscripciones de Google Cloud Pub/Sub entre proyectos.

## Enfoque Principal

A diferencia del enfoque anterior, **este proyecto se enfoca en las SUSCRIPCIONES**, no en los temas:

1. **Descubre** todas las suscripciones con sus configuraciones completas
2. **Verifica** cuáles ya existen en el proyecto destino
3. **Replica** solo las suscripciones que falten

## Estructura

```
Proyecto-PubSub-Discovery/
├── SubscriptionsDiscovery.sh      # Descubre suscripciones del proyecto origen
├── SubscriptionsVerify.sh         # Verifica cuáles existen en proyecto destino
├── SubscriptionsReplicate.sh      # Replica solo las que faltan
├── README.md                      # Este archivo
└── subscriptions-exports/         # Directorio de salida
```

## Flujo de Trabajo

### Paso 1: Descubrir Suscripciones

Descubre todas las suscripciones en el proyecto origen:

```bash
./SubscriptionsDiscovery.sh --project mi-proyecto-origen
```

**Resultado:**
- Archivo JSON con todas las suscripciones y sus configuraciones
- Reporte de discovery

### Paso 2: Verificar en Proyecto Destino

Verifica cuáles suscripciones ya existen en el proyecto destino:

```bash
./SubscriptionsVerify.sh \
  --project mi-proyecto-destino \
  --source-file subscriptions-exports/subscriptions-*.json
```

**Resultado:**
- Archivo con suscripciones que YA existen
- Archivo con suscripciones que FALTAN
- Reporte de verificación

### Paso 3: Replicar Faltantes

Replica solo las suscripciones que no existen en el proyecto destino:

```bash
./SubscriptionsReplicate.sh \
  --source-file subscriptions-exports/subscriptions-*-MISSING-*.json \
  --target-project mi-proyecto-destino
```

**O ejecutar en modo dry-run primero:**

```bash
./SubscriptionsReplicate.sh \
  --source-file subscriptions-exports/subscriptions-*-MISSING-*.json \
  --target-project mi-proyecto-destino \
  --dry-run
```

## Opciones de Comandos

### SubscriptionsDiscovery.sh

```
-p, --project PROJECT_ID     ID del proyecto GCP (requerido)
-o, --output DIR             Directorio de salida (default: ./subscriptions-exports)
-h, --help                   Mostrar ayuda
```

### SubscriptionsVerify.sh

```
-p, --project PROJECT_ID     ID del proyecto destino (requerido)
-s, --source-file FILE       Archivo JSON de suscripciones (requerido)
-o, --output DIR             Directorio de salida
-h, --help                   Mostrar ayuda
```

### SubscriptionsReplicate.sh

```
-s, --source-file FILE       Archivo JSON de suscripciones (requerido)
-t, --target-project ID      ID del proyecto destino (requerido)
-d, --dry-run                Modo simulación (no realiza cambios)
-h, --help                   Mostrar ayuda
```

## Datos Replicados

Cada suscripción se replica con:

- **Nombre**: Identificador único
- **Tema**: Referencia al tema de Pub/Sub
- **ackDeadlineSeconds**: Tiempo límite de reconocimiento
- **messageRetentionDuration**: Duración de retención de mensajes
- **Filtro**: Filtro de mensajes (si aplica)
- **Labels**: Etiquetas personalizadas

No se replican automáticamente:
- IAM policies
- Dead letter policies (configuración avanzada)
- Push subscriptions (requiere configuración adicional)

## Ejemplo Completo

```bash
# 1. Descubrir suscripciones en proyecto origen
./SubscriptionsDiscovery.sh -p proyecto-origen

# 2. Revisar qué se descubrió
ls -la subscriptions-exports/
cat subscriptions-exports/DISCOVERY-REPORT-*.txt

# 3. Verificar en proyecto destino
./SubscriptionsVerify.sh \
  -p proyecto-destino \
  -s subscriptions-exports/subscriptions-proyecto-origen-*.json

# 4. Revisar qué falta
cat subscriptions-exports/VERIFY-REPORT-*.txt

# 5. Ver preview de replicación
./SubscriptionsReplicate.sh \
  -s subscriptions-exports/subscriptions-proyecto-origen-*-MISSING-*.json \
  -t proyecto-destino \
  --dry-run

# 6. Replicar faltantes
./SubscriptionsReplicate.sh \
  -s subscriptions-exports/subscriptions-proyecto-origen-*-MISSING-*.json \
  -t proyecto-destino

# 7. Verificar nuevamente (opcional)
./SubscriptionsVerify.sh \
  -p proyecto-destino \
  -s subscriptions-exports/subscriptions-proyecto-origen-*.json
```

## Características

✓ Descubrimiento completo de suscripciones  
✓ Exportación a JSON estructurado  
✓ Verificación inteligente de existencia  
✓ Replicación de solo lo que falta  
✓ Modo dry-run para validación  
✓ Preservación de todas las configuraciones  
✓ Manejo robusto de errores  
✓ Salida coloreada y legible  
✓ Reportes detallados  

## Requisitos

- `gcloud` CLI instalado y configurado
- `jq` para procesamiento JSON
- Acceso autenticado a los proyectos
- Permisos de Pub/Sub en los proyectos

## Instalación

```bash
# Hacer scripts ejecutables
chmod +x Subscriptions*.sh
```

## Ventajas de este Enfoque

1. **No duplica**: Solo replica lo que no existe
2. **Eficiente**: Evita errores por recursos duplicados
3. **Inteligente**: Compara antes de actuar
4. **Seguro**: Dry-run disponible en todas las operaciones
5. **Verificable**: Reportes detallados en cada paso

## Ejemplo de Salida

```
================================
PubSub Subscriptions Discovery - mi-proyecto
================================
✓ gcloud encontrado
✓ jq encontrado
✓ Autenticación GCP verificada
✓ Proyecto 'mi-proyecto' verificado
ℹ Directorio de salida: ./subscriptions-exports
ℹ Archivos serán guardados con timestamp: 20260213_140000

================================
Descubriendo Suscripciones
================================
ℹ Encontradas 5 suscripciones
ℹ Procesando: suscripcion-1
ℹ Procesando: suscripcion-2
  • suscripcion-1
  • suscripcion-2
  • suscripcion-3
  • suscripcion-4
  • suscripcion-5
```

## Notas Importantes

- Los archivos de exportación incluyen timestamp para evitar sobrescrituras
- Los archivos MISSING contienen solo las suscripciones faltantes
- Se recomienda siempre usar dry-run antes de replicar
- Los reportes son útiles para auditoría y validación

---

**Última actualización**: 2026-02-13
