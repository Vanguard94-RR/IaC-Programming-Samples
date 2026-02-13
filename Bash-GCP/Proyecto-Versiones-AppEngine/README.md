# App Engine Version Manager

Script simple para eliminar versiones antiguas de App Engine.

## Instalación

Requiere:
- `gcloud` CLI
- `jq`

Instala con:
```bash
sudo apt-get install -y google-cloud-sdk jq
```

Luego autentica:
```bash
gcloud auth login
```

## Uso

```bash
./delete-appengine-versions.sh
```

El script preguntará:
1. ID del proyecto GCP
2. Qué servicio seleccionar
3. Qué política de retención usar
4. Confirmación para eliminar

## Políticas

- **recent-10**: Mantiene 10 versiones más recientes
- **recent-5**: Mantiene 5 versiones más recientes
- **monthly-3**: Una versión de cada mes (últimos 3 meses)
- **recent-N**: Personalizado (reemplaza N con un número)

## Seguridad

- La versión en servicio NUNCA se elimina
- Requiere confirmación explícita escribiendo "eliminar"
- Los logs se guardan en `logs/app-engine-versions.log`

## Archivos

- `delete-appengine-versions.sh` - Script principal
- `lib/common.sh` - Funciones comunes
- `lib/gcp-operations.sh` - Operaciones GCP
- `lib/ui.sh` - Interfaz de usuario
- `logs/` - Logs de operaciones
